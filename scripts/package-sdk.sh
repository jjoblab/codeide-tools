#!/usr/bin/env bash
#
# package-sdk.sh — fabrique les archives publiées dans les releases et met à jour manifest.json
#
# Sous-commandes :
#   sdk      Build-tools + platform-tools (aarch64, arm, x86_64) à partir des binaires
#            statiques de lzhiyong/android-sdk-tools. Release : tag vX.Y.Z.
#   cmdline  Command-line tools (zip officiel de Google, indépendant de l'architecture).
#            Release : tag « sdk ».
#
# Exemples :
#   ./scripts/package-sdk.sh sdk -v 35.0.2
#   ./scripts/package-sdk.sh sdk -v 35.0.2 -R            # + publication via gh
#   ./scripts/package-sdk.sh cmdline -z commandlinetools-linux-XXXX_latest.zip -R
#
# Dépendances : curl unzip tar xz jq sha256sum (et gh pour -R).
# Licence : GPL-3.0 (voir LICENSE).

# Les filtres jq utilisent des variables jq ($a, $k, ...) : les apostrophes sont voulues.
# shellcheck disable=SC2016
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
REPO_SLUG="${CODEIDE_TOOLS_REPO:-jjoblab/codeide-tools}"
UPSTREAM_REPO="${UPSTREAM_REPO:-lzhiyong/android-sdk-tools}"
ARCHES=(aarch64 arm x86_64)

die() {
  printf 'Erreur : %s\n' "$*" >&2
  exit 1
}
info() { printf '==> %s\n' "$*"; }

usage() {
  cat <<USAGE
Usage :
  $0 sdk     -v X.Y.Z [-t TAG_AMONT] [-s DIR_ZIPS] [-o DIST] [-b URL_BASE] [-m MANIFEST] [-R]
  $0 cmdline -z ZIP_OU_URL [-o DIST] [-b URL_BASE] [-m MANIFEST] [-R]

Options :
  -v VER    Version du SDK, au format X.Y.Z (sdk).
  -t TAG    Tag de la release lzhiyong/android-sdk-tools à utiliser (défaut : VER).
  -s DIR    Dossier contenant déjà android-sdk-tools-static-<arch>.zip (sinon téléchargement).
  -z ZIP    Zip des command-line tools de Google, chemin ou URL (cmdline).
  -o DIST   Dossier de sortie (défaut : ./dist).
  -b URL    Base des URLs de release (défaut : https://github.com/${REPO_SLUG}/releases/download).
  -m FILE   manifest.json à mettre à jour (défaut : manifest.json du dépôt).
  -R        Publier la release avec 'gh' (crée ou complète la release).
  -h        Affiche cette aide.
USAGE
}

need_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "Commande requise introuvable : $c"
  done
}

# --- Options -----------------------------------------------------------------

[ $# -ge 1 ] || {
  usage >&2
  exit 1
}
SUBCOMMAND=$1
shift
case "$SUBCOMMAND" in
  -h | --help)
    usage
    exit 0
    ;;
  sdk | cmdline) ;;
  *)
    usage >&2
    exit 1
    ;;
esac

VERSION=""
SOURCE_TAG=""
SRC_DIR=""
ZIP=""
DIST="./dist"
BASE_URL=""
MANIFEST="$REPO_ROOT/manifest.json"
PUBLISH=false

while getopts "hv:t:s:z:o:b:m:R" opt; do
  case "$opt" in
    h)
      usage
      exit 0
      ;;
    v) VERSION=$OPTARG ;;
    t) SOURCE_TAG=$OPTARG ;;
    s) SRC_DIR=$OPTARG ;;
    z) ZIP=$OPTARG ;;
    o) DIST=$OPTARG ;;
    b) BASE_URL=$OPTARG ;;
    m) MANIFEST=$OPTARG ;;
    R) PUBLISH=true ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

BASE_URL="${BASE_URL:-https://github.com/${REPO_SLUG}/releases/download}"

# --- Utilitaires -------------------------------------------------------------

fetch() {
  curl -fL --retry 3 --retry-delay 2 --http1.1 --progress-bar -o "$2" "$1"
}

# Manifest vide canonique, créé s'il manque (fabrication hors dépôt cloné
# ou premier usage avec -m) — mêmes clés que le manifest du dépôt.
MANIFEST_VIERGE='{
    "android_sdk": null,
    "build_tools": {
        "aarch64": {},
        "arm": {},
        "x86_64": {}
    },
    "cmdline_tools": null,
    "platform_tools": {
        "aarch64": {},
        "arm": {},
        "x86_64": {}
    },
    "sha256": {}
}'

manifest_update() { # arguments jq (options puis filtre)
  local tmp
  if [ ! -f "$MANIFEST" ]; then
    printf '%s\n' "$MANIFEST_VIERGE" >"$MANIFEST"
  fi
  tmp="$(mktemp)"
  jq -S --indent 4 "$@" "$MANIFEST" >"$tmp"
  mv "$tmp" "$MANIFEST"
  chmod 644 "$MANIFEST"
}

make_archive() { # répertoire-source sortie.tar.xz élément...
  local src=$1 out=$2
  shift 2
  tar -C "$src" --owner=0 --group=0 --numeric-owner -cf - "$@" | xz -T0 -6 -c >"$out"
}

publish_release() { # tag titre notes fichiers...
  local tag=$1 title=$2 notes=$3
  shift 3
  need_cmd gh
  if gh release view "$tag" --repo "$REPO_SLUG" >/dev/null 2>&1; then
    info "La release $tag existe : mise à jour des fichiers"
    gh release upload "$tag" "$@" --clobber --repo "$REPO_SLUG"
  else
    info "Création de la release $tag"
    gh release create "$tag" "$@" --repo "$REPO_SLUG" --title "$title" --notes "$notes"
  fi
}

# --- sdk ---------------------------------------------------------------------

cmd_sdk() {
  [ -n "$VERSION" ] || die "Option -v requise (ex. -v 35.0.2)."
  [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Version invalide '$VERSION' (attendu : X.Y.Z)."
  need_cmd curl unzip tar xz jq sha256sum

  local src_tag="${SOURCE_TAG:-$VERSION}"
  [[ "$src_tag" =~ ^[A-Za-z0-9._-]+$ ]] || die "Tag amont invalide : $src_tag"
  local key="_${VERSION//./_}" tag="v$VERSION"
  local arch zip_name zip_path src stage out file sum component section
  local files=()

  for arch in "${ARCHES[@]}"; do
    zip_name="android-sdk-tools-static-$arch.zip"
    if [ -n "$SRC_DIR" ]; then
      zip_path="$SRC_DIR/$zip_name"
      [ -f "$zip_path" ] || die "Fichier introuvable : $zip_path"
    else
      zip_path="$WORK/$zip_name"
      info "Téléchargement de $zip_name ($UPSTREAM_REPO, tag $src_tag)"
      fetch "https://github.com/$UPSTREAM_REPO/releases/download/$src_tag/$zip_name" "$zip_path"
    fi

    src="$WORK/src-$arch"
    stage="$WORK/stage-$arch"
    rm -rf "$src" "$stage"
    mkdir -p "$src" "$stage/build-tools/$VERSION" "$stage/platform-tools"
    unzip -q -o "$zip_path" -d "$src"
    [ -d "$src/build-tools" ] || die "$zip_name ne contient pas de dossier build-tools/."
    [ -d "$src/platform-tools" ] || die "$zip_name ne contient pas de dossier platform-tools/."

    cp -a "$src/build-tools/." "$stage/build-tools/$VERSION/"
    cp -a "$src/platform-tools/." "$stage/platform-tools/"
    find "$stage" -type d -exec chmod 755 {} +
    find "$stage" -type f -exec chmod 755 {} +

    # Métadonnées minimales lues par les outils du SDK Android.
    printf 'Pkg.Desc=Android SDK Build-Tools %s\nPkg.UserSrc=false\nPkg.Revision=%s\n' \
      "$VERSION" "$VERSION" >"$stage/build-tools/$VERSION/source.properties"
    printf 'Pkg.Desc=Android SDK Platform-Tools\nPkg.UserSrc=false\nPkg.Revision=%s\n' \
      "$VERSION" >"$stage/platform-tools/source.properties"
    chmod 644 "$stage/build-tools/$VERSION/source.properties" "$stage/platform-tools/source.properties"

    for component in build-tools platform-tools; do
      file="$component-$VERSION-$arch.tar.xz"
      out="$DIST/$file"
      info "Archive : $file"
      make_archive "$stage" "$out" "$component"
      sum="$(sha256sum "$out" | cut -d' ' -f1)"
      files+=("$out")

      section="${component//-/_}"
      manifest_update --arg s "$section" --arg a "$arch" --arg k "$key" \
        --arg u "$BASE_URL/$tag/$file" --arg f "$file" --arg h "$sum" \
        '.[$s][$a][$k] = $u | .sha256[$f] = $h'
    done
  done

  (cd "$DIST" && sha256sum "build-tools-$VERSION-"*.tar.xz "platform-tools-$VERSION-"*.tar.xz >SHA256SUMS)
  files+=("$DIST/SHA256SUMS")
  info "Manifest mis à jour : $MANIFEST"

  if [ "$PUBLISH" = true ]; then
    publish_release "$tag" "Android SDK tools $VERSION" \
      "Build-tools et platform-tools Android $VERSION (aarch64, arm, x86_64), repackagés pour CodeIDE à partir de $UPSTREAM_REPO." \
      "${files[@]}"
    info "Pensez à commiter et pousser manifest.json une fois la release publiée."
  else
    info "Fichiers générés dans $DIST :"
    printf '  %s\n' "${files[@]}"
    info "Publication : relancez avec -R, ou : gh release create $tag $DIST/*.tar.xz $DIST/SHA256SUMS --repo $REPO_SLUG"
  fi
}

# --- cmdline -----------------------------------------------------------------

cmd_cmdline() {
  [ -n "$ZIP" ] || die "Option -z requise (zip des command-line tools de Google)."
  need_cmd curl unzip tar xz jq sha256sum

  local zip_path src stage sdkmanager root out sum
  case "$ZIP" in
    http://* | https://*)
      zip_path="$WORK/cmdline-tools.zip"
      info "Téléchargement de $ZIP"
      fetch "$ZIP" "$zip_path"
      ;;
    *)
      [ -f "$ZIP" ] || die "Fichier introuvable : $ZIP"
      zip_path="$ZIP"
      ;;
  esac

  src="$WORK/cmdline-src"
  stage="$WORK/cmdline-stage"
  rm -rf "$src" "$stage"
  mkdir -p "$src" "$stage/cmdline-tools/latest"
  unzip -q -o "$zip_path" -d "$src"

  sdkmanager="$(find "$src" -maxdepth 3 -type f -path '*/bin/sdkmanager' -print -quit)"
  [ -n "$sdkmanager" ] || die "bin/sdkmanager introuvable dans le zip : est-ce bien commandlinetools ?"
  root="$(dirname "$(dirname "$sdkmanager")")"

  # Garde anti-rev-19+ : les cmdline-tools récents délèguent sdkmanager à un
  # binaire natif bin/android que Google ne publie Linux qu'en x86_64 —
  # INEXÉCUTABLE sur les appareils Android aarch64 (majorité des téléphones,
  # seule architecture du bootstrap CodeIDE à ce jour). Publier une telle
  # archive ferait renaître le « not executable: 64-bit ELF file » corrigé
  # en v0.48.0 côté app : on refuse la fabrication, period. Revs 100 % Java
  # acceptées : 12.0 = commandlinetools-linux-11076708_latest.zip (épinglée
  # par la commande android-sdk de CodeIDE).
  if [ -f "$root/bin/android" ] &&
    [ "$(head -c 4 "$root/bin/android" 2>/dev/null | od -An -tx1 | tr -d ' \n')" = "7f454c46" ]; then
    die "Ce zip cmdline-tools porte le binaire natif bin/android (ELF, rev 19+) : sdkmanager y délègue et serait INEXÉCUTABLE sur Android aarch64. Utilise une rev 100 % Java, ex. commandlinetools-linux-11076708_latest.zip (rev 12.0)."
  fi

  cp -a "$root/." "$stage/cmdline-tools/latest/"
  find "$stage" -type d -exec chmod 755 {} +
  chmod 755 "$stage/cmdline-tools/latest/bin/"*

  out="$DIST/cmdline-tools.tar.xz"
  info "Archive : cmdline-tools.tar.xz"
  make_archive "$stage" "$out" cmdline-tools
  sum="$(sha256sum "$out" | cut -d' ' -f1)"

  manifest_update --arg u "$BASE_URL/sdk/cmdline-tools.tar.xz" --arg h "$sum" \
    '.cmdline_tools = $u | .sha256["cmdline-tools.tar.xz"] = $h'
  info "Manifest mis à jour : $MANIFEST"

  if [ "$PUBLISH" = true ]; then
    publish_release sdk "Command-line tools" \
      "Command-line tools Android (sdkmanager, etc.), repackagés pour CodeIDE." "$out"
    info "Pensez à commiter et pousser manifest.json une fois la release publiée."
  else
    info "Fichier généré : $out"
  fi
}

# --- Exécution ---------------------------------------------------------------

mkdir -p "$DIST"
DIST="$(cd "$DIST" && pwd)"
WORK="$DIST/work"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

case "$SUBCOMMAND" in
  sdk) cmd_sdk ;;
  cmdline) cmd_cmdline ;;
esac
