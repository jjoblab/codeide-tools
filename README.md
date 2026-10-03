# codeide-tools

Outils de build Android pour **CodeIDE** (`jo.codeide`) : build-tools, platform-tools et
command-line tools compilés pour Android, plus l'installeur `codeidesetup` qui les déploie
dans le terminal de l'IDE.

Ce dépôt est l'équivalent de `androidide-tools` pour AndroidIDE. Il est volontairement séparé
de [`codeide-packages`](https://github.com/jjoblab/codeide-packages) (fork de termux-packages) :
les paquets du bootstrap et les versions du SDK n'ont pas le même cycle de vie.

## Contenu

```
manifest.json            URLs et sommes SHA-256 de chaque archive
scripts/codeidesetup     installeur, exécuté dans le terminal de CodeIDE
scripts/package-sdk.sh   fabrique les archives et met à jour manifest.json
.github/workflows/       validation, publication des build-tools, publication des cmdline-tools
```

Les archives elles-mêmes ne sont pas versionnées dans git : elles vivent dans les **releases**
(`vX.Y.Z` pour le SDK, `sdk` pour les command-line tools).

## Installation (dans le terminal de CodeIDE)

```sh
curl -fsSL https://raw.githubusercontent.com/jjoblab/codeide-tools/main/scripts/codeidesetup -o codeidesetup
bash codeidesetup -c
```

Sans option, le script installe la version la plus récente du manifest pour l'architecture
de l'appareil, plus OpenJDK 17. Options utiles :

| Option | Effet |
| --- | --- |
| `-s 35.0.2` | version précise du SDK (défaut : la plus récente) |
| `-c` | installe aussi les command-line tools (`sdkmanager`) |
| `-j 21` | OpenJDK 21 au lieu de 17 (expérimental) |
| `-g` / `-o` | installe aussi `git` / `openssh` |
| `-y` | mode non interactif |
| `-L` | liste les versions disponibles puis quitte |
| `-i DIR` | répertoire d'installation (défaut : `$HOME`, SDK dans `DIR/android-sdk`) |

`codeidesetup -h` affiche la liste complète.

Le script :

1. installe les prérequis manquants (`curl`, `jq`, `tar`, `xz-utils`) ;
2. lit `manifest.json` et résout les URLs pour l'architecture (`aarch64`, `arm`, `x86_64`) ;
3. télécharge chaque archive, **vérifie sa somme SHA-256** et l'extrait dans `android-sdk/` ;
4. installe `openjdk-17` (ou `21`) avec le gestionnaire de paquets (`pkg`) ;
5. écrit `JAVA_HOME` et `ANDROID_SDK_ROOT` dans `$SYSROOT/etc/ide-environment.properties`
   (les autres lignes du fichier sont conservées).

Il a besoin de la variable `SYSROOT` (ou à défaut `PREFIX`) : elle est définie dans le terminal de CodeIDE.

Les plateformes (`android.jar`) ne sont pas incluses : avec `-c`, installez-les via
`sdkmanager --install "platforms;android-35"`.

## Publier une nouvelle version du SDK

### Avec GitHub Actions (recommandé, rien à compiler sur le téléphone)

1. **Actions → Publier build-tools et platform-tools → Run workflow**.
2. Saisissez la version (`35.0.2`). Le tag amont `lzhiyong/android-sdk-tools` est supposé
   identique ; sinon renseignez `source_tag`.
3. Le workflow crée la release `v35.0.2` avec 6 archives + `SHA256SUMS`, puis commite
   `manifest.json`.

Pour les command-line tools : **Actions → Publier les command-line tools**, avec l'URL
`https://dl.google.com/android/repository/commandlinetools-linux-XXXXXXX_latest.zip`.

### En local

Dépendances : `curl unzip tar xz jq sha256sum` (et `gh` pour publier).

```sh
./scripts/package-sdk.sh sdk -v 35.0.2          # génère dist/*.tar.xz et met à jour manifest.json
./scripts/package-sdk.sh sdk -v 35.0.2 -R       # idem + création de la release avec gh
./scripts/package-sdk.sh cmdline -z commandlinetools-linux-XXXXXXX_latest.zip -R
```

Si vous avez déjà téléchargé les zips amont : `-s DOSSIER` (fichiers
`android-sdk-tools-static-<arch>.zip`). Pensez ensuite à commiter et pousser `manifest.json`.

## Formats

**manifest.json** (mêmes clés que le manifest d'AndroidIDE, plus les sommes SHA-256) :

```json
{
    "android_sdk": null,
    "build_tools": { "aarch64": { "_35_0_2": "https://…/build-tools-35.0.2-aarch64.tar.xz" } },
    "cmdline_tools": "https://…/cmdline-tools.tar.xz",
    "platform_tools": { "aarch64": { "_35_0_2": "https://…/platform-tools-35.0.2-aarch64.tar.xz" } },
    "sha256": { "build-tools-35.0.2-aarch64.tar.xz": "…" }
}
```

Tant qu'aucune release n'est publiée, le manifest ne contient aucune version.

**Archives** (extraites à la racine du SDK, `$HOME/android-sdk`) :

| Archive | Contenu |
| --- | --- |
| `build-tools-X.Y.Z-<arch>.tar.xz` | `build-tools/X.Y.Z/` : `aapt`, `aapt2`, `aidl`, `dexdump`, `split-select`, `zipalign`, `source.properties` |
| `platform-tools-X.Y.Z-<arch>.tar.xz` | `platform-tools/` : `adb`, `fastboot`, `mke2fs`, `sqlite3`, etc., `source.properties` |
| `cmdline-tools.tar.xz` | `cmdline-tools/latest/` : `bin/sdkmanager`, `lib/`, etc. |

## Remarques

- **Ce dépôt doit rester public** : l'installeur télécharge le manifest et les releases sans
  authentification.
- Pour changer de dépôt (fork, test), définissez `CODEIDE_TOOLS_REPO=utilisateur/depot`
  ou passez `-m URL_DU_MANIFEST` à `codeidesetup`.

## Crédits et licence

- Binaires Android compilés pour Android par [Lzhiyong/android-sdk-tools](https://github.com/Lzhiyong/android-sdk-tools).
- Architecture inspirée de [AndroidIDEOfficial/androidide-tools](https://github.com/AndroidIDEOfficial/androidide-tools) (GPL-3.0).
- Command-line tools : Google, distribués sous leurs propres conditions.

Licence : GPL-3.0, voir [LICENSE](LICENSE).
