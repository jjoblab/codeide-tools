# R1 — Origine des binaires natifs (build-tools, platform-tools) pour bionic

- Date : 2026-10-05 (UTC)
- Statut : décidé (voir ADR 0002)

## Question

D'où proviennent les binaires natifs du SDK Android exécutables sur téléphone
(`aapt`, `aapt2`, `aidl`, `zipalign`, `dexdump`, `split-select`, `adb`,
`fastboot`, `mke2fs`, `sqlite3`…) pour bionic (aarch64, arm, x86_64) ?
(a) continuer à consommer `Lzhiyong/android-sdk-tools` ;
(b) pipeline de build propre (NDK + sources AOSP à un tag, en GitHub Actions).
`aapt2` doit-il devenir un composant autonome (précédent AndroidIDE) ?

## Méthode (commandes exactes)

```sh
# Inventaire des releases Lzhiyong (API GitHub anonyme limitée → flux atom)
curl -fsSL https://github.com/Lzhiyong/android-sdk-tools/releases.atom
curl -fsSL "https://github.com/Lzhiyong/android-sdk-tools/releases/expanded_assets/<tag>"
# Catalogue officiel Google (versions existantes côté amont)
curl -fsSL https://dl.google.com/android/repository/repository2-3.xml
# Recettes de build amont (lecture du code)
git clone --depth 5 https://github.com/Lzhiyong/android-sdk-tools.git
git clone --depth 5 https://github.com/AndroidIDEOfficial/platform-tools.git   # @c000942
```

## Résultats

### Couverture de `Lzhiyong/android-sdk-tools` (vérifié 2026-10-05, flux atom + expanded_assets)

| Tag | Publiée | Assets (build-tools + platform-tools dans chaque zip) |
|---|---|---|
| 35.0.2 | 2024-08-20 | static-aarch64 (13,7 Mio), static-arm (11,8 Mio), static-x86 (13,8 Mio), static-x86_64 (13,5 Mio) |
| 34.0.3 | 2023-09-15 (éditée 2024-11-22) | static-aarch64, static-arm, static-i686, static-x86_64 |
| 33.0.3 | 2023-09-15 | static-aarch64, static-arm, static-x86, static-x86_64 |

Amont figé depuis **août 2024** (aucun 36.x ; la chaîne CodeIDE documente
pourtant build-tools 36.0.0 pour AGP 9.4, `docs/ENVIRONNEMENT.md` du dépôt
CodeIDE, vérifié 2026-09-22). README du dépôt : « Currently, only aarch64 has
been tested » — arm et x86_64 sont publiés mais non testés par l'auteur.

### Catalogue Google (repository2-3.xml, 2026-10-05)

Build-tools stables Linux : 37.0.0, 36.1.0, 36.0.0, 35.0.1, 35.0.0, 34.0.0,
33.0.3… (binaires x86_64 Linux — inutilisables sur téléphone bionic).
Plateformes stables : android-37.2 (r01), 37.1, 37.0 (r02), 36.1, 36 (r02),
35 (r02)… cmdline-tools : revs 1.0 → 23.0 (voir note R3).

### Recettes de build (a) ≡ (b)

`Lzhiyong/android-sdk-tools` et `AndroidIDEOfficial/platform-tools` @ `c000942`
portent la **même recette** (`get_source.py` + `build.py` + `CMakeLists` par
outil + `patches/`) :

- sources AOSP à un tag (`get_source.py --tags platform-tools-35.0.2`,
  `repos.json` liste les dépôts android.googlesource.com) ;
- `build.py --ndk … --abi … --api 30 --target <outil>` — **API minimale 30**
  (aide de `build.py`, ligne 147/150 : `default=30, "min api is 30"`) ;
- build-tools : aapt, aapt2, aidl, zipalign, dexdump, split-select ;
- platform-tools : adb, fastboot, e2fsprogs (mke2fs), f2fs-tools, sqlite3,
  dmtracedump, etc1tool, hprof-conv ;
- licence du dépôt et des sources AOSP : **Apache-2.0** (`LICENSE.txt`,
  177 lignes, vérifié) → redistribution autorisée avec conservation de la
  licence et du NOTICE (voir note R4).

Faiblesses du Dockerfile d'AndroidIDE : `ubuntu:latest` + NDK **r26-rc1**
(HEAD vérifié `c000942`) — non reproductible. Le fork Lzhiyong ne publie ni
Dockerfile ni CI ; la chaîne n'est pas plus reproductible, mais les sorties
sont publiques et épinglables par SHA-256.

### Comparaison

| Critère | (a) consommer Lzhiyong | (b) pipeline propre (Actions) |
|---|---|---|
| Versions couvertes | 33.0.3 / 34.0.3 / 35.0.2 (figé 2024-08) | toute tag AOSP `platform-tools-X` (36.x, 37.x atteignables) |
| Reproductibilité des binaires | non (sorties de l'amont) — mais **archives reproductibles** de notre côté (entrée fixe → hash fixe) | atteignable (épingle Docker par digest, NDK, tag, patchs) — coût élevé |
| Durée / maintenance | quasi nulle (téléchargement + reconditionnement) | build ~heures + protoc + suivi des patchs à chaque tag |
| Licences | Apache-2.0 (AOSP), OK | Apache-2.0 (AOSP), OK |
| Risque amont | dépôt personnel, plus mis à jour, outils testés aarch64 seuls | nous dépendons de nous-mêmes ; première mise au point significative |
| Vitesse de couverture 36.x | **impossible aujourd'hui** | possible après mise au point (non vérifié ici) |

### `aapt2` autonome ?

AndroidIDE publie `aapt2-<abi>` **séparément** (dépôt
`AndroidIDEOfficial/platform-tools`, tags v34.0.x, révisions -r01/-r02).
Pour CodeIDE : le binaire est déjà **dans** l'archive build-tools de Lzhiyong
(disposition officielle `build-tools/<v>/aapt2`). Le contrat 12.4 prévoit la
lecture « composant `aapt2` du plan s'il existe, sinon du composant
build-tools » : garder `aapt2` **dans** build-tools (pas de composant
autonome au catalogue) minimise le nombre d'artefacts sans rien interdire
plus tard — la matrice de compat (compat.yaml) épingle la version de
build-tools (donc d'aapt2) par AGP.

## Décision

1. **(a) aujourd'hui** : consommer `Lzhiyong/android-sdk-tools` épinglé par
   tag + SHA-256 du zip amont, pour 33.0.3, 34.0.3, 35.0.2 (aarch64, arm,
   x86_64). Critère d'acceptation « trois versions de build-tools » tenu.
   Les archives que NOUS fabriquons sont déterministes (rebuild → même hash).
2. **(b) est préparé, pas activé** : `build/native/` porte la recette
   versionnée (image par digest, NDK r26d, tag AOSP, `--api 30`, patchs) pour
   bâtir 36.x/37.x le jour où le besoin est confirmé — **non vérifié**
   (aucun build exécuté ici : pas de NDK dans cet environnement, build à
   lancer en GitHub Actions par `build-component.yml` avec
   `source: native`).
3. `aapt2` reste dans l'archive build-tools (pas de composant autonome) ;
   le contrat 12.4 reste respecté (le plan retombe sur build-tools).
4. `minAndroidApi = 30` pour tous les binaires Lzhiyong (aide de `build.py`
   de l'amont, API par défaut et minimum) ; CodeIDE `minSdk = 26`
   (`gradle/libs.versions.toml` du dépôt CodeIDE, vérifié) : les binaires
   exigent Android 11 (API 30) au minimum — documenté dans le manifeste,
   l'app affichera la contrainte si l'appareil est plus vieux.

## Sources

- `https://github.com/Lzhiyong/android-sdk-tools/releases.atom` (2026-10-05)
- `expanded_assets/{35.0.2,34.0.3,33.0.3}` (2026-10-05)
- `https://dl.google.com/android/repository/repository2-3.xml` (2026-10-05,
  419 185 octets)
- `Lzhiyong/android-sdk-tools` clone @ HEAD `5071328` (« updating ») :
  `README.md`, `build.py` (l. 110 `ANDROID_PLATFORM=android-{api}`,
  l. 147 `--api default=30 "min api is 30"`), `LICENSE.txt` (Apache-2.0)
- `AndroidIDEOfficial/platform-tools` @ `c000942` : `Dockerfile`
  (ubuntu:latest + NDK r26-rc1), `build.py` (l. 150), `build-tools/*.cmake`,
  `platform-tools/*.cmake`
- `jjoblab/CodeIDE` : `gradle/libs.versions.toml` (minSdk 26, targetSdk 28,
  compileSdk 37.2), `docs/ENVIRONNEMENT.md` (build-tools 36.0.0 / AGP 9.4.1,
  vérifié 2026-09-22)

## Non vérifié

- Liaison statique/dynamique réelle et ABI ELF de chaque binaire des zips
  33.0.3/34.0.3 : mesuré pour 35.0.2 (t3), la même recette s'applique —
  à re-mesurer à chaque intégration (le packaging contrôle l'ABI ELF
  systématiquement).
- Exécution réelle des binaires arm et x86_64 (l'auteur n'a testé que
  aarch64) : couverte par `smoke.yml` en CI, marquée non vérifiée jusqu'au
  premier passage.
- Build (b) complet : aucune exécution ici.

## Addendum (2026-10-06) — vérification des tags AOSP & activation de la voie (b)

Directive propriétaire : « je ne veux pas dépendre de Lzhiyong ». Mesures
complémentaires (`git ls-remote` sur android.googlesource.com) :

- `refs/tags/platform-tools-*` sur `platform/frameworks/base` : **s'arrêtent à
  35.0.2** (33.0.4, 34.0.0→34.0.5, 35.0.1, 35.0.2) — Google n'a plus publié de
  tags `platform-tools-*` ensuite : c'est la cause profonde du gel de
  Lzhiyong (août 2024), pas un abandon de l'auteur seul.
- Les versions 36.x/37.x restent atteignables par les **refs de release** :
  `android-16.0.0_r1`→`r4` (build-tools 36.x), `android-17.0.0_r1` (37.x) —
  présentes sur les 39 dépôts de `repos.json` (résolution complète, commits
  journalisés dans `catalog/upstream/aosp.yaml`).

Décision : voie (b) **activée** — ADR 0012 (amont `aosp`, recette vendue dans
`build/native/`, image Docker épinglée, NDK r27c, pins par commit). Les
versions 33–35 restent sur la voie (a) (octets immuables déjà publiés).
