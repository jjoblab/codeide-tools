#!/usr/bin/env python3
"""get_source.py (adapté codeide-tools) — clone les sources AOSP aux COMMITS
épinglés du catalogue (catalog/upstream/aosp.yaml → pins.json).

Différence avec l'amont Lzhiyong (Apache-2.0, recette vendue — NOTICE.md) :
l'original clone tous les dépôts à un même tag ; cette version clone chaque
dépôt au commit EXACT résolu depuis le pin — immuable et reproductible, même
si un dépôt amont déplace ou supprime ses tags.

Usage :
  python3 get_source.py --pins pins.json [--root DIR]
  (le répertoire racine contient src/ ; ce script vit à côté de patches/)
Écrit : <root>/sources-resolues.json (journal des commits — provenance).
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent

# Les sources peuvent venir d'un cache CI restauré sous un autre propriétaire
# (conteneur root → cache du runner) : sans ceci, git échoue en 128
# (« dubious ownership »).
GIT = ["git", "-c", "safe.directory=*"]


def run(cmd: list[str], cwd: Path | None = None) -> None:
    print("+ " + " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=cwd, check=True)


def clone_at_ref(url: str, tag: str, pinned_commit: str, dest: Path) -> None:
    """Clone le dépôt au tag AOSP puis VÉRIFIE que le commit résolu égale le
    pin. android.googlesource.com refuse le fetch par SHA brut (HTTP 500,
    constaté 2026-10-06) : on fetch le tag, on contrôle l'immuabilité ensuite —
    un tag déplacé amont provoque un échec NET (jamais de repli silencieux)."""
    if (dest / ".git").exists():
        head = subprocess.run(GIT + ["rev-parse", "HEAD"], cwd=dest,
                              capture_output=True, text=True, check=True)
        if head.stdout.strip() == pinned_commit:
            print(f"= {dest.name:35s} déjà à {pinned_commit[:12]}")
            return
        raise SystemExit(f"{dest} existe à un autre commit — retirez-le")
    dest.mkdir(parents=True)
    run(GIT + ["init", "-q", str(dest)])
    run(GIT + ["-C", str(dest), "fetch", "-q", "--depth", "1",
               url, f"refs/tags/{tag}"])
    resolved = subprocess.run(
        GIT + ["-C", str(dest), "rev-parse", "FETCH_HEAD^{commit}"],
        capture_output=True, text=True, check=True).stdout.strip()
    if resolved != pinned_commit:
        raise SystemExit(
            f"IMMUABILITÉ : {dest.name} tag {tag} résout {resolved[:12]} "
            f"≠ pin catalogue {pinned_commit[:12]} — l'amont a déplacé le tag ; "
            f"re-résolvez les pins (catalog/upstream/aosp.yaml)")
    run(GIT + ["-C", str(dest), "checkout", "-q", "--detach", resolved])


def sed(pattern: str, target: Path) -> None:
    run(["sed", "-i", pattern, str(target)])


def apply_git_patches(root: Path) -> None:
    """Patchs git de la recette, appliqués depuis les VRAIES sources
    (real_src = root/src résolu — GNU patch ne suit pas les liens
    symboliques dans les composants du chemin, constaté en CI).

    Niveaux de strip par convention de l'amont (mixte) :
      - a/src/<repo>/…  (protobuf, task_runner) → -p2 depuis real_src ;
      - a/<repo>/…      (art, base)             → -p1 depuis real_src.
    protobuf est REQUIS (config.h du protoc hôte + includes Android du
    cross-build). « Reversed (or previously applied) » (reprise sur cache)
    est un SUCCÈS : l'état voulu est déjà atteint — GNU patch sort 1 même
    dans ce cas, on ne doit pas l'interpréter comme un échec."""
    real_src = (root / "src").resolve()
    p = SCRIPT_DIR / "patches"
    strict = {"protobuf_CMakeLists.txt.patch": 2}
    tolerant = {
        "task_runner.h.patch": 2,
        "StringPiece.h.patch": 1,
        "dex_file.cc.patch": 1,
        "instruction_set.h.patch": 1,
        "mem_map.cc.patch": 1,
    }
    base = ["patch", "--batch", "--forward", "--no-backup-if-mismatch",
            "-d", str(real_src)]
    for name, strip in {**strict, **tolerant}.items():
        cmd = base + [f"-p{strip}", "-i", str(p / name)]
        r = subprocess.run(cmd, capture_output=True, text=True)
        out = (r.stdout + r.stderr)
        deja = "Reversed (or previously applied) patch detected" in out
        if r.returncode != 0 and not deja:
            if name in strict:
                raise SystemExit(f"patch REQUIS en échec : {name}\n{out}")
            print(f"⚠ {name} : non appliqué (portage à évaluer — voir .rej)")
        elif r.returncode != 0 and deja:
            print(f"= {name} : déjà appliqué (cache)")


def apply_patches(root: Path) -> None:
    """Reprise de l'amont, chemins réécrits vers les VRAIES sources
    (real_src) — les liens symboliques de mise en page sont évités."""
    src = (root / "src").resolve()
    inc = src / "incremental_delivery/sysprop/include"
    inc.mkdir(parents=True, exist_ok=True)
    p = SCRIPT_DIR / "patches"
    shutil.copy2(p / "misc/IncrementalProperties.sysprop.h", inc)
    shutil.copy2(p / "misc/IncrementalProperties.sysprop.cpp", inc.parent)
    shutil.copy2(p / "misc/deployagent.inc", src / "adb/fastdeploy/deployagent")
    shutil.copy2(p / "misc/deployagentscript.inc", src / "adb/fastdeploy/deployagent")
    soong_inc = src / "soong/cc/libbuildversion/include"
    soong_inc.mkdir(parents=True, exist_ok=True)
    shutil.copy2(p / "misc/platform_tools_version.h", soong_inc)

    sed(r"s#frameworks/base/tools/aapt2/Resources.proto#Resources.proto#g",
        src / "base/tools/aapt2/ApkInfo.proto")
    sed(r"s#frameworks/base/tools/aapt2/Configuration.proto#Configuration.proto#g",
        src / "base/tools/aapt2/Resources.proto")
    sed(r"s#frameworks/base/tools/aapt2/Configuration.proto#Configuration.proto#g",
        src / "base/tools/aapt2/ResourcesInternal.proto")
    sed(r"s#frameworks/base/tools/aapt2/Resources.proto#Resources.proto#g",
        src / "base/tools/aapt2/ResourcesInternal.proto")
    sed(r"s#/usr/src/googletest#${CMAKE_SOURCE_DIR}/src/googletest#g",
        src / "abseil-cpp/CMakeLists.txt")

    # boringssl android-16 : le CMakeLists amont épie C++14 mais span.h
    # exige C++17 (std::is_convertible_v) — sinon échec de compilation croisée.
    bor = src / "boringssl/CMakeLists.txt"
    if bor.exists():
        sed(r"s#set(CMAKE_CXX_STANDARD 14)#set(CMAKE_CXX_STANDARD 17)#", bor)

    # libbase + liblog android-16 : properties.cpp utilise __system_property_serial/
    # __system_property_area_serial — exportées par libc depuis API 19/21 et 23
    # (bionic libc.map.txt) mais JAMAIS déclarées par les en-têtes NDK curatés
    # (vérifié jusqu'à API 34). En-tête de déclaration vendu (compat/) :
    # insertion gardée (idempotente) en tête de chaque properties.cpp.
    for props in (src / "libbase/properties.cpp",
                  src / "logging/liblog/properties.cpp"):
        if props.exists():
            text = props.read_text(encoding="utf-8", errors="replace")
            if "__system_property_area_serial" in text and \
                    "system_properties_compat.h" not in text:
                props.write_text(
                    '#include "bionic/system_properties_compat.h"\n' + text,
                    encoding="utf-8")
                print(f"= {props.name} ({props.parent.name}) : en-tête compat bionic inséré")

    # liblog android-16 : __android_log_logd_logger_with_timestamp est DÉFINIE
    # dans liblog lui-même mais déclarée API 37 dans les en-têtes NDK (r27c
    # culmine à 35) — l'appel interne est rejeté par clang. Renommage local
    # (aucun consommateur du nom public : API 37 jamais appelable par nos
    # outils) + déclaration avancée (le log.h amont ne déclare plus le nom
    # renommé, et la définition suit l'appel).
    logw = src / "logging/liblog/logger_write.cpp"
    if logw.exists():
        lw = logw.read_text(encoding="utf-8", errors="replace")
        fwd_mark = ("void __codeide_logd_logger_ts"
                    "(const struct __android_log_message*,")
        if fwd_mark not in lw:
            # renommage (no-op si déjà fait par une exécution antérieure)
            lw = lw.replace("__android_log_logd_logger_with_timestamp",
                            "__codeide_logd_logger_ts")
            anchor = ("void __android_log_logd_logger"
                      "(const struct __android_log_message* log_message) {")
            fwd = (fwd_mark + "\n"
                   "                              const struct timespec*);\n")
            if anchor in lw:
                lw = lw.replace(anchor, fwd + anchor, 1)
            logw.write_text(lw, encoding="utf-8")
            print("= liblog/logger_write.cpp : _with_timestamp renommée (API 37) "
                  "+ déclaration avancée")

    # googletest → boringssl/third_party/googletest (lien symbolique)
    run(["ln", "-sfn", str(src / "googletest"),
         str(src / "boringssl/src/third_party/googletest")])

    apply_git_patches(root)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pins", required=True, help="JSON {tag, repos: {path: commit}}")
    parser.add_argument("--root", default=".", help="racine de travail (contient src/)")
    args = parser.parse_args()

    for tool in ("git", "go", "bison", "flex"):
        if shutil.which(tool) is None:
            raise SystemExit(f"outil manquant : {tool} (installez le paquet)")

    pins_doc = json.loads(Path(args.pins).read_text())
    pins = pins_doc["repos"]
    aosp_tag = pins_doc["tag"]
    repos = json.loads((SCRIPT_DIR / "repos.json").read_text())
    url_of = {r["path"]: r["url"] for r in repos}

    root = Path(args.root).resolve()
    (root / "src").mkdir(parents=True, exist_ok=True)

    resolved = {}
    for path, commit in pins.items():
        if path not in url_of:
            raise SystemExit(f"dépôt inconnu dans repos.json : {path}")
        clone_at_ref(url_of[path], aosp_tag, commit, root / path)
        head = subprocess.run(GIT + ["rev-parse", "HEAD"], cwd=root / path,
                              capture_output=True, text=True, check=True)
        resolved[path] = head.stdout.strip()

    apply_patches(root)

    (root / "sources-resolues.json").write_text(
        json.dumps({"tag": aosp_tag, "repos": resolved}, indent=2),
        encoding="utf-8")
    print(f"sources prêtes : {len(resolved)} dépôts "
          f"(journal : {(root / 'sources-resolues.json').name})")


if __name__ == "__main__":
    main()
