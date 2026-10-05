# ADR 0001 — Architecture v2 : catalogue source de vérité, manifeste v2, archives déterministes

- Statut : accepté (2026-10-05)
- Contexte : prompt 2 (refonte `codeide-tools` v2.1), § 2, 4, 5, 6, 9.

## Contexte

Le dépôt v1 publie une seule version (35.0.2) via un workflow manuel, avec
un manifeste aux clés héritées d'AndroidIDE (`_35_0_2`), sans plateformes
ni matrice de compatibilité ; l'app et le script `codeidesetup` dupliquent
la logique d'installation. Le contrat commun (prompt 2 § 12) impose un
manifeste v2 extensible consommé par l'app Kotlin et par un CLI shell, des
archives reproductibles et la rétrocompatibilité v1.

## Décision

1. **Le catalogue (`catalog/`) est la seule source de vérité** :
   `catalog/components/<id>.yaml` (une définition par composant),
   `catalog/compat.yaml` (matrice AGP), `catalog/profiles.yaml`
   (ensembles recommandés). Manifeste, `COMPAT.md`, workflows et README en
   dérivent (générateur `build/gen-manifest.py`).
2. **Manifeste v2** conforme à 12.2 : schéma JSON versionné
   (`schema/manifest.v2.schema.json`, `schemaVersion: 2`), champs normatifs
   `id/version/revision/arch/channel/sources/sha256/size/installPath/
   critical/requires/verify`, profils et compat. Champs additifs
   documentés : `archiveRoot` (optionnel, informatif — pour les zips
   externes dont la racine ≠ `installPath`, ex. plateformes Google ;
   ignoré par les clients 2.x qui n'ont pas besoin de déplacer la racine).
3. **Archives** : `.tar.xz` nommées `<id>-<version>-r<rev>-<arch>.tar.xz`,
   racine = racine du SDK, tous chemins sous l'`installPath` exclusif du
   composant (12.3). Fabrication **déterministe** (`build/package.sh`) :
   entrées triées, `SOURCE_DATE_EPOCH` fixé, propriétaire 0:0,
   permissions explicites (755 exécutables), `xz` niveau fixe ; contrôle
   de l'ABI ELF de chaque binaire natif contre `arch` (échec = pas
   d'archive).
4. **Rétrocompatibilité** : `manifest.json` (v1) est **généré** depuis le
   v2 (composants exprimables en v1 uniquement) à chaque publication ;
   les releases v1 existantes (`v35.0.2`, `sdk`) et leurs URLs ne changent
   jamais. Le manifeste v2 est publié à URL immuable par génération +
   pointeur `latest` (ADR 0006).
5. **Immuabilité** : un quadruplet (`id`, `version`, `revision`, `arch`)
   publié n'est jamais modifié — un correctif = `r2`. La CI vérifie
   qu'aucun `sha256` publié ne change entre deux générations.

## Conséquences

- Ajouter une version = un fichier de catalogue + une PR ; tout le reste
  est automatique (critère d'acceptation).
- `codeidesetup` devient un shim de `cli/codeide-sdk` (ADR 0010) ; l'app
  CodeIDE n'appelle ni n'embarque le CLI (12.6) — l'équivalence passe par
  le manifeste, le format des archives et `tests/golden/`.
- Vecteurs de référence (`tests/golden/`) publiés dès T2 (12.7) : le
  prompt 1 les importe dans ses tests.

## Références

- Prompt 2 § 4-6, 9, 12.2, 12.3, 12.7.
- Notes de recherche `docs/research/01` (amonts), `07` (validation des
  exigences de contenu, découpage des archives).
