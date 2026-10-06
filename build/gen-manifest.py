#!/usr/bin/env python3
"""Générateur de manifestes codeide-tools (v2 + v1 dérivé + COMPAT.md).

Le catalogue (catalog/) est la seule source de vérité ; ce script en dérive :
  - dist/manifest.v2.json   : manifeste v2 conforme à schema/manifest.v2.schema.json
  - manifest.json           : manifeste v1 (rétrocompatibilité, URLs des releases existantes)
  - docs/COMPAT.md          : matrice de compatibilité générée depuis catalog/compat.yaml

Un composant n'entre dans le manifeste v2 que s'il a des sommes d'archive :
  - composants reconditionnés (build-tools, platform-tools) : build/artifacts.json,
    produit par build/package.sh (jamais inventé ici) ;
  - composants pointeurs (cmdline-tools, platform) : sommes épinglées de l'amont.

channel : stable si l'évidence de fumée du catalogue est 'ok', sinon preview
(ADR 0009 : rien n'est « supporté » sans test d'exécution).

Usage :
  python3 build/gen-manifest.py                # génère tout
  python3 build/gen-manifest.py --check        # échoue si les fichiers générés
                                              # diffèrent de ceux committés
  python3 build/gen-manifest.py --skip-schema  # (tests) sans validation JSON Schema
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import sys
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog"
ARTIFACTS = REPO / "build" / "artifacts.json"
SCHEMA = REPO / "schema" / "manifest.v2.schema.json"
V2_OUT = REPO / "dist" / "manifest.v2.json"
V1_OUT = REPO / "manifest.json"
COMPAT_OUT = REPO / "docs" / "COMPAT.md"

REPO_SLUG = "jjoblab/codeide-tools"
RELEASES_BASE = f"https://github.com/{REPO_SLUG}/releases/download"


def load_yaml(path: Path) -> dict:
    with open(path, encoding="utf-8") as fh:
        return yaml.safe_load(fh)


def die(msg: str) -> None:
    print(f"Erreur : {msg}", file=sys.stderr)
    sys.exit(1)


def subst(template: str, version: str) -> str:
    return template.replace("{version}", version)


def load_catalog() -> tuple[dict, dict, list[dict], dict]:
    upstream = {}
    for f in sorted((CATALOG / "upstream").glob("*.yaml")):
        upstream[f.stem] = load_yaml(f)
    components = []
    for f in sorted((CATALOG / "components").glob("*.yaml")):
        components.append(load_yaml(f))
    compat = load_yaml(CATALOG / "compat.yaml")
    profiles = load_yaml(CATALOG / "profiles.yaml")
    return upstream, components, compat, profiles


def load_artifacts() -> dict:
    if not ARTIFACTS.exists():
        return {}
    with open(ARTIFACTS, encoding="utf-8") as fh:
        return json.load(fh)


def smoke_channel(component: dict, version: str, arch: str) -> tuple[str, str]:
    """Retourne (channel, raison) selon l'évidence de fumée du catalogue."""
    entry = (component.get("smoke", {}) or {}).get(version, {}).get(arch)
    if entry and entry.get("status") == "ok":
        return "stable", entry.get("source", "")
    return "preview", (entry or {}).get("reason", "smoke en attente")


def archive_name(comp_id: str, version: str, revision: str, arch: str) -> str:
    return f"{comp_id}-{version}-{revision}-{arch}.tar.xz"


def build_v2_components(upstream: dict, components: list[dict], artifacts: dict) -> list[dict]:
    out = []
    for comp in components:
        cid = comp["id"]
        up_id = comp.get("upstream")
        up = upstream.get(up_id, {})
        for v in comp.get("versions", []):
            version, revision = v["version"], v.get("revision", "r1")
            for arch in comp.get("arch", []):
                key = f"{cid}-{version}-{revision}-{arch}"
                if cid in ("cmdline-tools", "platform"):
                    # Pointeur direct Google : sommes épinglées de l'amont.
                    pins = up.get("cmdline-tools" if cid == "cmdline-tools" else "platforms", {})
                    pin = pins.get(version)
                    if not pin:
                        die(f"{cid}@{version} : aucun épinglage amont dans catalog/upstream/")
                    url = f"{up['base-url']}/{pin['url']}"
                    sha, size = pin["sha256"], pin["size"]
                else:
                    # Archive reconditionnée : les sommes viennent d'artifacts.json.
                    art = artifacts.get(key)
                    if not art:
                        continue  # pas encore fabriquée : hors manifeste
                    sha, size = art["sha256"], art["size"]
                    name = archive_name(cid, version, revision, arch)
                    tag = f"{cid}-{version}-{revision}"
                    url = f"{RELEASES_BASE}/{tag}/{name}"
                channel, _reason = smoke_channel(comp, version, arch)
                entry = {
                    "id": cid,
                    "version": version,
                    "revision": revision,
                    "arch": arch,
                    "channel": channel,
                    "critical": comp["critical"],
                    "sources": [{"url": url}],
                    "sha256": sha,
                    "size": size,
                    "installPath": subst(comp["install-path"], version),
                    "requires": comp.get("requires", []),
                    "verify": {
                        "cmd": subst(comp["verify"]["cmd"], version),
                        "expect": comp["verify"]["expect"],
                    },
                }
                if comp.get("license"):
                    entry["license"] = comp["license"]
                # minAndroidApi : surcharge par version (aosp/36.0.0 compilée
                # à API 34 — ADR 0012), sinon champ composant.
                min_api = v.get("minAndroidApi", comp.get("minAndroidApi"))
                if min_api:
                    entry["minAndroidApi"] = min_api
                if comp.get("archive-root"):
                    entry["archiveRoot"] = comp["archive-root"]
                out.append(entry)
    # Ordre stable : id, version (desc), arch.
    def sort_key(e: dict):
        return (e["id"], tuple(int(p) if p.isdigit() else p for p in re.split(r"[.\-]", e["version"])), e["arch"])

    return sorted(out, key=sort_key)


def build_profiles(components: list[dict], artifacts: dict) -> dict:
    """Profils : seules les entrées réellement présentes au manifeste sont gardées
    (une exigence sans artefact = profil cassé ; on échoue plutôt)."""
    available = set()
    for comp in components:
        cid = comp["id"]
        for v in comp.get("versions", []):
            for arch in comp.get("arch", []):
                if cid in ("cmdline-tools", "platform"):
                    available.add(f"{cid}@{v['version']}")
                elif artifacts.get(f"{cid}-{v['version']}-{v.get('revision', 'r1')}-{arch}"):
                    available.add(f"{cid}@{v['version']}")
    profiles = {}
    for name, p in (load_yaml(CATALOG / "profiles.yaml") or {}).items():
        reqs = p.get("components", [])
        missing = [r for r in reqs if r not in available]
        if missing:
            die(f"profil {name} : composants sans artefact au manifeste : {', '.join(missing)}")
        profiles[name] = {"components": reqs}
        if p.get("description"):
            profiles[name]["description"] = p["description"].strip()
    return profiles


def build_v1_manifest(components: list[dict]) -> dict:
    """Manifeste v1 : uniquement les composants exprimables en v1, avec leurs
    URLs/sommes des releases EXISTANTES (immuables). Reproduit à l'identique le
    manifeste v1 historique tant que le catalogue ne change pas."""
    v1 = {
        "android_sdk": None,
        "build_tools": {"aarch64": {}, "arm": {}, "x86_64": {}},
        "cmdline_tools": None,
        "platform_tools": {"aarch64": {}, "arm": {}, "x86_64": {}},
        "sha256": {},
    }
    for comp in components:
        v1sec = comp.get("v1") or {}
        section = v1sec.get("section")
        if not section:
            continue
        for version, sums in (v1sec.get("legacy-sha256") or {}).items():
            for arch, sha in sums.items():
                if section in ("build_tools", "platform_tools"):
                    name = f"{comp['id']}-{version}-{arch}.tar.xz"
                    url = v1sec["legacy-url"].replace("{version}", version).replace("{arch}", arch)
                    v1[section][arch][f"_{version.replace('.', '_')}"] = url
                else:  # cmdline_tools : entrée unique (rev 12.0)
                    name = "cmdline-tools.tar.xz"
                    url = v1sec["legacy-url"]
                    v1["cmdline_tools"] = url
                v1["sha256"][name] = sha
    return v1


def build_compat(compat: dict) -> list[dict]:
    out = []
    for e in compat.get("entries", []):
        row = {k: e[k] for k in ("agp", "buildTools", "aapt2", "compileSdk", "jdk", "status")}
        if "incompatible" in e:
            row["incompatible"] = e["incompatible"]
        if "evidence" in e:
            row["evidence"] = e["evidence"]
        if "note" in e:
            row["note"] = e["note"]
        out.append(row)
    return out


def render_compat_md(compat: dict) -> str:
    lines = [
        "# Matrice de compatibilité AGP ↔ build-tools ↔ aapt2 ↔ compileSdk ↔ JDK",
        "",
        "Document **généré** depuis `catalog/compat.yaml` (ne pas éditer à la main).",
        "« testé » = mesuré sur hôte Linux x86_64 (note `docs/research/02`, scripts",
        "`r2-matrice2.sh` / `r2-cellules.sh`) — l'exécution bionique sur appareil reste à",
        "confirmer par les smoke tests. « non testé » = déduit, à confirmer.",
        "",
        "| AGP | build-tools | aapt2 | compileSdk | JDK | Statut | Remarque |",
        "|---|---|---|---|---|---|---|",
    ]
    for e in compat.get("entries", []):
        status = "testé (hôte)" if e["status"] == "tested" else "non testé"
        if e.get("incompatible"):
            status = "**incompatible** (testé)"
        note = e.get("note", "")
        if e.get("evidence"):
            note = (note + " — " if note else "") + f"preuve : {e['evidence']}"
        lines.append(
            f"| {e['agp']} | {e['buildTools']} | {e['aapt2']} | {e['compileSdk']} | "
            f"{e['jdk']} | {status} | {note} |"
        )
    lines += [
        "",
        "## Lecture rapide",
        "",
        "- AGP **9.x** (9.0/9.4 testés) : build-tools minimale **36.0.0** — une demande",
        "  inférieure est ignorée et AGP auto-installe 36.0.0 **x86_64** (≈ 63 Mio) ;",
        "  l'override `android.aapt2FromMavenOverride` fait fonctionner aapt2 34/35.",
        "- AGP **8.13** : minimale 35.0.0 — `build-tools@35.0.2` satisfait sans aucune",
        "  auto-installation (combinaison recommandée).",
        "- **aapt2 33.0.3 ne lit pas** `android.jar` ≥ 35 (échec de link) : compileSdk",
        "  ≤ 34 pour build-tools 33.0.3.",
        "- Stratégies détaillées pour AGP 9.x : ADR 0003 ; mesures : note de recherche 02.",
        "",
    ]
    return "\n".join(lines)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="échoue si les fichiers générés diffèrent")
    ap.add_argument("--skip-schema", action="store_true", help="(tests) sans validation JSON Schema")
    args = ap.parse_args()

    upstream, components, compat, _ = load_catalog()
    artifacts = load_artifacts()

    manifest = {
        "schemaVersion": 2,
        "generatedAt": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "components": build_v2_components(upstream, components, artifacts),
        "profiles": build_profiles(components, artifacts),
        "compat": build_compat(compat),
    }

    if not args.skip_schema:
        try:
            import jsonschema
        except ImportError:
            die("jsonschema absent (pip install jsonschema)")
        schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
        jsonschema.validate(manifest, schema)

    outputs = {
        V2_OUT: json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        V1_OUT: json.dumps(build_v1_manifest(components), ensure_ascii=False, indent=4, sort_keys=True) + "\n",
        COMPAT_OUT: render_compat_md(compat),
    }

    if args.check:
        ok = True
        for path, content in outputs.items():
            if not path.exists() or path.read_text(encoding="utf-8") != content:
                # generatedAt rend le v2 instable : on compare SANS le champ.
                if path == V2_OUT and path.exists():
                    old = json.loads(path.read_text(encoding="utf-8"))
                    old.pop("generatedAt", None)
                    new = json.loads(content)
                    new.pop("generatedAt", None)
                    if old == new:
                        continue
                print(f"HORS-DATE : {path}", file=sys.stderr)
                ok = False
        sys.exit(0 if ok else 1)

    for path, content in outputs.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        print(f"généré : {path.relative_to(REPO)}")

    n_stable = sum(1 for c in manifest["components"] if c.get("channel") == "stable")
    print(
        f"manifeste v2 : {len(manifest['components'])} composants "
        f"({n_stable} stable, {len(manifest['components']) - n_stable} preview), "
        f"{len(manifest['profiles'])} profils, {len(manifest['compat'])} lignes compat"
    )


if __name__ == "__main__":
    main()
