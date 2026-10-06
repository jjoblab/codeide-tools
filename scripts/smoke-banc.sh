#!/bin/sh
# smoke-banc.sh — banc bionique multi-arches pour smoke.yml (ADR 0009).
#
# Monte un conteneur Termux (userspace bionique réel) et y exécute
# TÉLÉCHARGEMENT RÉEL (URLs du manifeste, GitHub Releases) + install +
# verify --deep : chaque binaire est exécuté et son motif vérifié.
#
#   aarch64 : runner arm64 public, conteneur natif.
#   x86_64  : runner amd64 public, conteneur amd64 natif.
#   arm     : runner amd64, conteneur armv7 SOUS QEMU (binfmt préalable —
#             l'appelant exécute tonistiigi/binfmt --install arm) :
#             binaire réellement exécuté, CPU émulé, évidence citée telle.
#
# Pourquoi docker run et pas un conteneur de job : les steps d'un job
# s'exécutent en ROOT dans le conteneur — pkg refuse root (« Cannot run
# 'pkg' command as root », run 37426582933) — et l'entrypoint de l'image
# (su → uid 1000 « system ») est le seul mode où pkg fonctionne. Patron
# éprouvé : porte bionic de publish.yml (run 37424794649).
#
# MANIFESTE DE BANC : le CLI consommateur ignore le canal preview (règle
# 12.2 : l'app n'installe que ce qui est attesté). Or le banc teste
# PRÉCISÉMENT la promotion preview → stable de ces entrées : il travaille
# sur une copie du manifeste publié où les canaux preview de l'arche visée
# passent stable. URLs/sha256/tailles INCHANGÉS — téléchargements réels et
# vérifications d'intégrité identiques ; seul le filtre de canal est
# neutralisé (hypothèse sous test — même approche que la porte bionic de
# publish.yml, manifeste de test à channel stable).
#
# L'entrypoint fait env -i : les variables -e n'atteignent pas le conteneur ;
# les valeurs sont EMBEDDÉES dans le script interne APRÈS validation stricte
# (les expressions shell n'existent pas dans les valeurs validées : aucune
# interpolation non contrôlée).
#
# Usage : sh scripts/smoke-banc.sh "<composants id@version,...|''>" "<manifeste>" <arch>
#   à exécuter depuis la racine du dépôt (checkout complet).

set -eu

components=${1:-}
manifest=${2:-}
arch=${3:-}

[ -n "$arch" ] || { printf '%s\n' "usage : $0 \"<composants|vide>\" <manifeste> <aarch64|arm|x86_64>" >&2; exit 2; }
[ -f cli/codeide-sdk ] || { printf '%s\n' "ERREUR : exécuter depuis la racine du dépôt (cli/codeide-sdk introuvable)" >&2; exit 2; }

# --- validation stricte des entrées (échec net, jamais de repli) --------------
python3 - "$components" "$manifest" "$arch" <<'PY'
import re, sys
comps, manifest, arch = sys.argv[1], sys.argv[2], sys.argv[3]
if comps:
    pat = re.compile(r"^[a-z-]+@[0-9][0-9.]*$")
    bad = [s.strip() for s in comps.split(",") if not pat.match(s.strip())]
    if bad:
        sys.exit(f"specs invalides : {bad} — format attendu id@version[,id@version...]")
if not re.match(r"^https://[a-z0-9.:/_-]+$", manifest):
    sys.exit(f"URL de manifeste invalide (caractères non autorisés) : {manifest}")
if arch not in ("aarch64", "arm", "x86_64"):
    sys.exit(f"arche inconnue : {arch} (supportées : aarch64, arm, x86_64)")
PY

mkdir -p smoke/home smoke/tmp
chmod -R a+rwX smoke

# --- manifeste de banc : copie du publié, preview → stable pour l'arche ------
python3 - "$manifest" "$arch" > smoke/banc-manifest.json <<'PY'
import json, sys, urllib.request
url, arch = sys.argv[1], sys.argv[2]
with urllib.request.urlopen(url) as r:
    data = json.load(r)
flipped = 0
for c in data.get("components", []):
    if c.get("channel") == "preview" and c.get("arch") in (arch, "any"):
        c["channel"] = "stable"
        flipped += 1
json.dump(data, sys.stdout, indent=2)
print()
print(f"manifeste de banc : {flipped} entrée(s) preview→stable ({arch}) — URLs/sha inchangés",
      file=sys.stderr)
PY

# --- plateforme docker ---------------------------------------------------------
# arm : aucun runner public 32 bits → émulation qemu-user (binfmt posé par
# l'appelant). # shellcheck disable=SC2086 : découpage voulu de $platform.
platform=""
if [ "$arch" = arm ]; then platform="--platform linux/arm/v7"; fi

# --- script interne (bionique) : valeurs validées embarquées, \$ = conteneur --
script=$(cat <<EOF
set -eu
arch="$arch"
comps="$components"
echo "manifeste source : $manifest"
export PATH=/data/data/com.termux/files/usr/bin:\$PATH
export HOME=/smoke/home TMPDIR=/smoke/tmp
export CODEIDE_TOOLS_MANIFEST=/smoke/banc-manifest.json
u=\$(uname -m)
echo "banc : uname -m=\$u (arche cible : \$arch)"
case \$arch:\$u in
  aarch64:aarch64|x86_64:x86_64|arm:armv*l) ;;
  *) echo "AVERTISSEMENT : uname -m inattendu (\$u) pour \$arch — évidence à examiner" ;;
esac
pkg update -y || true
pkg install -y curl jq coreutils tar xz-utils
# cmdline-tools (profil default) exige une JVM pour sdkmanager --version.
need_java=0
if [ -z "\$comps" ] || printf '%s\n' "\$comps" | tr ',' '\n' | grep -q '^cmdline-tools@'; then
  need_java=1
fi
if [ "\$need_java" = 1 ]; then
  pkg install -y openjdk-21 || pkg install -y openjdk-17
fi
cd /repo
if [ -n "\$comps" ]; then
  sh cli/codeide-sdk install \$(printf '%s\n' "\$comps" | tr ',' ' ') --arch "\$arch" --root /smoke/sdk || exit 5
else
  sh cli/codeide-sdk install --profile default --arch "\$arch" --root /smoke/sdk || exit 5
fi
# Exécution RÉELLE de chaque binaire installé (aapt2 version, adb --version…) :
sh cli/codeide-sdk verify --deep --root /smoke/sdk || exit 5
note=""
if [ "\$arch" = arm ]; then note=" — CPU émulé qemu-arm, bionique réel"; fi
printf 'SMOKE OK bionic %s%s %s\n' "\$arch" "\$note" "\$(date -u +%Y-%m-%dT%H:%M:%SZ)" > /smoke/smoke-proof.txt
cat /smoke/smoke-proof.txt
EOF
)

# --- exécution : entrypoint préservé (ne PAS --entrypoint) ---------------------
docker run --rm $platform \
  -v "$PWD:/repo" -v "$PWD/smoke:/smoke" \
  termux/termux-docker:latest \
  /data/data/com.termux/files/usr/bin/bash -exc "$script"
