#!/bin/sh
# promote-smoke.sh — orchestrateur mainteneur de la promotion smoke (ADR 0009).
#
# Après un run smoke.yml VERT : bascule les entrées catalogue pending → ok
# (promote-smoke.py, édition chirurgicale), régénère les manifestes
# (v2 + v1 + COMPAT.md), committe/pousse main, puis republie gh-pages
# (historique manifests/v2 immuable conservé : clone de la branche, ajout
# ts.json + remplacement de latest.json — même logique que publish.yml).
#
# Le catalogue = code review : ce commit EST la revue (message détaillé,
# évidence = URL du run). Exige GITHUB_TOKEN (push main + gh-pages).
#
# Usage :
#   GITHUB_TOKEN=… sh scripts/promote-smoke.sh <run_id> <émulation_arm:oui|non> \
#        <id>@<version>:<arch> [<id>@<version>:<arch>…]
#   à exécuter depuis la racine du dépôt, arbre propre.

set -eu

run_id=${1:-}
emul_arm=${2:-}
shift 2 2>/dev/null || true
specs="$*"

[ -n "$run_id" ] && [ -n "$emul_arm" ] && [ -n "$specs" ] || {
  printf '%s\n' "usage : GITHUB_TOKEN=… $0 <run_id> <émulation_arm:oui|non> id@version:arch …" >&2
  exit 2
}
[ -n "${GITHUB_TOKEN:-}" ] || { printf '%s\n' "ERREUR : GITHUB_TOKEN requis (poussées main + gh-pages)" >&2; exit 2; }
[ -f cli/codeide-sdk ] || { printf '%s\n' "ERREUR : exécuter depuis la racine du dépôt" >&2; exit 2; }
[ -z "$(git status --porcelain)" ] || { printf '%s\n' "ERREUR : arbre de travail non propre — committer/écartier d'abord" >&2; exit 2; }

repo_slug=$(git remote get-url origin | sed 's#.*github.com[:/]##; s#\.git$##')
run_url="https://github.com/$repo_slug/actions/runs/$run_id"
push_url="https://x-access-token:${GITHUB_TOKEN}@github.com/${repo_slug}.git"

# 1. Bascule catalogue (chirurgicale, idempotente, échec net si motif absent).
python3 scripts/promote-smoke.py "$run_url" "$emul_arm" $specs

# 2. Manifestes régénérés (v2 + v1 + COMPAT.md).
python3 build/gen-manifest.py

# 3. Commit + push main (identité locale déjà configurée).
specs_lisibles=$(printf '%s\n' $specs | tr '\n' ' ' | sed 's/ $//')
git add manifest.json docs/COMPAT.md dist/manifest.v2.json catalog
git diff --cached --quiet && { printf '%s\n' "rien à committer (déjà promu ?)" >&2; exit 1; }
git commit -m "chore: promotion smoke → stable ($specs_lisibles)

Évidence : $run_url (verify --deep sur bionique, téléchargements réels).
Catalogue : entrées smoke pending → ok ; manifestes v2/v1 + COMPAT.md
régénérés (channel stable pour les arches attestées)."
git push "$push_url" main

# 4. gh-pages : historique immuable conservé, latest.json remplacé.
ts=$(date -u +%Y%m%d-%H%M%S)
rm -rf gh-pages
git clone -q --branch gh-pages --depth 1 "$push_url" gh-pages
mkdir -p gh-pages/manifests/v2
cp dist/manifest.v2.json "gh-pages/manifests/v2/$ts.json"
cp dist/manifest.v2.json gh-pages/manifests/v2/latest.json
(
  cd gh-pages
  git config user.name "jjoblab"
  git config user.email "150948254+jjoblab@users.noreply.github.com"
  git add -A
  git diff --cached --quiet || git commit -qm "manifeste v2 $ts — promotion smoke $run_id"
  git push -q origin gh-pages
)
rm -rf gh-pages   # nettoyage : le clone ne doit pas polluer l'arbre de travail

printf '%s\n' "promotion terminée : main poussé, gh-pages $ts.json + latest.json publiés"
