#!/usr/bin/env python3
"""Requêtes catalogue pour les scripts shell (package.sh, workflows).

Usage :
  catalog-query.py pin <amont> <version> <champ>          # sha256/size du zip amont
  catalog-query.py arch-pin <amont> <version> <arch> <champ>
  catalog-query.py aosp <version> <quoi>                  # pins-json | tag | ndk | api
  catalog-query.py amont-version <id> <version>           # amont effectif (surcharge par version)
  catalog-query.py versions <id>                          # versions d'un composant
  catalog-query.py champ <id> <clé>                       # champ simple (install-path…)
  catalog-query.py lambda <version>                       # jar stub : chemin + sha256
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "catalog"


def load(path: Path) -> dict:
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def upstream(name: str) -> dict:
    return load(CATALOG / "upstream" / f"{name}.yaml")


def component(cid: str) -> dict:
    for f in sorted((CATALOG / "components").glob("*.yaml")):
        if load(f).get("id") == cid:
            return load(f)
    raise SystemExit(f"composant inconnu : {cid}")


def dotted(obj: dict, key: str):
    cur: object = obj
    for part in key.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return None
        cur = cur[part]
    return cur


def main() -> None:
    args = sys.argv[1:]
    if not args:
        raise SystemExit(__doc__)
    cmd = args[0]
    if cmd == "pin":
        _, name, version, field = args
        pin = upstream(name)["pins"][version]
        print(pin[field])
    elif cmd == "arch-pin":
        # pin archi : lzhiyong <version> <arch> <champ>
        _, name, version, arch, field = args
        pin = upstream(name)["pins"][version][arch]
        print(pin[field])
    elif cmd == "aosp":
        # aosp <version> <quoi> — pins source AOSP (ADR 0012)
        _, version, what = args
        doc = upstream("aosp")
        pin = doc["pins"][version]
        if what == "pins-json":
            print(json.dumps({"tag": pin["tag"], "repos": pin["repos"]},
                             ensure_ascii=False))
        elif what == "tag":
            print(pin["tag"])
        else:  # ndk, api, image… : champs du haut niveau + surcharge possible
            val = pin.get(what, doc.get(what))
            print(val if val is not None else "")
    elif cmd == "amont-version":
        # amont effectif d'une version : surcharge de l'entrée de version,
        # sinon champ composant (compat : lzhiyong pour 33–35)
        _, cid, version = args
        comp = component(cid)
        for v in comp.get("versions", []):
            if v["version"] == version:
                print(v.get("upstream") or comp.get("upstream", "lzhiyong"))
                return
        raise SystemExit(f"version inconnue : {cid}@{version}")
    elif cmd == "versions":
        for v in component(args[1]).get("versions", []):
            print(f"{v['version']}\t{v.get('revision', 'r1')}")
    elif cmd == "champ":
        val = dotted(component(args[1]), args[2])
        if val is None:
            print("", end="")
        elif isinstance(val, list):
            for item in val:
                print(item)
        else:
            print(val)
    elif cmd == "lambda":
        # jar core-lambda-stubs d'une version : chemin + sha256 + version amont
        version = args[1]
        jar = REPO / "build" / "vendor" / "core-lambda-stubs" / f"{version}.jar"
        if not jar.is_file():
            raise SystemExit(f"jar stub absent : {jar}")
        sha = hashlib.sha256(jar.read_bytes()).hexdigest()
        g = upstream("google")["lambda-stubs-source"][version]
        print(f"{jar}\t{sha}\t{g['url']}\t{g['sha256']}")
    else:
        raise SystemExit(f"commande inconnue : {cmd}")


if __name__ == "__main__":
    main()
