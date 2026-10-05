# R7 — Validation du contrat d'environnement (12.4) : ce qu'AGP exige réellement

- Date : 2026-10-05 (UTC)
- Statut : testé sur hôte x86_64 (Linux) — la partie appareil reste à
  confirmer (ADR 0008)

## Question

Avec **uniquement** les variables du contrat (12.4) et l'override `aapt2`
posé dans `$GRADLE_USER_HOME/gradle.properties`, sans `local.properties` ni
`sdkmanager` : qu'exige réellement AGP dans `build-tools/<v>/` et
`platforms/android-N/` ? Les `licenses/` sont-elles nécessaires ?
L'exécution depuis le stockage privé avec `targetSdk 28` fonctionne-t-elle ?

## Méthode (commandes exactes)

Même dispositif que la note R2 (projet minimal, scripts
`scripts/r7-agp-test.sh`, `scripts/r7-bissect2.sh`, `scripts/r7-bissect3.sh`,
`scripts/r2-matrice2.sh`). Environ **25 builds** menés en supprimant un à un
des fichiers du SDK puis en reconstruisant. Le bytecode de la validation
AGP a été lu directement dans `sdklib-31.13.0.jar` (javap,
`com/android/sdklib/BuildToolInfo.class` et `BuildToolInfo$PathId.class`,
extraits du cache Gradle).

## Résultats

### 1. Le contrat d'environnement suffit

Tous les builds ont réussi avec exactement :
`ANDROID_HOME` = `ANDROID_SDK_ROOT` (le SDK), `ANDROID_USER_HOME`,
`JAVA_HOME`, `GRADLE_USER_HOME`, `HOME` et le `PATH` du JDK ; **aucun**
`local.properties`, **aucun** `sdk.dir`, **aucun** appel à `sdkmanager`.
AGP retrouve le SDK par `ANDROID_HOME` seul, comme AndroidIDE (prompt 2,
§ 1 bis b).

### 2. Contenu exigé de `build-tools/<v>/` (validation AGP = `BuildToolInfo.isValid`)

La validation lit `source.properties` (**`Pkg.Revision` doit égaler la
révision du paquet** — un 35.0.2 dans `build-tools/36.0.0` est rejeté
« inconsistent revision »), puis vérifie l'existence des fichiers dont le
`PathId` est « présent » à cette révision. Bissect sur la révision 36.0.0 :

| Fichier | Exigé (constaté) | Source du constat |
|---|---|---|
| `aapt`, `aapt2`, `aidl`, `dexdump`, `split-select`, `zipalign` | **oui** (suppression → « Installed Build Tools revision 36.0.0 is corrupted ») | bissect individuel |
| `core-lambda-stubs.jar` | **oui** (`PathId.CORE_LAMBDA_STUBS`, min 27.0.3) | bissect + bytecode |
| `source.properties` | **oui** (cohérence de révision) | bytecode `isValid` |
| `package.xml`, `NOTICE.txt`, `lib/`, `lib64/`, `apksigner`, `d8`, `runtime.properties`, `bcc_compat`, `lld`, `*-ld`, `llvm-rs-cc` | **non** (supprimés sans effet) | bissect |

`core-lambda-stubs.jar` : 11 classes stub `java.lang.invoke` (15 149 octets
pour 35.0.1, 17 103 pour 36.0.0 — contenus différents par version), jar
AOSP Apache-2.0 **jamais exécuté** par AGP 9.4.1 dans ce projet (contrôle
d'existence seul). Les zips Lzhiyong ne le contiennent pas → nos archives
l'embarquent (voir décision).

### 3. Contenu exigé de `platforms/android-N/`

Les zips Google de plateformes ne contiennent **pas** de `package.xml` —
`android.jar`, `build.prop`, `data/`, `source.properties` suffisent ; tous
les builds ont passé avec la plateforme extraite telle quelle. La
plateforme est un composant `any` (pur Java).

### 4. `licenses/` : requises seulement pour l'auto-installation d'AGP

SDK complet (build-tools + plateforme + platform-tools présents), **sans**
`licenses/` : le build **réussit** — seuls des avertissements apparaissent
lorsqu'un paquet manque :

```
Warning: License for package Android SDK Platform-Tools not accepted.
WARNING: platform-tools package is not installed. Please accept the
installation licence to continue
```

Conclusion : l'écriture des licences par l'app après acceptation (12.5)
n'est **pas** sur le chemin critique ; elle active le chargeur
d'auto-installation d'AGP (utile pour les mises à jour, dangereux sur
appareil — voir R2 découverte 1 : il télécharge des binaires x86_64).
L'app doit documenter ce levier dans son ADR côté prompt 1.

### 5. `platform-tools` : présence suffisante, jamais exécuté au build

Avec `platform-tools/` 35.0.2 (fichiers bioniques, non exécutables sur
l'hôte) présent : aucune réinstallation, build OK. Supprimé : AGP propose
de l'installer (avertissement, non bloquant constaté). Le PATH incluant
`platform-tools` (12.4) sert à l'utilisateur (`adb`), pas au build.

### 6. `zipalign` n'est pas exécuté par `assembleDebug` (AGP 9.4.1)

`chmod -x build-tools/36.0.0/zipalign` → build **réussi** (alignement
in-process). La présence du fichier reste exigée par la validation (2).

### 7. `android.aapt2FromMavenOverride`

Honoré (avertissement « experimental ») : AGP exécute le binaire pointé
même si la version diffère de celle des build-tools du SDK ; un chemin
inexistant échoue explicitement. Le binaire `aapt2` **du répertoire**
build-tools reste exigé **à l'existence** (validation) même avec override.

### 8. `targetSdk` 28 et stockage privé

Non vérifiable ici (pas d'appareil). Référence : ADR 0045 de CodeIDE
(`docs/adr/0045-targetsdk-execution-bootstrap.md` — restriction W^X
d'Android 10 sur `exec()` pour `targetSdk ≥ 29`, précédent Termux) ;
constat d'exécution réel de tout l'outillage bionique via ADR 0082 (v0.51.0,
appareil aarch64). À re-confirmer sur appareil par `smoke.yml` côté
CodeIDE (chaque côté le confirme par test, 12.4).

## Décision (reportée aux ADR 0001/0008 et au contrat des archives)

1. L'archive `build-tools` v2 contient : les 6 binaires natifs (Lzhiyong) +
   `core-lambda-stubs.jar` (jar AOSP, venu du zip Google de la même
   version, sha256 épinglé) + `NOTICE.txt` + `source.properties`
   (révision = version du composant). C'est exactement le jeu minimal
   validé ci-dessus + NOTICE (conformité Apache-2.0).
2. La disposition `platforms/android-N/` suit le zip Google tel quel
   (extraction + déplacement de la racine) ; `installPath` du composant =
   `platforms/android-N`.
3. Le contrat 12.4 est **validé côté hôte** ; l'unique divergence à
    surveiller : rien. (Aucun point du contrat n'a eu à être modifié —
   règle de la section 12 respectée.)
4. `verify` du manifeste : les commandes de vérification n'exigent que
   l'environnement 12.4 (pas de licenses).

## Sources

- Scripts cités + `/tmp/r7/full36` (dispositif), 2026-10-05.
- `sdklib-31.13.0.jar` : `BuildToolInfo.isValid` (lectures
  `source.properties` + boucle `mPaths`/`PathId.isPresentIn`),
  `BuildToolInfo$PathId` (tables minRevision/removalRevision — LLVM_RS_CC,
  BCC_COMPAT, LD_*, LLD retirés à 32.0.0 ; CORE_LAMBDA_STUBS min 27.0.3).
- `DefaultSdkLoader.getTargetInfo` (builder-9.4.1.jar) : appel d'
  `isValid` + auto-installation via `installBuildTools`.

## Non vérifié

- Exécution des binaires **sur appareil** (bionic, aarch64) : smoke tests
  à venir ; `targetSdk 28` (point 8).
- Builds **release** (signature, `zipalign` release ?), projets avec
  sources `.aidl` (l'exécution d'`aidl` n'a pas été déclenchée — un projet
  contenant des `.aidl` exécuterait le binaire du composant).
- Comportement d'AGP 8.x sur les mêmes bissects (fait pour 8.13 via la
  matrice R2 : mêmes exigences de validation constatées au premier build
  réussi de T7).
