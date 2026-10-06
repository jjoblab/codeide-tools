#!/usr/bin/env bash
# package.sh — fabrication DÉTERMINISTE des archives codeide-tools v2.
#
#   build/package.sh <id>@<version>[,<id>@<version>…] [options]
#
# Options :
#   --arch LIST     architectures (défaut : aarch64,arm,x86_64)
#   --dist DIR      sortie (défaut : dist)
#   --cache DIR     cache des zips amont (défaut : build/cache ; env CODEIDE_CACHE)
#   --upstream DIR  répertoire contenant déjà les zips amont (évite le réseau)
#                   — noms : android-sdk-tools-static-<arch>.zip par tag
#   --force         écrase l'entrée existante d'artifacts.json (IMMUABILITÉ :
#                   à n'utiliser qu'avant toute publication réelle)
#
# Entrées : catalog/ (pins amont), build/vendor/ (jars stub).
# Sorties : dist/<id>-<version>-r<rev>-<arch>.tar.xz (+ .sha256),
#           dist/<tag-release>/provenance.json + SHA256SUMS,
#           build/artifacts.json (sommes des archives fabriquées).
#
# Déterminisme : entrées triées (tar --sort=name), mtime imposé
# (SOURCE_DATE_EPOCH), propriétaire 0:0, permissions explicites, xz -6 -T1.
# Le manifeste n'est PAS modifié ici : lancer ensuite build/gen-manifest.py.
#
# Licence : GPL-3.0 (voir LICENSE). Les composants redistribués restent sous
# leurs licences respectives (Apache-2.0 pour les binaires AOSP — NOTICE livré).
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

DIST="${REPO}/dist"
CACHE="${CODEIDE_CACHE:-${REPO}/build/cache}"
UPSTREAM_DIR=""
ARCHES="aarch64,arm,x86_64"
FORCE=false
SPECS=()

while [ $# -gt 0 ]; do
  case $1 in
    --arch) ARCHES=$2; shift 2 ;;
    --dist) DIST=$2; shift 2 ;;
    --cache) CACHE=$2; shift 2 ;;
    --upstream) UPSTREAM_DIR=$2; shift 2 ;;
    --force) FORCE=true; shift ;;
    -h|--help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) SPECS+=("$1"); shift ;;
  esac
done
[ "${#SPECS[@]}" -ge 1 ] || { echo "Usage : build/package.sh <id>@<version>[,…] [--arch a,b,c]…" >&2; exit 1; }

# Les spécifications peuvent être collées par des virgules : on les éclate.
SPECS_EXPANDED=()
for s in "${SPECS[@]}"; do
  IFS=',' read -ra _parts <<<"$s"
  SPECS_EXPANDED+=("${_parts[@]}")
done
SPECS=("${SPECS_EXPANDED[@]}")

# mtime fixe (2000-01-01T00:00:00Z) : constant, indépendant de la machine.
SOURCE_DATE_EPOCH=946684800
export SOURCE_DATE_EPOCH
XZ_LEVEL=6

mkdir -p "$DIST" "$CACHE"
# --dist/--cache peuvent être relatifs : on absolutise AVANT tout cd —
# make_archive redirige sa sortie depuis un sous-shell cd-é dans le staging
# temporaire (premier échec CI réel : « dist/x.tar.xz : No such file or
# directory » alors que dist/ existait à la racine).
DIST="$(cd "$DIST" && pwd)"
CACHE="$(cd "$CACHE" && pwd)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/codeide-package.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

die() { echo "Erreur : $*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }

sha256_of() { sha256sum "$1" | cut -d' ' -f1; }

recipe_sha() { # sha du contenu de build/native (la recette EST la source, ADR 0012)
  find "$REPO/build/native" -type f ! -path '*/__pycache__/*' -print0 \
    | sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1
}

aosp_zip_reusable() { # fichier-zip : vrai si présent ET recette inchangée (stamp)
  local zip=$1 stamp want got
  [ -s "$zip" ] || return 1
  stamp="$(dirname "$zip")/.recipe-sha"
  [ -s "$stamp" ] || return 1   # pas de stamp (cache antérieur au garde-fou) : reconstruire
  want="$(recipe_sha)"
  got="$(cat "$stamp")"
  [ "$want" = "$got" ]
}

fetch_zip() { # amont tag arch [composant] — le chemin du zip est ÉCHOS sur stdout,
  #           tout le journal va sur stderr (pas de mélange).
  local amont=$1 tag=$2 arch=$3 composant=${4:-}
  local name="android-sdk-tools-static-$arch.zip" want got url
  # aosp : réutilisation du zip en cache SEULEMENT si la recette n'a pas
  # changé (stamp .recipe-sha, cf aosp_zip_reusable) — bug constaté au r2
  # 36.0.0 : un changement de flags build/native/CMakeLists.txt était
  # silencieusement ignoré, le zip r1 reconditionné tel quel. lzhiyong :
  # le zip est épinglé sha256 (check_pin en aval) — réutilisation sûre.
  if [ "$amont" = aosp ]; then
    if [ -n "$UPSTREAM_DIR" ] && aosp_zip_reusable "$UPSTREAM_DIR/$tag/$name"; then
      echo "$UPSTREAM_DIR/$tag/$name"; return
    fi
    if aosp_zip_reusable "$CACHE/$tag/$name"; then
      info "zip natif en cache, recette inchangée ($tag/$arch) : réutilisation" >&2
      echo "$CACHE/$tag/$name"; return
    fi
  else
    if [ -n "$UPSTREAM_DIR" ] && [ -s "$UPSTREAM_DIR/$tag/$name" ]; then
      echo "$UPSTREAM_DIR/$tag/$name"; return
    fi
    if [ -s "$CACHE/$tag/$name" ]; then echo "$CACHE/$tag/$name"; return; fi
  fi
  mkdir -p "$CACHE/$tag"
  case $amont in
    lzhiyong) url="https://github.com/Lzhiyong/android-sdk-tools/releases/download/$tag/$name" ;;
    aosp)
      # Construction native depuis les sources AOSP épinglées (ADR 0012) —
      # pas de téléchargement : le zip est fabriqué par build/native/.
      # composant → CODEIDE_SCOPE (build-tools restreint la configuration).
      info "construction native (aosp) $tag/$arch${composant:+ ($composant)}" >&2
      bash "$REPO/build/native/build-native.sh" "$tag" "$arch" "$CACHE/$tag/$name" "$composant" >&2
      # stamp : la recette qui a produit ce zip (garde-fou de réutilisation)
      recipe_sha >"$CACHE/$tag/.recipe-sha"
      echo "$CACHE/$tag/$name"; return ;;
    *) die "amont inconnu : $amont" ;;
  esac
  info "téléchargement $tag/$name" >&2
  curl -fsSL --retry 3 --retry-delay 2 -o "$CACHE/$tag/$name" "$url" >&2
  echo "$CACHE/$tag/$name"
}

check_pin() { # fichier amont tag arch
  local file=$1 tag=$2 arch=$3 want got
  want="$(python3 build/catalog-query.py arch-pin lzhiyong "$tag" "$arch" sha256)"
  got="$(sha256_of "$file")"
  [ "$want" = "$got" ] || die "SHA-256 amont invalide pour $tag/$arch : attendu $want, obtenu $got"
  info "pin amont vérifié ($tag/$arch)"
}

make_archive() { # staging arche-relative-sortie
  local staging=$1 rel=$2 out=$3
  (
    cd "$staging"
    tar --sort=name --format=ustar \
        --mtime="@${SOURCE_DATE_EPOCH}" --clamp-mtime \
        --owner=0 --group=0 --numeric-owner \
        -cf - "$rel" | xz -${XZ_LEVEL} -T1 -c >"$out"
  )
}

package_native() { # id version revision arch
  local id=$1 version=$2 rev=$3 arch=$4
  local tag_up=$version   # tag amont = version du composant
  # Amont effectif : surcharge par version (aosp — ADR 0012), sinon composant.
  local amont zip
  amont="$(python3 build/catalog-query.py amont-version "$id" "$version")"
  zip="$(fetch_zip "$amont" "$tag_up" "$arch" "$id")"
  [ -f "$zip" ] || die "zip amont introuvable : $tag_up/$arch"
  if [ "$amont" = aosp ]; then
    # Pas de pin binaire amont : le sha du zip construit est un résultat
    # journalisé ; les pins sources/récipe/NDK/image sont au catalogue.
    info "amont aosp ($tag_up) : zip construit, sha256 $(sha256_of "$zip")"
  else
    check_pin "$zip" "$tag_up" "$arch"
  fi

  local stage="$WORK/stage-$id-$version-$arch"
  rm -rf "$stage"; mkdir -p "$stage"

  local binlist up_rel down_rel
  if [ "$id" = build-tools ]; then
    up_rel="build-tools"; down_rel="build-tools/$version"
    binlist="$(python3 build/catalog-query.py champ build-tools content.binaries 2>/dev/null | tr -d '[]' | tr ',' ' ' || true)"
  else
    up_rel="platform-tools"; down_rel="platform-tools"
    binlist="$(python3 build/catalog-query.py champ platform-tools content.binaries 2>/dev/null | tr -d '[]' | tr ',' ' ' || true)"
  fi

  # Extraction ciblée : seuls les binaires listés au catalogue entrent au stage.
  # Racine interne variable selon les tags amont : build-tools/ (35.0.2) ou
  # <arch>/build-tools/ (33.0.3, 34.0.3) — détection automatique.
  local src="$WORK/src-$arch-$version"
  rm -rf "$src"; mkdir -p "$src"
  unzip -q -o "$zip" -d "$src"
  local bt_dir
  bt_dir="$(find "$src" -maxdepth 2 -type d -name build-tools | head -n1)"
  [ -n "$bt_dir" ] || die "dossier build-tools/ introuvable dans $zip"
  local src_root; src_root="$(dirname "$bt_dir")"

  mkdir -p "$stage/$down_rel"
  for bin in $binlist; do
    [ -f "$src_root/$up_rel/$bin" ] || die "binaire absent du zip amont : $up_rel/$bin"
    cp "$src_root/$up_rel/$bin" "$stage/$down_rel/$bin"
    # Contrôle ABI ELF : échec => pas d'archive (prompt § 6).
    python3 build/check-elf.py "$stage/$down_rel/$bin" "$arch" >/dev/null
  done
  info "ABI ELF vérifiée ($id $version $arch : $(echo "$binlist" | wc -w) binaires)"

  if [ "$id" = build-tools ]; then
    # core-lambda-stubs.jar (AOSP Apache-2.0, exigé par la validation AGP — note 07).
    local jar_path jar_sha
    # shellcheck disable=SC2318
    read -r jar_path jar_sha <<EOF
$(python3 build/catalog-query.py lambda "$version" | cut -f1-2)
EOF
    info "jar stub : $(basename "$jar_path") (${jar_sha%${jar_sha#????????????}}…)"
    cp "$jar_path" "$stage/$down_rel/core-lambda-stubs.jar"
    cp "$REPO/build/vendor/core-lambda-stubs/NOTICE.txt" "$stage/$down_rel/NOTICE.txt"
    printf 'Pkg.Desc=Android SDK Build-Tools %s\nPkg.UserSrc=false\nPkg.Revision=%s\n' \
      "$version" "$version" >"$stage/$down_rel/source.properties"
  else
    printf 'Pkg.Desc=Android SDK Platform-Tools\nPkg.UserSrc=false\nPkg.Revision=%s\n' \
      "$version" >"$stage/$down_rel/source.properties"
  fi

  # Permissions explicites : répertoires 755, exécutables 755, le reste 644.
  find "$stage" -type d -exec chmod 755 {} +
  find "$stage" -type f -exec chmod 755 {} +
  if [ "$id" = build-tools ]; then
    chmod 644 "$stage/$down_rel/core-lambda-stubs.jar" \
              "$stage/$down_rel/source.properties" "$stage/$down_rel/NOTICE.txt"
  else
    chmod 644 "$stage/$down_rel/source.properties"
  fi

  # Aucun chemin absolu ni '..' dans l'archive (contrat 12.3).
  if ( cd "$stage" && find . | grep -E '/\.\.(/|$)|^\.\./' >/dev/null ); then
    die "chemin interdit (.. ) détecté dans $stage"
  fi

  local name="$id-$version-$rev-$arch.tar.xz"
  local out="$DIST/$name"
  info "archive $name"
  make_archive "$stage" "${down_rel%%/*}" "$out"

  local sum size; sum="$(sha256_of "$out")"; size=$(stat -c%s "$out")
  printf '%s  %s\n' "$sum" "$name" >"$DIST/$name.sha256"

  # artifacts.json : fusion, immuabilité par défaut (jamais d'écrasement silencieux).
  python3 - "$id" "$version" "$rev" "$arch" "$sum" "$size" "$name" "$FORCE" <<'PY'
import json, pathlib, sys
cid, version, rev, arch, sha, size, name, force = sys.argv[1:9]
path = pathlib.Path("build/artifacts.json")
data = json.loads(path.read_text()) if path.exists() else {}
key = f"{cid}-{version}-{rev}-{arch}"
if key in data and data[key]["sha256"] != sha and force != "true":
    sys.exit(f"Erreur : {key} déjà fabriqué (sha {data[key]['sha256'][:12]}…) — immuabilité. --force pour écraser AVANT publication.")
data[key] = {"sha256": sha, "size": int(size), "archive": name}
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
PY
}

provenance() { # id version rev arches…
  local id=$1 version=$2 rev=$3; shift 3
  local dir="$DIST/$id-$version-$rev"
  mkdir -p "$dir"
  python3 - "$id" "$version" "$rev" "$dir" "$REPO" "$@" <<'PY'
import json, pathlib, subprocess, sys, datetime
cid, version, rev, outdir, repo, *arches = sys.argv[1:]
repo = pathlib.Path(repo)
import yaml
lz = yaml.safe_load((repo/"catalog/upstream/lzhiyong.yaml").read_text())
g = yaml.safe_load((repo/"catalog/upstream/google.yaml").read_text())
try:
    aosp = yaml.safe_load((repo/"catalog/upstream/aosp.yaml").read_text())
except FileNotFoundError:
    aosp = {}
def git(*a):
    try: return subprocess.check_output(["git", *a], cwd=repo, text=True).strip()
    except Exception: return None

# Amont EFFECTIF par version (ADR 0012) : versions aosp = construites depuis
# les sources épinglées (pas de pin binaire — les commits sont la provenance) ;
# versions lzhiyong = binaires amont épinglés par sha256.
if version in (aosp.get("pins") or {}):
    pin = aosp["pins"][version]
    upstream = {
        "mode": "aosp-sources",
        "recipe": aosp["recipe"],
        "ndk": aosp["ndk"],
        "image": aosp["image"],
        "api": pin.get("api", aosp.get("api", 30)),
        "tag": pin["tag"],
        "license": "Apache-2.0",
        "repos": pin["repos"],
        "built": list(arches),
    }
else:
    upstream = {
        "mode": "lzhiyong-binaire",
        "repo": lz["repo"], "tag": version, "license": lz["license"],
        "pins": {a: lz["pins"][version][a] for a in arches},
    }
prov = {
    "component": f"{cid}-{version}-{rev}",
    "builtAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "upstream": upstream,
    "toolchain": {"xz": subprocess.check_output(["xz", "--version"], text=True).splitlines()[0]},
    "determinism": {"sourceDateEpoch": 946684800, "xzLevel": 6, "xzThreads": 1, "tarFormat": "ustar", "sorted": True},
    "gitCommit": git("rev-parse", "HEAD"),
}
if cid == "build-tools":
    stub = g["lambda-stubs-source"][version]
    prov["coreLambdaStubs"] = {
        "file": f"build/vendor/core-lambda-stubs/{version}.jar",
        "source": f"https://dl.google.com/android/repository/{stub['url']}",
        "sourceSha256": stub["sha256"], "license": "Apache-2.0 (AOSP)",
    }
pathlib.Path(outdir, "provenance.json").write_text(json.dumps(prov, indent=2, sort_keys=True) + "\n")
print(f"généré : {outdir}/provenance.json")
PY
}

# --- Exécution ---------------------------------------------------------------
IFS=',' read -ra ARCH_LIST <<<"$ARCHES"

for spec in "${SPECS[@]}"; do
  id="${spec%%@*}"; version="${spec##*@}"
  rev="$(python3 build/catalog-query.py versions "$id" | awk -F'\t' -v v="$version" '$1==v{print $2; exit}')"
  [ -n "$rev" ] || die "version $version inconnue au catalogue pour $id"
  case $id in
    build-tools|platform-tools)
      for arch in "${ARCH_LIST[@]}"; do
        package_native "$id" "$version" "$rev" "$arch"
      done
      provenance "$id" "$version" "$rev" "${ARCH_LIST[@]}"
      ;;
    cmdline-tools|platform)
      info "$id@$version : pointeur direct Google — rien à fabriquer (ADR 0005)"
      ;;
    *) die "composant non fabricable : $id" ;;
  esac
done

# SHA256SUMS global du lot.
( cd "$DIST" && find . -maxdepth 1 -name '*.tar.xz' -printf '%f\n' | sort | xargs sha256sum >SHA256SUMS 2>/dev/null ) || true
info "terminé : $DIST"
info "ensuite : python3 build/gen-manifest.py   (régénère manifestes + COMPAT.md)"
