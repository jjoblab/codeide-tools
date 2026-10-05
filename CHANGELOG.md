# CHANGELOG

Format : [Keep a Changelog](https://keepachangelog.com/fr/) — versions du
dépôt `codeide-tools` (les versions des COMPOSANTS suivent l'amont Android ;
cette liste décrit le dépôt).

## [2.0.0] — 2026-10-05

Refonte complète (prompt 2 v2.1) : multi-versions, reproductible, vérifiable.

### Ajouté

- **Manifeste v2** (`schemaVersion: 2`) : schéma JSON normatif
  (`schema/manifest.v2.schema.json`), composants avec `revision` (immuable par
  quadruplet), `channel` (stable/preview), `sources` ordonnées (miroirs),
  `sha256`/`size` obligatoires, `installPath` exclusif, `critical`,
  `requires` (`jdk>=N`…), `verify` (commande + motif, exécutée sans shell),
  profils et matrice de compatibilité. Publié à URLs immuables + `latest`
  (GitHub Pages — ADR 0006).
- **Catalogue source de vérité** (`catalog/`) : ajouter une version = un
  fichier + une PR ; manifeste, `COMPAT.md`, workflows et README en dérivent.
- **Archives déterministes** (`build/package.sh`) : entrées triées, `mtime`
  imposé (`SOURCE_DATE_EPOCH`), propriétaire 0:0, permissions explicites,
  `xz -T1` — deux builds successifs donnent le même hash (testé) ; contrôle
  **ABI ELF** de chaque binaire natif à la fabrication.
- **Couverture initiale** : build-tools et platform-tools 33.0.3 / 34.0.3 /
  35.0.2 (aarch64, arm, x86_64, amont Lzhiyong épinglé), plateformes
  android-35/36/37.2 et cmdline-tools 12.0/17.0 (pointeurs directs Google,
  SHA-256 épinglés).
- **CLI `codeide-sdk`** (POSIX sh) : `list`/`install`/`remove`/`verify
  --deep`/`doctor`/`env --print`/`--json` ; cache adressé par SHA-256, reprise
  HTTP, déplacement atomique, verrou, codes de sortie documentés — 26 tests
  bats.
- **Vecteurs de référence** (`tests/golden/`) : manifestes valides et
  invalides (rejetés par le schéma), faux manifeste conforme pour la
  constante de test de l'app (12.7), archives minuscules à sommes connues.
- **CI** : `ci.yml` (shellcheck, schéma, bats, manifestes à jour, parité v1,
  immuabilité, reproductibilité), `build-component.yml` (matrice),
  `publish.yml` (**smoke bionique aarch64 obligatoire avant publication**,
  release immuable + provenance + attestations + gh-pages),
  `watch-upstream.yml` (veille hebdomadaire amont, issue avec diff).
- **Recherche R1-R7 + ADR 0001-0010** : origine des binaires, matrice
  compat AGP mesurée (aapt2 33 ne lit pas android.jar ≥ 35 ; AGP 9.x min
  build-tools 36.0.0 ; override honoré), cmdline-tools 100 % Java mesurés
  JDK 17/21, licences (clause 3.4 : pointeurs directs Google), hébergement
  (Range vérifié), intégrité (SHA-256 + attestations), contrat
  d'environnement 12.4 validé sur hôte (exigences AGP bissectées).

### Modifié

- `manifest.json` (v1) est désormais **généré depuis le v2** (parité
  octet-identique testée) et reste publié à son URL historique — les apps v1
  installées continuent de fonctionner sans changement.
- `scripts/codeidesetup` devient un **shim de dépréciation** vers
  `codeide-sdk` (options v1 principales conservées).
- `scripts/package-sdk.sh` (v1) est retiré (remplacé par `build/package.sh`) ;
  l'historique git le conserve.

### Sécurité

- Aucune licence pré-acceptée n'est livrée (12.5) : l'app écrit `licenses/`
  après acceptation explicite.
- Sommes SHA-256 obligatoires partout ; immuabilité des quadruplets publiés
  vérifiée en CI.

## [1.x] — 2024 → 2026-09

État initial (dépôt v1) : manifeste AndroidIDE-like + SHA-256, une version
(35.0.2), installeur `codeidesetup`, publication par workflows manuels. Voir
l'historique git.
