#!/bin/sh
# ci-checks.sh — vérifications locales = miroir exact du job CI (ci.yml).
# Sortie non nulle à la première défaillance ; chaque étape est affichée.
set -eu
cd "$(dirname "$0")/.."

REPO_ROOT=$(pwd)
SHELLCHECK=${SHELLCHECK:-shellcheck}
BATS=${BATS:-bats}
PASS=0; FAIL=0

etape() { printf '\n=== %s ===\n' "$1"; }
ok_() { printf 'OK : %s\n' "$1"; PASS=$((PASS+1)); }
ko_() { printf 'ÉCHEC : %s\n' "$1" >&2; FAIL=$((FAIL+1)); }

# 1. Syntaxe + shellcheck de tous les scripts shell (CLI POSIX, shim, build).
etape "shellcheck (seuil : warning)"
for f in cli/codeide-sdk scripts/codeidesetup build/package.sh build/native/build-native.sh; do
  if $SHELLCHECK -S warning "$f"; then ok_ "$f"; else ko_ "$f"; fi
done

# 2. Catalogue : YAML valides, composants connus, pins complètes.
etape "catalogue"
python3 - <<'PY' && ok_ "catalogue cohérent" || ko_ "catalogue"
import sys, yaml, pathlib
cat = pathlib.Path("catalog")
ids = set()
for f in sorted((cat/"components").glob("*.yaml")):
    c = yaml.safe_load(f.read_text())
    assert c["id"] and c["install-path"] and c["verify"]["cmd"], f
    ids.add(c["id"])
    # L'amont peut être surchargé par version (aosp — ADR 0012).
    for v in c.get("versions", []):
        up_v = v.get("upstream") or c["upstream"]
        ups_v = yaml.safe_load((cat/"upstream"/f"{up_v}.yaml").read_text())
        section_v = {"cmdline-tools": "cmdline-tools", "platform": "platforms"}.get(c["id"], "pins")
        pins_v = ups_v[section_v]
        assert v["version"] in pins_v, f"{c['id']}@{v['version']} sans pin amont ({up_v})"
profiles = yaml.safe_load((cat/"profiles.yaml").read_text())
comps = {f"{v['version']}" for f in (cat/"components").glob("*.yaml")
         for v in yaml.safe_load(f.read_text()).get("versions", [])}
for pname, p in profiles.items():
    for r in p["components"]:
        cid, ver = r.split("@")
        assert cid in ids, f"profil {pname}: id inconnu {cid}"
        assert ver in comps, f"profil {pname}: version inconnue {r}"
PY

# 3. Schéma : manifeste v2 généré + vecteurs golden (valides ET invalides).
etape "schéma + manifeste généré"
python3 build/gen-manifest.py --check && ok_ "manifestes générés à jour (--check)" \
  || { ko_ "manifestes générés HORS-DATE (relancer build/gen-manifest.py)"; python3 build/gen-manifest.py; }
python3 - <<'PY' && ok_ "vecteurs golden conformes" || ko_ "vecteurs golden"
import json, jsonschema, pathlib
schema = json.load(open("schema/manifest.v2.schema.json"))
g = pathlib.Path("tests/golden")
for name in ("manifest-test.json", "manifest-valid-minimal.json"):
    jsonschema.validate(json.load(open(g/name)), schema)
for p in sorted(g.glob("manifest-invalide-*.json")):
    if "semantique" in p.name:
        continue
    try:
        jsonschema.validate(json.load(open(p)), schema)
        raise SystemExit(f"vecteur non rejeté : {p.name}")
    except jsonschema.ValidationError:
        pass
PY

# 4. Parité v1 : le manifeste v1 généré ne doit JAMAIS diverger des entrées
#    publiées (immutabilité des sha256 v1).
etape "parité v1 (sha256 publiés inchangés)"
python3 - <<'PY' && ok_ "aucun sha256 v1 modifié" || ko_ "sha256 v1 modifié (IMMUTABILITÉ VIOLÉE)"
import json, pathlib, yaml
v1 = json.load(open("manifest.json"))
ok = True
for f in pathlib.Path("catalog/components").glob("*.yaml"):
    c = yaml.safe_load(f.read_text())
    sec = c.get("v1") or {}
    for ver, sums in (sec.get("legacy-sha256") or {}).items():
        for arch, sha in sums.items():
            if c["id"] in ("build-tools", "platform-tools"):
                name = f"{c['id']}-{ver}-{arch}.tar.xz"
                got = v1.get("sha256", {}).get(name)
                if got != sha:
                    print(f"divergence : {name} attendu {sha}, manifeste v1 {got}")
                    ok = False
            else:
                if v1.get("sha256", {}).get("cmdline-tools.tar.xz") != sha:
                    ok = False
raise SystemExit(0 if ok else 1)
PY

# 5. Immuabilité v2 : les sha256 d'artifacts.json existants ne bougent pas
#    entre deux générations (test de non-régression du manifeste v2).
etape "immutabilité v2"
python3 - <<'PY' && ok_ "sha256 v2 stables" || ko_ "sha256 v2 instables"
import json, pathlib
art = json.load(open("build/artifacts.json")) if pathlib.Path("build/artifacts.json").exists() else {}
v2 = json.load(open("dist/manifest.v2.json"))
pub = {f"{c['id']}-{c['version']}-{c['revision']}-{c['arch']}": c["sha256"] for c in v2["components"]}
for k, entry in art.items():
    if k in pub and pub[k] != entry["sha256"]:
        print(f"divergence : {k} artifacts.json {entry['sha256']} != manifeste {pub[k]}")
        raise SystemExit(1)
PY

# 6. Tests bats du CLI (vecteurs golden).
etape "tests bats"
if command -v "$BATS" >/dev/null 2>&1; then
  if "$BATS" tests/cli/*.bats; then ok_ "bats"; else ko_ "bats"; fi
else
  printf 'bats absent : ignoré (installer bats-core)\n'
fi

# 7. Reproductibilité : rebuild d'un petit composant, hash identique.
etape "reproductibilité + convention de racine (platform-tools 34.0.3 arm)"
if [ "${CI_SKIP_REPRODUCE:-0}" != "1" ]; then
  keep=$(mktemp -d)
  cp build/artifacts.json "$keep/artifacts.json"
  bash build/package.sh platform-tools@34.0.3 --arch arm --dist "$keep/dist" \
    --cache "$keep/cache" >/dev/null 2>&1
  a=$(jq -r '."platform-tools-34.0.3-r1-arm".sha256' build/artifacts.json)
  b=$(sha256sum "$keep/dist/platform-tools-34.0.3-r1-arm.tar.xz" | cut -d' ' -f1)
  if [ "$a" = "$b" ]; then ok_ "rebuild identique ($b)"; else ko_ "rebuild divergent ($a vs $b)"; fi
  # Convention de racine (12.3) : une seule racine = racine du SDK, aucun
  # chemin absolu ni « .. » — archive reconstruite + vecteurs golden.
  if python3 -c '
import sys, tarfile
viol = []
for name in sys.argv[1:]:
    with tarfile.open(name) as tf:
        roots = set()
        for m in tf.getmembers():
            if m.name.startswith("/") or ".." in m.name.split("/"):
                viol.append(f"{name} : chemin interdit {m.name}")
            roots.add(m.name.split("/")[0])
        if len(roots) != 1:
            viol.append(f"{name} : racines multiples {sorted(roots)}")
raise SystemExit("\n".join(viol) if viol else 0)
' "$keep/dist/platform-tools-34.0.3-r1-arm.tar.xz" tests/golden/archives/test-tools-1.0-r1-any.tar.xz; then
    ok_ "convention de racine (12.3) respectée"
  else
    ko_ "convention de racine VIOLÉE (voir ci-dessus)"
  fi
  if cmp -s "$keep/artifacts.json" build/artifacts.json; then ok_ "artifacts.json inchangé";
  else ko_ "artifacts.json modifié par le rebuild"; fi
  rm -rf "$keep"
fi

printf '\n=== BILAN : %d OK, %d ÉCHEC(S) ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
