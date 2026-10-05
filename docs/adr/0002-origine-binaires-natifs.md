# ADR 0002 — Origine des binaires natifs : Lzhiyong épinglé + pipeline propre préparé

- Statut : accepté (2026-10-05)
- Contexte : question de recherche R1 (note `docs/research/01`).

## Décision

1. **Consommer `Lzhiyong/android-sdk-tools`** (épinglage : tag amont +
   SHA-256 du zip amont dans le catalogue) pour build-tools et
   platform-tools bioniques, versions 33.0.3, 34.0.3, 35.0.2 ×
   {aarch64, arm, x86_64}. L'amont est figé (août 2024) mais couvre le
   critère « trois versions » ; ses binaires sont statiques, ELF
   `for Android 30` (NDK r27b), Apache-2.0.
2. **Préparer sans activer** le pipeline propre (`build/native/`) :
   recette versionnée (image Docker par digest, NDK r26d — pas de rc,
   tag AOSP, `--api 30`, patchs) pour construire 36.x/37.x le jour où
   le besoin est confirmé (AGP 9.x exige ≥ 36.0.0 — ADR 0003).
   `build-component.yml` accepte `source: native` pour l'exécuter en CI.
   **Non vérifié** : aucun build natif n'a été exécuté ici (pas de NDK
   dans l'environnement de travail).
3. **`aapt2` reste dans l'archive build-tools** (pas de composant autonome
   au catalogue) : le contrat 12.4 retombe sur build-tools ; moins
   d'artefacts ; la matrice de compat épingle la version de build-tools
   (donc d'aapt2) par AGP. Un composant `aapt2` autonome reste ajoutable
   plus tard (champs du schéma inchangés) si le besoin de versions
   découplées apparaît.
4. `minAndroidApi = 30` (constaté dans l'ELF, aide de `build.py` amont) ;
   CodeIDE `minSdk = 26` : les composants exigent Android 11 —
   informatif dans le manifeste, l'app peut afficher la contrainte.

## Justification

Lzhiyong publie exactement la même recette qu'AndroidIDE
(`AndroidIDEOfficial/platform-tools` @ c000942 : `get_source.py`,
`build.py --api 30`, CMake par outil, patchs) **sans** ses défauts de
reproductibilité Docker (NDK rc) — mais avec des sorties publiques
épinglables. Le pipeline propre est le seul chemin vers 36.x, au coût
d'une mise au point significative (patchs à porter par tag) ; le
consommer d'abord garantit la couverture aujourd'hui (critère
d'acceptation : trois versions de build-tools).

## Conséquences

- La couverture 36.x (AGP 9.x natif) dépend du pipeline (b) — voir
  ADR 0003 pour les stratégies de compat intermédiaires.
- arm et x86_64 : publiés par Lzhiyong mais « non testés » par l'auteur
  (README) → couverts par `smoke.yml` avant toute entrée « testé » dans
  le manifeste.
- Toute nouvelle version = nouvelle entrée de catalogue avec le SHA-256
  du zip amont ; les sommes de NOS archives sont calculées à la
  fabrication (reproductibles).

## Références

- `docs/research/01-r1-origine-binaires.md` (inventaire vérifié, tableau
  comparatif, mesures ELF).
- `Lzhiyong/android-sdk-tools` @ 5071328 (README, build.py l. 147,
  LICENSE.txt) ; `AndroidIDEOfficial/platform-tools` @ c000942.
