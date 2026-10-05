#!/usr/bin/env python3
"""Contrôle ELF d'un binaire natif : classe, machine, liaison, note Android.

Sortie JSON : {path, class, machine, static, androidApi, ndk} — et exit 1 si
l'ABI ne correspond pas à l'architecture attendue (équivalent du
assertAapt2Arch d'AndroidIDE, prompt 2 § 6).

Usage : python3 build/check-elf.py <fichier> <arch attendue>
Archives : aarch64 (EM_AARCH64, 64 bits), arm (EM_ARM, 32 bits),
x86_64 (EM_X86_64, 64 bits).
"""
from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

MACHINES = {
    0x28: "arm",       # EM_ARM (32 bits)
    0xB7: "aarch64",   # EM_AARCH64
    0x3E: "x86_64",    # EM_X86_64
}


def read_elf(path: Path) -> dict:
    data = path.read_bytes()
    if data[:4] != b"\x7fELF":
        raise ValueError(f"{path} : pas un fichier ELF")
    ei_class = data[4]          # 1 = 32 bits, 2 = 64 bits
    ei_data = data[5]           # 1 = little endian
    if ei_data != 1:
        raise ValueError(f"{path} : gros boutiste, inattendu pour Android")
    if ei_class == 2:
        # e_machine @ offset 18 (uint16 LE), e_type @ 16, e_phoff @ 32, e_shoff @ 40
        e_type = struct.unpack_from("<H", data, 16)[0]
        e_machine = struct.unpack_from("<H", data, 18)[0]
        e_shoff = struct.unpack_from("<Q", data, 40)[0]
        e_shentsize = struct.unpack_from("<H", data, 58)[0]
        e_shnum = struct.unpack_from("<H", data, 60)[0]
        e_shstrndx = struct.unpack_from("<H", data, 62)[0]
    else:
        e_type = struct.unpack_from("<H", data, 16)[0]
        e_machine = struct.unpack_from("<H", data, 18)[0]
        e_shoff = struct.unpack_from("<I", data, 32)[0]
        e_shentsize = struct.unpack_from("<H", data, 46)[0]
        e_shnum = struct.unpack_from("<H", data, 48)[0]
        e_shstrndx = struct.unpack_from("<H", data, 50)[0]

    # Liaison : un exécutable statique n'a pas de section .dynamic (PT_DYNAMIC
    # absent). On cherche PT_DYNAMIC dans les en-têtes de programme.
    has_dynamic = False
    note_api = ndk = None
    if e_type == 2 or e_type == 3:  # EXEC / DYN
        phoff = struct.unpack_from("<Q" if ei_class == 2 else "<I", data, 32 if ei_class == 2 else 28)[0]
        phentsize = struct.unpack_from("<H", data, 54 if ei_class == 2 else 42)[0]
        phnum = struct.unpack_from("<H", data, 56 if ei_class == 2 else 44)[0]
        for i in range(phnum):
            off = phoff + i * phentsize
            p_type = struct.unpack_from("<I", data, off)[0]
            if p_type == 2:  # PT_DYNAMIC
                has_dynamic = True
                break
    # Note .note.android.ident (NT_ANDROID_IDENT) : NDK + API cible.
    if e_shoff and e_shnum:
        sh = []
        for i in range(e_shnum):
            base = e_shoff + i * e_shentsize
            name_off, sh_type = struct.unpack_from("<II", data, base)[:2]
            sh.append((name_off, sh_type, base))
        shstr_base = e_shoff + e_shstrndx * e_shentsize
        shstr_off = struct.unpack_from("<Q", data, shstr_base + 24)[0] if ei_class == 2 else struct.unpack_from("<I", data, shstr_base + 16)[0]
        for name_off, sh_type, base in sh:
            name_end = data.index(b"\x00", shstr_off + name_off)
            name = data[shstr_off + name_off : name_end].decode("ascii", "replace")
            if name == ".note.android.ident":
                off = struct.unpack_from("<Q", data, base + 24)[0] if ei_class == 2 else struct.unpack_from("<I", data, base + 16)[0]
                size = struct.unpack_from("<Q", data, base + 32)[0] if ei_class == 2 else struct.unpack_from("<I", data, base + 20)[0]
                # note : namesz(4) + descsz(4) + type(4) + nom "Android\0" (8)
                # desc  : API(4) + version NDK (8, ex. "r27b\0\0\0\0")
                desc_off = off + 12 + 8
                api = struct.unpack_from("<I", data, desc_off)[0]
                ndk_bytes = data[desc_off + 4 : desc_off + 12]
                ndk = ndk_bytes.split(b"\x00")[0].decode("ascii", "replace") or None
                note_api = api
                break
    return {
        "path": str(path),
        "class": 64 if ei_class == 2 else 32,
        "machine": MACHINES.get(e_machine, f"unknown({e_machine:#x})"),
        "static": not has_dynamic,
        "androidApi": note_api,
        "ndk": ndk,
    }


def main() -> None:
    path, expected = Path(sys.argv[1]), sys.argv[2]
    if not path.is_file():
        print(json.dumps({"error": f"fichier absent : {path}"}))
        sys.exit(1)
    try:
        info = read_elf(path)
    except ValueError as exc:
        print(json.dumps({"error": str(exc)}))
        sys.exit(1)
    ok = info["machine"] == expected
    print(json.dumps(info))
    if not ok:
        print(f"ABI ELFE {info['machine']} != {expected} attendu : {path}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
