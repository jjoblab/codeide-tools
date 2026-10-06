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


def run(cmd: list[str], cwd: Path | None = None) -> None:
    print("+ " + " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=cwd, check=True)


def clone_at_ref(url: str, tag: str, pinned_commit: str, dest: Path) -> None:
    """Clone le dépôt au tag AOSP puis VÉRIFIE que le commit résolu égale le
    pin. android.googlesource.com refuse le fetch par SHA brut (HTTP 500,
    constaté 2026-10-06) : on fetch le tag, on contrôle l'immuabilité ensuite —
    un tag déplacé amont provoque un échec NET (jamais de repli silencieux)."""
    if (dest / ".git").exists():
        head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=dest,
                              capture_output=True, text=True, check=True)
        if head.stdout.strip() == pinned_commit:
            print(f"= {dest.name:35s} déjà à {pinned_commit[:12]}")
            return
        raise SystemExit(f"{dest} existe à un autre commit — retirez-le")
    dest.mkdir(parents=True)
    run(["git", "init", "-q", str(dest)])
    run(["git", "-C", str(dest), "fetch", "-q", "--depth", "1",
         url, f"refs/tags/{tag}"])
    resolved = subprocess.run(
        ["git", "-C", str(dest), "rev-parse", "FETCH_HEAD^{commit}"],
        capture_output=True, text=True, check=True).stdout.strip()
    if resolved != pinned_commit:
        raise SystemExit(
            f"IMMUABILITÉ : {dest.name} tag {tag} résout {resolved[:12]} "
            f"≠ pin catalogue {pinned_commit[:12]} — l'amont a déplacé le tag ; "
            f"re-résolvez les pins (catalog/upstream/aosp.yaml)")
    run(["git", "-C", str(dest), "checkout", "-q", "--detach", resolved])


def sed(pattern: str, target: Path) -> None:
    run(["sed", "-i", pattern, str(target)])


def apply_patches(root: Path) -> None:
    """Reprise de l'amont, chemins réécrits : patchs depuis SCRIPT_DIR,
    cibles sous root/src/ (exécution avec CWD = root)."""
    src = root / "src"
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

    sed(r"s#frameworks/base/tools/aapt2/Configuration.proto#Configuration.proto#g",
        src / "base/tools/aapt2/ApkInfo.proto")
    sed(r"s#frameworks/base/tools/aapt2/Resources.proto#Resources.proto#g",
        src / "base/tools/aapt2/Resources.proto")
    sed(r"s#frameworks/base/tools/aapt2/Configuration.proto#Configuration.proto#g",
        src / "base/tools/aapt2/ResourcesInternal.proto")
    sed(r"s#frameworks/base/tools/aapt2/Resources.proto#Resources.proto#g",
        src / "base/tools/aapt2/ResourcesInternal.proto")
    sed(r"s#/usr/src/googletest#${CMAKE_SOURCE_DIR}/src/googletest#g",
        src / "abseil-cpp/CMakeLists.txt")

    # googletest → boringssl/third_party/googletest (lien symbolique)
    run(["ln", "-sfn", str(src / "googletest"),
         str(src / "boringssl/src/third_party/googletest")])


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
        head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=root / path,
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
