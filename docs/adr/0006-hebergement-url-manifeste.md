# ADR 0006 — Hébergement et URL du manifeste

- Statut : accepté (2026-10-05)
- Contexte : question de recherche R5 (note `docs/research/05`).

## Décision

1. **Assets** : GitHub Releases du dépôt public, une release par
   quadruplet `<id>-<version>-r<rev>`, jamais d'écrasement (workflow
   `publish.yml`). Reprise HTTP vérifiée (206 + `content-range` sur un
   asset réel).
2. **URL du manifeste v2** (constante unique à embarquer par CodeIDE,
   12.7 — jusqu'à activation de Pages par le propriétaire, l'app utilise
   sa constante configurable sur un manifeste de test conforme) :
   - `latest` :
     `https://jjoblab.github.io/codeide-tools/manifests/v2/latest.json`
   - immuable : `…/manifests/v2/<horodatage>.json`
   servis par GitHub Pages (branche `gh-pages` alimentée par
   `publish.yml`). Reprise Range vérifiée sur témoin tiers (206) ;
   à re-mesurer après activation.
3. **manifeste v1** : régénéré depuis le v2 et publié à son URL
   actuelle (`raw.githubusercontent.com/jjoblab/codeide-tools/main/manifest.json`)
   — URL inchangée, composants v1 stables (parité testée par la CI).
4. **Pas de miroir secondaire** à l'initialisation : le tableau `sources`
   (ordonné) existe dans le schéma et le CLI gère les miroirs + journaux
   — l'ajout plus tard est non-cassant. Les composants Google n'ont que
   `dl.google.com` comme source (ADR 0005).

## Justification

GitHub Releases : 2 Gio/asset, bande passante libre pour un dépôt public
(documentation GitHub, 2026-10-05) — largement au-dessus de nos tailles
(max ≈ 15 Mio). Pages donne des URLs immuables par version + pointeur
`latest`, sans authentification ; `raw.githubusercontent` ignore le Range
(200) mais ne sert que le manifeste (quelques Ko).

## Conséquences

- Le propriétaire doit activer GitHub Pages (source : branche `gh-pages`)
  une seule fois ; jusqu'alors, l'URL `latest` répond 404 (prévu par le
  contrat : constante configurable + manifeste de test).
- `publish.yml` pousse `gh-pages` et `main` (manifeste v1 + catalogues
  mis à jour) — commit signé par le bot, jamais d'écrasement d'asset.

## Références

- `docs/research/05-r5-hebergement-manifeste.md` (mesures Range complètes,
  2026-10-05).
- https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases
  (limite 2 Gio, consulté le 2026-10-05).
