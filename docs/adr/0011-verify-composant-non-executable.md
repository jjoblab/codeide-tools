# ADR 0011 — verify d'un composant non exécutable (plateformes) : sémantique de présence

- Statut : accepté (2026-10-05) — divergence de contrat signalée (règle § 12 :
  constat écrit dans CE dépôt + signalement à l'utilisateur ; pas de
  modification du contrat de notre seul côté)

## Contexte (divergence constatée)

Le contrat 12.2 rend le champ `verify` **requis pour tout composant** et fixe
sa sémantique : « Exécuté sans shell… Succès = code de sortie attendu **et**
regex trouvée dans stdout + stderr ». Or une **plateforme** (`platform`,
composant `any`) ne contient **aucun exécutable** : `android.jar`,
`build.prop`, `data/`, `templates/`, `skins/` — rien qui se lance (vérifié
sur les zips Google 35/36/37.2, note de recherche 02). L'exigence
« rien n'est supporté sans test d'exécution » se traduit pour une plateforme
par **compilation réelle contre `android.jar`** (build AGP minimal — c'est
exactement la preuve enregistrée dans `catalog/compat.yaml` : cellules
`cs=35/36/37` du 2026-10-05), pas par une commande du composant.

## Décision

1. Le champ `verify` des composants `platform` pointe le **fichier pivot**
   (`platforms/<N>/android.jar`) — conforme au schéma (chemin relatif à la
   racine du SDK) mais **non exécutable** : c'est une convention documentée,
   pas une commande.
2. Les clients (CLI `codeide-sdk`, app CodeIDE) appliquent la sémantique
   suivante, explicite et journalisée, **jamais muette** : si la cible du
   `verify` existe mais n'est pas exécutable → vérification de **présence**
   (« OK … (présence — composant any non exécutable, ADR 0011) »). Le CLI
   implémente ce comportement (`run_verify_one`).
3. L'évidence d'« exécution » d'une plateforme reste le **build AGP réel**
   (cellules de mesure de `catalog/compat.yaml`, reprises par `smoke.yml`
   quand il testera un build AGP minimal sur appareil).
4. Toute généralisation future (composant `any` sans exécutable) hérite de
   cette convention. Une modification de la sémantique de `verify` dans le
   contrat commun = incrément de `schemaVersion` + ADR dans **les deux**
   dépôts (règle § 12) — non déclenchée ici : nous ajoutons une convention
   d'interprétation, le schéma et les champs restent inchangés.

## Conséquences

- `codeide-sdk verify` sur un SDK avec plateformes n'échoue pas sur
  l'inexécutabilité de `android.jar` : présence vérifiée, journalisée comme
  telle.
- Le prompt 1 (app CodeIDE) doit implémenter la même convention côté Kotlin
  (même ADR à déposer dans son dépôt — clause § 12).
- Les autres composants (build-tools, platform-tools, cmdline-tools,
  `test-tools` des vecteurs) gardent la sémantique complète
  exécution + motif.

## Références

- Prompt 2 § 12.2 (verify requis, sémantique), § 12 (divergences).
- Note `docs/research/02` (builds réels contre android-35/36/37.2),
  `07` § 3 (contenu des plateformes).
- `cli/codeide-sdk` : `run_verify_one` (implémentation).
