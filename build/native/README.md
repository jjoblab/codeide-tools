# build/native/ — pipeline de build natif depuis les sources AOSP (ADR 0012)

Construit les binaires SDK bioniques (aapt, aapt2, aidl, zipalign, dexdump,
split-select, adb, fastboot…) **depuis les sources AOSP épinglées**, sans
consommer les releases de `Lzhiyong/android-sdk-tools` (indépendance amont —
motivation : dépôt personnel figé depuis août 2024, pas de 36.x/37.x).

## Chaîne (tous les maillons épinglés)

| Maillon | Pin | Où |
|---|---|---|
| Sources AOSP (39 dépôts) | commit par dépôt | `catalog/upstream/aosp.yaml` |
| Recette de build | commit de CE dépôt | `build/native/` (vendue — `NOTICE.md`) |
| Toolchain NDK | r27c (27.2.12479018) | `Dockerfile` |
| Image de base | ubuntu:24.04 par digest | `Dockerfile` |
| Niveau d'API | `--api 30` (minimum bionic) | `build-native.sh` |

## Usage

```sh
# produit le zip amont équivalent (build-tools/ + platform-tools/ à la racine)
bash build/native/build-native.sh 36.0.0 aarch64 /tmp/android-sdk-tools-static-aarch64.zip
```

Le zip alimente ensuite `build/package.sh` (amont `aosp` — voir le catalogue),
qui fabrique les archives déterministes v2 comme pour tout composant.

## Détails

- **Cache** : `CODEIDE_NATIVE_CACHE` (défaut `build/cache/native/<version>/`)
  conserve les sources, le `protoc` hôte et les répertoires de build — reprise
  rapide entre architectures et exécutions.
- **Sortie** : `build.py` de l'amont packaging le zip `android-sdk-tools-<arch>.zip`
  (arrangement binaire identique aux zips Lzhiyong) ; `build-native.sh` le
  renomme au format `android-sdk-tools-static-<arch>.zip` attendu par le cache
  de `package.sh`.
- **Pas de pin binaire du zip** : contrairement à l'amont Lzhiyong (SHA-256 du
  zip amont), le sha du zip construit est un RÉSULTAT journalisé dans
  `provenance.json` ; les entrées épinglées sont les sources, la recette, le NDK
  et l'image.
- **Durée** : première construction ≈ 1 h/arche (sources ~2 Go + protoc hôte +
  CMake) ; reprises sur cache bien plus rapides.

## Mise au point (mise en garde de l'amont)

Le README de Lzhiyong prévient : « les patchs ne s'appliquent qu'à des tags ou
branches spécifiques » — pour un NOUVEAU tag AOSP, certains patchs peuvent
nécessiter un portage. Les échecs de build se diagnostiquent dans les journaux
CI du workflow « Fabriquer un composant ».
