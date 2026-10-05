# R5 — Hébergement, disponibilité et URL du manifeste

- Date : 2026-10-05 (UTC)
- Statut : décidé (voir ADR 0006)

## Question

Limites des assets GitHub Releases, URL stables et immuables pour le
manifeste, miroir secondaire éventuel, support de la **reprise HTTP (Range)**
exigée par l'app, et **URL du manifeste** à faire embarquer par CodeIDE
(12.7).

## Méthode (commandes exactes)

```sh
# Disponibilité des releases v1 existantes (rétrocompatibilité)
curl -s -o /dev/null -w "%{http_code}" -I -L \
  https://github.com/jjoblab/codeide-tools/releases/download/v35.0.2/build-tools-35.0.2-aarch64.tar.xz
curl -s -o /dev/null -w "%{http_code}" -I -L \
  https://github.com/jjoblab/codeide-tools/releases/download/sdk/cmdline-tools.tar.xz
# Reprise Range sur chaque type d'hébergement visé
curl -s -I -L -r 0-1023 <URL asset release>          # attendu 206 + content-range
curl -s -I -r 0-1023 https://dl.google.com/android/repository/platform-36_r02.zip
curl -s -o /dev/null -w "%{http_code} %{size_download}" -r 0-511 https://pages.github.com/index.html
curl -fsS -r 0-99999  -o p1 <URL dl.google> ; curl -fsS -r 100000-199999 -o p2 <URL dl.google>
curl -s -I -r 0-1023 https://raw.githubusercontent.com/jjoblab/codeide-tools/main/manifest.json
```

## Résultats (tous mesurés le 2026-10-05)

| Hôte | Code observé | Reprise Range | Observation |
|---|---|---|---|
| Asset de release GitHub (v35.0.2) | 302 → **206** | **oui** (`accept-ranges`, `content-range: bytes 0-1023/3015120`) | asset de 2 876 Mio servi via CDN (`objects.githubusercontent.com`) |
| `dl.google.com` (plateformes, cmdline-tools) | **206** | **oui** (206 + 2 lectures partielles de 100 000 octets chacune, vérifiées) | CDN Google, contenu statique |
| GitHub Pages (témoin `pages.github.com`) | **206**, 512 octets servis | **oui** | comportement CDN vérifié sur un site tiers ; `*.github.io` du dépôt : à confirmer après activation |
| `raw.githubusercontent.com` (manifest.json actuel) | **200** (Range ignoré, `accept-ranges` annoncé) | **non** | acceptable : le manifeste pèse quelques Ko ; jamais utilisé pour une archive |

Disponibilité v1 vérifiée : release `v35.0.2` (6 archives) et release `sdk`
→ HTTP 200 sur les asset URLs publiées ; `raw.githubusercontent…/main/manifest.json`
→ 200. Rien ne bouge (§ 9 du prompt respecté).

Limites GitHub Releases (documentation officielle, « About releases ») :
**2 Gio par fichier**, pas de quota total documenté pour un dépôt public ;
bande passante non facturée. Nos plus gros assets potentiels : archives de
plateformes reconditionnées (~60 Mio) — loin de la limite ; les plateformes
restent de toute façon servies par `dl.google.com` (R4).

## Décision

1. **Assets** : GitHub Releases du dépôt public `jjoblab/codeide-tools`,
   une release par quadruplet versionné `<id>-<version>-r<rev>` ; jamais
   d'écrasement d'asset (workflow `publish.yml`). Reprise : OK (206 mesuré).
2. **URL du manifeste v2** (à embarquer par CodeIDE dans sa constante
   unique, 12.7) :
   - point flottant « latest » :
     `https://jjoblab.github.io/codeide-tools/manifests/v2/latest.json`
   - immuable par génération : `…/manifests/v2/<AAAAMMJJ>-<HHMMSS>.json`
   servis par **GitHub Pages** sur le dépôt (publiés par le workflow
   `publish.yml` dans la branche `gh-pages`, créée automatiquement ; Pages
   est à activer une fois par le propriétaire — jusqu'à activation, l'URL
   répond 404 et l'app doit utiliser sa constante configurable pointant un
   manifeste de test, prévu par 12.7).
   Reprise Range sur Pages : vérifiée sur témoin tiers (206) ; marquée
   **à confirmer** sur `jjoblab.github.io` après activation.
   Alternativement, `raw.githubusercontent.com/jjoblab/codeide-tools/main/
   manifest.v2.json` reste un point de repli (mutable, mais manifeste
   petit : reprise non requise).
3. **Miroir secondaire** : aucune entrée `sources` supplémentaire à la
   publication initiale (aucun miroir disponible ; le schéma et le CLI
   gèrent déjà un tableau ordonné — l'ajout d'un miroir plus tard est
   non-cassant). Pour les composants Google, l'unique source est
   `dl.google.com` (R4).
4. **manifest.json v1** (rétrocompatibilité) : reste publié à son URL
   actuelle (`raw.githubusercontent.com/…/main/manifest.json`), régénéré
   depuis le v2 à chaque publication — URL inchangée, contenu stable
   pour les composants existants (parité testée par la CI).

## Sources

- Mesures ci-dessus (2026-10-05, curl 8.x, HTTP/2).
- Documentation GitHub Releases : « About releases » — limite de 2 Gio par
  fichier (https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases,
  consulté le 2026-10-05).
- `repository2-3.xml` (2026-10-05) pour les URLs `dl.google.com` exactes.

## Non vérifié

- `jjoblab.github.io/codeide-tools` : Pages n'est pas encore activé sur le
  dépôt (404 attendu) — à activer par le propriétaire, puis re-mesurer
  Range et enregistrer le résultat dans ce fichier.
- Quotas réels de bande passante : aucun chiffre officiel au-delà de
  « illimité pour les dépôts publics » ; à surveiller en pratique.
