#!/usr/bin/env python3
"""Génère les vecteurs de référence (tests/golden/) — partagés avec l'app CodeIDE.

Contenu (déterministe, régénérable à l'identique) :
  - manifest-test.json          : FAUX manifeste conforme 12.2 (l'app pointe sa
                                   constante configurable dessus en attendant
                                   l'URL réelle — prompt 2 § 12.7) ;
  - manifest-valid-minimal.json : manifeste minimal valide au schéma ;
  - manifest-invalide-*.json    : cas d'échec (champ requis absent, sha256
                                   invalide, URL non-HTTPS, installPath
                                   interdit, arch inconnue, schemaVersion
                                   erroné, sources vide…) ;
  - archives/*.tar.xz           : archives minuscules avec sommes connues,
                                   installables/verifiables par le CLI et
                                   l'app sans réseau ;
  - archives/manifest-sha-lié-mais-faux.json : archive réelle + somme
                                   volontairement erronée (cas d'échec).

Usage : python3 build/gen-golden.py  (régénère tests/golden à l'identique)
"""
from __future__ import annotations

import hashlib
import json
import subprocess
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
GOLDEN = REPO / "tests" / "golden"
ARCHIVES = GOLDEN / "archives"
SCHEMA = REPO / "schema" / "manifest.v2.schema.json"

SOURCE_DATE_EPOCH = "946684800"


def make_tar(stage: Path, top: str, out: Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    proc = subprocess.run(
        ["tar", "--sort=name", "--format=ustar", f"--mtime=@{SOURCE_DATE_EPOCH}",
         "--clamp-mtime", "--owner=0", "--group=0", "--numeric-owner",
         "-cf", "-", top],
        cwd=stage, check=True, stdout=subprocess.PIPE,
    )
    xz = subprocess.run(["xz", "-6", "-T1", "-c"], input=proc.stdout, check=True,
                        stdout=subprocess.PIPE)
    out.write_bytes(xz.stdout)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def write_json(path: Path, obj) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def component(cid, version, rev, arch, url, sha, size, install_path, critical=True,
              requires=None, verify=None, channel="stable", extra=None) -> dict:
    c = {
        "id": cid, "version": version, "revision": rev, "arch": arch,
        "channel": channel, "critical": critical,
        "sources": [{"url": url}],
        "sha256": sha, "size": size,
        "installPath": install_path,
        "requires": requires or [],
        "verify": verify or {"cmd": f"{install_path}/hello.txt", "expect": "hello"},
    }
    if extra:
        c.update(extra)
    return c


def main() -> None:
    if GOLDEN.exists():
        for f in sorted(GOLDEN.rglob("*"), reverse=True):
            if f.is_file() and f.suffix in (".json", ".xz", ".txt", ".sha256", ".md"):
                f.unlink()

    with tempfile.TemporaryDirectory() as tmp:
        # --- Deux archives minuscules, contenus connus -----------------------
        a1_stage = Path(tmp) / "a1"
        (a1_stage / "test-tools" / "1.0").mkdir(parents=True)
        hello = a1_stage / "test-tools" / "1.0" / "hello.txt"
        hello.write_text("hello v1\n", encoding="utf-8")
        hello.chmod(0o644)
        (a1_stage / "test-tools" / "1.0" / "run.sh").write_text("#!/bin/sh\necho test-tools 1.0\n", encoding="utf-8")
        (a1_stage / "test-tools" / "1.0" / "run.sh").chmod(0o755)
        make_tar(a1_stage, "test-tools", ARCHIVES / "test-tools-1.0-r1-any.tar.xz")

        a2_stage = Path(tmp) / "a2"
        (a2_stage / "test-tools" / "2.0").mkdir(parents=True)
        (a2_stage / "test-tools" / "2.0" / "hello.txt").write_text("hello v2\n", encoding="utf-8")
        (a2_stage / "test-tools" / "2.0" / "hello.txt").chmod(0o644)
        make_tar(a2_stage, "test-tools", ARCHIVES / "test-tools-2.0-r1-any.tar.xz")

        arch1 = (ARCHIVES / "test-tools-1.0-r1-any.tar.xz").read_bytes()
        arch2 = (ARCHIVES / "test-tools-2.0-r1-any.tar.xz").read_bytes()
        sum1, sum2 = sha256(arch1), sha256(arch2)

        # --- FAUX manifeste de test conforme 12.2 (12.7) ---------------------
        write_json(GOLDEN / "manifest-test.json", {
            "schemaVersion": 2,
            "generatedAt": "2026-10-05T12:00:00Z",
            "components": [
                component(
                    "test-tools", "1.0", "r1", "any",
                    url="https://example.invalid/test-tools-1.0-r1-any.tar.xz",
                    sha=sum1, size=len(arch1), install_path="test-tools/1.0",
                    critical=True, requires=["jdk>=17"],
                    verify={"cmd": "test-tools/1.0/run.sh", "expect": "test-tools 1.0"},
                ),
                component(
                    "test-tools", "2.0", "r1", "any",
                    url="https://example.invalid/test-tools-2.0-r1-any.tar.xz",
                    sha=sum2, size=len(arch2), install_path="test-tools/2.0",
                    channel="preview",
                ),
            ],
            "profiles": {
                "default": {"components": ["test-tools@1.0"]},
            },
            "compat": [
                {"agp": "9.4.1", "buildTools": "1.0", "aapt2": "1.0",
                 "compileSdk": "36", "jdk": ">=17", "status": "tested"},
            ],
        })

        # --- Manifeste minimal valide ----------------------------------------
        write_json(GOLDEN / "manifest-valid-minimal.json", {
            "schemaVersion": 2,
            "generatedAt": "2026-10-05T12:00:00Z",
            "components": [
                component(
                    "test-tools", "1.0", "r1", "any",
                    url="https://example.invalid/a.tar.xz",
                    sha=sum1, size=len(arch1), install_path="test-tools/1.0",
                ),
            ],
            "profiles": {"default": {"components": ["test-tools@1.0"]}},
            "compat": [
                {"agp": "8.13", "buildTools": "1.0", "aapt2": "1.0",
                 "compileSdk": "36", "jdk": ">=17", "status": "untested"},
            ],
        })

        # --- Cas d'échec : archive réelle, somme volontairement fausse --------
        write_json(GOLDEN / "archives" / "manifest-sha-errone.json", {
            "schemaVersion": 2,
            "generatedAt": "2026-10-05T12:00:00Z",
            "components": [
                component(
                    "test-tools", "1.0", "r1", "any",
                    url="https://example.invalid/test-tools-1.0-r1-any.tar.xz",
                    sha="0" * 64, size=len(arch1), install_path="test-tools/1.0",
                ),
            ],
            "profiles": {"default": {"components": ["test-tools@1.0"]}},
            "compat": [
                {"agp": "9.4.1", "buildTools": "1.0", "aapt2": "1.0",
                 "compileSdk": "36", "jdk": ">=17", "status": "untested"},
            ],
        })

    # --- Manifestes invalides (le schéma doit les REJETER) --------------------
    good = json.loads((GOLDEN / "manifest-valid-minimal.json").read_text(encoding="utf-8"))

    def variant(name: str, mutate) -> None:
        obj = json.loads(json.dumps(good))
        mutate(obj)
        write_json(GOLDEN / f"manifest-invalide-{name}.json", obj)

    variant("champ-requis-absent", lambda o: o["components"][0].pop("sha256"))
    variant("sha256-majuscule", lambda o: o["components"][0].update(sha256="A" * 64))
    variant("sha256-court", lambda o: o["components"][0].update(sha256="abc123"))
    variant("url-non-https", lambda o: o["components"][0].update(sources=[{"url": "http://example.invalid/a.tar.xz"}]))
    variant("url-relative", lambda o: o["components"][0].update(sources=[{"url": "archives/a.tar.xz"}]))
    variant("sources-vide", lambda o: o["components"][0].update(sources=[]))
    variant("installpath-parent", lambda o: o["components"][0].update(installPath="../escape"))
    variant("installpath-absolu", lambda o: o["components"][0].update(installPath="/etc/test"))
    variant("arch-inconnue", lambda o: o["components"][0].update(arch="mips"))
    variant("schema-version", lambda o: o.update(schemaVersion=1))
    variant("verify-absent", lambda o: o["components"][0].pop("verify"))
    variant("version-invalide", lambda o: o["components"][0].update(version="trente-six"))
    # Cas SEMANTIQUE (rejeté par la résolution client, pas par le schéma) :
    # profil référençant un composant absent du manifeste.
    write_json(GOLDEN / "manifest-invalide-semantique-profil.json", {
        "schemaVersion": 2,
        "generatedAt": "2026-10-05T12:00:00Z",
        "components": [
            component(
                "test-tools", "1.0", "r1", "any",
                url="https://example.invalid/a.tar.xz",
                sha=sum1, size=len(arch1), install_path="test-tools/1.0",
            ),
        ],
        "profiles": {"default": {"components": ["ghost@1.0"]}},
        "compat": [
            {"agp": "8.13", "buildTools": "1.0", "aapt2": "1.0",
             "compileSdk": "36", "jdk": ">=17", "status": "untested"},
        ],
    })
    variant("channel-invalide", lambda o: o["components"][0].update(channel="beta"))

    # --- Sommes annexes -------------------------------------------------------
    for name in ("test-tools-1.0-r1-any.tar.xz", "test-tools-2.0-r1-any.tar.xz"):
        data = (ARCHIVES / name).read_bytes()
        (ARCHIVES / f"{name}.sha256").write_text(f"{sha256(data)}  {name}\n", encoding="utf-8")

    # --- Validation : le faux manifeste et le minimal passent le schéma -------
    import jsonschema
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    for path in (GOLDEN / "manifest-test.json", GOLDEN / "manifest-valid-minimal.json",
                 GOLDEN / "archives" / "manifest-sha-errone.json"):
        jsonschema.validate(json.loads(path.read_text(encoding="utf-8")), schema)
    invalid = sorted(p for p in GOLDEN.glob("manifest-invalide-*.json")
                     if "semantique" not in p.name)
    assert invalid, "aucun vecteur invalide généré"
    rejected = 0
    for path in invalid:
        try:
            jsonschema.validate(json.loads(path.read_text(encoding="utf-8")), schema)
        except jsonschema.ValidationError:
            rejected += 1
    if rejected != len(invalid):
        raise SystemExit(f"{len(invalid) - rejected} vecteur(s) « invalide » passent le schéma !")

    (GOLDEN / "README.md").write_text(
        "# Vecteurs de référence (tests/golden/)\n\n"
        "Partagés entre ce dépôt (tests CLI, CI) et l'app CodeIDE (prompt 1,\n"
        "importés dans ses tests — contrat 12.7).\n\n"
        "- `manifest-test.json` : **faux manifeste conforme 12.2** — cible de la\n"
        "  constante configurable de l'app tant que l'URL Pages réelle n'est pas\n"
        "  activée (§ 12.7). Ses composants pointent vers `archives/`.\n"
        "- `manifest-valid-minimal.json` : manifeste minimal valide au schéma.\n"
        "- `manifest-invalide-*.json` : 14 cas que le schéma doit REJETER\n"
        "  (champ requis absent, sha256 mal formé, URL non HTTPS/relative,\n"
        "  installPath `..`/absolu, arch inconnue, schemaVersion erroné, …).\n"
        "- `archives/*.tar.xz` : archives minuscules aux sommes connues\n"
        "  (racine = racine du SDK, contrat 12.3) ;\n"
        "  `manifest-sha-errone.json` : archive réelle + somme fausse\n"
        "  (l'installation doit échouer proprement).\n\n"
        "Régénération déterministe : `python3 build/gen-golden.py`\n"
        "(les octets sont stables : tar trié + mtime fixé + xz -T1).\n",
        encoding="utf-8",
    )
    print(f"vecteurs générés dans {GOLDEN} ({len(invalid)} invalides rejetés par le schéma ✓)")


if __name__ == "__main__":
    main()
