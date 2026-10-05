# ADR 0009 — Pipeline CI : build, smoke test obligatoire, publication, veille

- Statut : accepté (2026-10-05)
- Contexte : prompt 2 § 7 (pipeline CI), § 11 (T4/T7), § 13.

## Décision

1. **`ci.yml`** (push/PR) : `shellcheck` sur tous les scripts, validation
   du catalogue contre le schéma, tests bats du CLI, génération du
   manifeste **à blanc** + contrôle que le manifeste committé est à jour,
   test de reproductibilité (rebuild × 2, hash identiques), test de
   parité v1 (le `manifest.json` v1 généré est stable pour les composants
   existants).
2. **`build-component.yml`** (réutilisable, `workflow_dispatch`) : matrice
   composant × version × arch ; télécharge l'amont (épinglé), fabrique
   l'archive déterministe (`build/package.sh`), contrôle ELF, calcule les
   sommes, produit le fichier de provenance JSON ; en attente de
   publication (artefact).
3. **`smoke.yml`** : **porte de publication** — une version qui échoue au
   smoke test n'entre pas dans le manifeste (§ 0 règle 3). Exécution
   bionique réelle via runner `ubuntu-24.04-arm` + conteneur
   `termux/termux-docker` (aarch64 bionic), `codeide-sdk install
   --profile …` puis `verify --deep` (exécute chaque binaire, compare la
   sortie attendue). **Piste à vérifier au premier run** (non exécutable
   dans l'environnement de travail) ; en cas d'impossibilité, la version
   est publiée `channel: preview` et marquée non testée — jamais
   `stable` sans exécution.
4. **`publish.yml`** : crée la release `<id>-<version>-r<rev>` (assets +
   `SHA256SUMS` + provenance + attestations), régénère manifeste v2
   (immuable horodaté + `latest`) **et** v1, pousse `main` (catalogue +
   manifestes) et `gh-pages`. Jamais d'écrasement d'asset : un quadruplet
   publié est immuable (correctif = révision `r2`).
5. **`watch-upstream.yml`** (hebdomadaire) : compare les releases amont
   (Lzhiyong atom, `repository2-3.xml` Google) au catalogue, ouvre une
   issue « nouvelle version disponible » avec diff pré-rempli. Aucune
   publication automatique : l'ajout reste une PR humaine (catalogue =
   code review).
6. Rétention/dépréciation : les releases ne sont jamais supprimées
   (immuabilité) ; le manifeste peut retirer une version du profil
   `default` (dépréciation annoncée dans le `CHANGELOG.md`), sans toucher
   aux assets.

## Conséquences

- Toute entrée `status: tested` de `COMPAT.md` et toute publication
  `stable` traîne une preuve d'exécution (log de `smoke.yml`).
- L'auto-installation d'AGP (ADR 0003) et le smoke test bionique
  nécessitent l'activation des runners arm64 publics (gratuits pour les
  dépôts publics) — à vérifier au premier run.

## Références

- Prompt 2 § 7, § 12.6 (CLI en CI), § 14.
- Note `docs/research/06` (attestations), `05` (Pages).
