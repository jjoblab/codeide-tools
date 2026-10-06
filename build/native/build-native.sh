#!/bin/bash
# build-native.sh — construit le zip amont équivalent (android-sdk-tools-static-
# <arch>.zip) DEPUIS LES SOURCES AOSP épinglées au catalogue (ADR 0012).
#
# usage : build-native.sh <version> <arch> <out-zip> [composant]
#   version : version catalogue (ex. 36.0.0) — pins = catalog/upstream/aosp.yaml
#   arch    : aarch64 | arm | x86_64
#   out-zip : chemin du zip produit (format attendu par build/package.sh)
#   composant : build-tools | platform-tools (vide = zip complet)
#              → CODEIDE_SCOPE : build-tools restreint la configuration CMake
#                aux outils du composant (platform-tools/adb exige un portage
#                propre par tag — fichiers déplacés amont, ADR 0012)
#
# Étapes (dans Docker, image épinglée — Dockerfile) :
#   1. export des pins catalogue → pins.json (commits AOSP immuables)
#   2. get_source.py : clones --depth 1 aux commits pins (cache : $WORK/recipe/src)
#   3. protoc hôte (protobuf AOSP, build une fois, mis en cache)
#   4. build.py : CMake + Ninja, NDK r27c, --api 30, ABI cible
#   5. le zip produit (build-tools/ + platform-tools/ à la racine) → <out-zip>
#
# Cache : CODEIDE_NATIVE_CACHE (défaut build/cache/native/<version>) — sources
# + protoc + répertoires de build conservés entre arches et entre exécutions.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NATIVE="$REPO/build/native"

version=$1 arch=$2 out=$3 composant=${4:-}
[ -n "$version" ] && [ -n "$arch" ] && [ -n "$out" ] || {
  echo "usage : build-native.sh <version> <arch> <out-zip> [composant]" >&2; exit 1; }

case $composant in
  build-tools)   SCOPE="build-tools" ;;
  ""|platform-tools) SCOPE="all" ;;
  *) echo "composant inconnu : $composant" >&2; exit 1 ;;
esac

case $arch in
  aarch64) abi=arm64-v8a ;;
  arm)     abi=armeabi-v7a ;;
  x86_64)  abi=x86_64 ;;
  *) echo "architecture inconnue : $arch" >&2; exit 1 ;;
esac

WORK="${CODEIDE_NATIVE_CACHE:-$REPO/build/cache/native/$version}"
mkdir -p "$WORK" "$(dirname "$out")"
WORK="$(cd "$WORK" && pwd)"

# 1) pins depuis le catalogue (échec net si la version n'est pas épinglée aosp)
python3 "$REPO/build/catalog-query.py" aosp "$version" pins-json >"$WORK/pins.json"
aosp_tag="$(python3 -c "import json;print(json.load(open('$WORK/pins.json'))['tag'])")"
echo "==> amont aosp : $aosp_tag ($arch → $abi)" >&2

# 2) image Docker épinglée (cache de couches Docker si présent)
docker build -q -t codeide-native "$NATIVE" >/dev/null

# 3) construction dans le conteneur
docker_run_extra=()
[ "$SCOPE" != all ] && docker_run_extra+=(-e CODEIDE_SCOPE="$SCOPE")
docker run --rm \
  ${docker_run_extra:+"${docker_run_extra[@]}"} \
  -v "$NATIVE":/recipe:ro \
  -v "$WORK":/work \
  codeide-native bash -euxo pipefail -c '
    cd /work
    # recette (fichiers légers, ~1,7 Mio) copiée à frais — le commit du dépôt
    # est le pin de la recette ; les SOURCES restent dans le volume (/work/src,
    # ~2 Go) à travers un lien symbolique : pas de re-clonage entre arches.
    rm -rf /work/recipe-mirror
    mkdir -p /work/recipe-mirror /work/src
    cp -a /recipe/. /work/recipe-mirror/
    ln -sfn /work/src /work/recipe-mirror/src
    cd /work/recipe-mirror

    python3 get_source.py --pins /work/pins.json --root /work/recipe-mirror

    # protoc hôte (protobuf AOSP) — persistant dans /work/src/protobuf/build
    if [ ! -x src/protobuf/build/protoc ]; then
      cmake -GNinja -S src/protobuf -B src/protobuf/build \
            -Dprotobuf_BUILD_TESTS=OFF -DCMAKE_BUILD_TYPE=Release
      ninja -C src/protobuf/build protoc
    fi

    python3 build.py --ndk /opt/ndk --abi '"$abi"' --api 30 \
      --build /work/build-'"$arch"' \
      --protoc /work/recipe-mirror/src/protobuf/build/protoc
  '

# 4) le zip est écrit par build.py à CWD/build/… (absolu → /work)
zip_in="$WORK/android-sdk-tools-$arch.zip"
[ -f "$zip_in" ] || { echo "zip natif introuvable : $zip_in" >&2; exit 1; }
cp -f "$zip_in" "$out"
sha="$(sha256sum "$out" | cut -d' ' -f1)"
echo "==> zip natif produit : $out (sha256 $sha) — Pas de pin binaire : la recette est épinglée (ADR 0012)" >&2
