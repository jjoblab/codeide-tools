#!/usr/bin/env python3
"""promote-smoke.py — bascule catalogue smoke pending → ok (commit mainteneur, ADR 0009).

Édition chirurgicale du YAML par regex (PAS de round-trip yaml.safe_dump :
les commentaires de documentation du catalogue seraient détruits) — même
patron que l'étape « Évidence smoke → catalogue » de publish.yml, généralisé
aux trois arches. Idempotent (déjà ok = message, pas d'erreur). Échec net si
un motif attendu est introuvable — jamais de repli silencieux.

Usage :
  promote-smoke.py <run_url> <émulation_arm:oui|non> <id>@<version>:<arch> ...

Exemple :
  promote-smoke.py https://github.com/jjoblab/codeide-tools/actions/runs/37429101295 \
      oui build-tools@36.0.0:arm build-tools@36.0.0:x86_64
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "catalog" / "components"


def flip(path: Path, version: str, arch: str, source: str) -> None:
    text = path.read_text(encoding="utf-8")
    # Début du bloc de la version (ligne '  "<version>":').
    m = re.search(r"^(?P<i>[ ]+)\"" + re.escape(version) + r"\":\n", text, re.MULTILINE)
    if not m:
        sys.exit(f"ÉCHEC : {path.name} : bloc « {version} » introuvable")
    start = m.end()
    # Fin du bloc : prochaine clé quotée de même niveau ou section de premier niveau.
    tail = text[start:]
    m2 = re.search(r"^[ ]+\"[^\"]+\":\n|^[a-z-]+:", tail, re.MULTILINE)
    end = start + (m2.start() if m2 else len(tail))
    block = text[start:end]
    pat = re.compile(
        r"^(?P<pre>[ ]+" + arch + r":[ ]+)\{ status: pending, reason: \"[^\"]*\" \}$",
        re.MULTILINE,
    )
    mb = pat.search(block)
    if not mb:
        if re.search(r"[ ]+" + arch + r":[ ]+\{ status: ok,", block):
            print(f"  {path.name} {version}/{arch} : déjà ok (idempotent)")
            return
        sys.exit(
            f"ÉCHEC : {path.name} : ligne smoke {arch} introuvable dans le bloc "
            f"« {version} » — vérifier le catalogue (échec net, pas de repli)"
        )
    newline = mb.group("pre") + '{ status: ok, source: "' + source + '" }'
    path.write_text(text[:start] + block[: mb.start()] + newline + block[mb.end() :] + text[end:], encoding="utf-8")
    print(f"  {path.name} {version}/{arch} : pending → ok")


def main() -> None:
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    run_url, emul_arm, specs = sys.argv[1], sys.argv[2], sys.argv[3:]
    if emul_arm not in ("oui", "non"):
        sys.exit(f"émulation_arm doit valoir oui|non (obtenu : {emul_arm})")
    pat = re.compile(r"^([a-z-]+)@([0-9][0-9.]*):(aarch64|arm|x86_64)$")
    bad = [s for s in specs if not pat.match(s)]
    if bad:
        sys.exit(f"specs invalides : {bad} — format attendu id@version:arch")
    print(f"bascule catalogue — évidence : {run_url}")
    for spec in specs:
        cid, version, arch = pat.match(spec).groups()
        source = f"{run_url} — smoke.yml bionic {arch} (install + verify --deep, téléchargement réel)"
        if arch == "arm" and emul_arm == "oui":
            source += " — CPU émulé qemu-arm, bionique réel"
        flip(CATALOG / f"{cid}.yaml", version, arch, source)
    print("catalogue basculé : régénérer les manifestes (build/gen-manifest.py)")


if __name__ == "__main__":
    main()
