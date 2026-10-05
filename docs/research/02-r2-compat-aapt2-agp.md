# R2 — Compatibilité `aapt2` ↔ AGP ↔ `compileSdk` (mesures sur hôte)

- Date : 2026-10-05 (UTC)
- Statut : matrice partielle testée sur hôte (voir « Non vérifié ») — ADR 0003

## Question

Quelles versions d'`aapt2` fonctionnent avec les AGP 8.x et 9.x supportés, et
pour quels `compileSdk` ?

## Méthode (commandes exactes)

Projet Android minimal (`com.android.application`, une activité, une
ressource) compilé avec Gradle 9.7.1 (AGP 9.x) ou 8.14.3 (AGP 8.x), JDK 17
Temurin 17.0.16+8, **exactement** les variables du contrat 12.4
(`ANDROID_HOME`, `ANDROID_SDK_ROOT`, `ANDROID_USER_HOME`, `JAVA_HOME`,
`GRADLE_USER_HOME` ; aucun `local.properties`, aucun `sdkmanager`) et
l'override `android.aapt2FromMavenOverride=<SDK>/build-tools/<v>/aapt2`
posé dans `gradle.properties` du projet (mécanisme de l'app, 12.4).
Le SDK de test contenait **un seul** build-tools à la fois. Scripts :
`scripts/r2-matrice2.sh`, `scripts/r2-cellules.sh` (reproductibles).

**Limite assumée** : l'hôte est x86_64 Linux — les `aapt2` testés sont les
**équivalents Linux** de Google (mêmes versions sources) : 33.0.3, 34.0.0,
35.0.1, 36.0.0. Les binaires bioniques de Lzhiyong (33.0.3, 34.0.3, 35.0.2)
sont version-appariés : 33.0.3 identique, 34.0.3 ≈ 34.0.0, 35.0.2 ≈ 35.0.1.
L'exécution bionique sur appareil reste à confirmer par `smoke.yml`.

## Résultats

### Découverte 1 — version minimale de build-tools imposée par AGP

AGP **ignore** silencieusement un `buildToolsVersion` inférieur à son minimum
et installe/utilise sa version par défaut (nécessite `licenses/` + réseau,
via le chargeur SDK intégré d'AGP — pas `sdkmanager`) :

```
WARNING: The specified Android SDK Build Tools version (35.0.1) is ignored,
as it is below the minimum supported version (36.0.0) for Android Gradle Plugin 9.4.1.
…
Installing Android SDK Build-Tools 36 in /tmp/r7/sdk/build-tools/36.0.0
```

| AGP | build-tools minimale (constaté) | comportement si version plus basse demandée |
|---|---|---|
| 9.4.1 | **36.0.0** | ignorée, 36.0.0 auto-installée (60 Mio, x86_64) |
| 9.0.0 | **36.0.0** | idem |
| 8.13.0 | **35.0.0** | ignorée, 35.0.0 auto-installée |
| 8.0.0 | **33.0.1** | 33.0.3 utilisée nativement, aucune installation |

### Découverte 2 — aapt2 33.0.3 ne lit pas les plateformes récentes

`aapt2` 33.0.3 échoue au link de ressources contre `android.jar` 35 **et** 36
(format de table de ressources trop récent) — échec dur, reproduit avec AGP
8.0.0 et 9.4.1 :

```
ERROR: AAPT: aapt2 E … LoadedArsc.cpp:94] RES_TABLE_TYPE_TYPE entry offsets
overlap actual entry data.
aapt2 E … ApkAssets.cpp:149] Failed to load resources table in APK
'/tmp/r7/sdk/platforms/android-36/android.jar'.
error: failed to load include path /tmp/r7/sdk/platforms/android-36/android.jar.
```

### Découverte 3 — l'override aapt2 est honoré, y compris versions croisées

Via `android.aapt2FromMavenOverride`, **aapt2 34.0.0 et 35.0.1 compilent avec
AGP 9.4.1** pour `compileSdk` 36 **et** 37 (le protocole aapt2↔AGP est
compatible en descendants jusqu'à 34) ; la preuve de l'honnêteté du
mécanisme : un override vers un chemin inexistant échoue explicitement
(`Specified AAPT2 executable does not exist: …/aapt2. Must supply one of
aapt2 from maven or custom location.`).

### Matrice mesurée (hôte x86_64, `assembleDebug`)

| AGP | aapt2 fournie | compileSdk 35 | 36 | 37 (android-37.2) | auto-install AGP |
|---|---|---|---|---|---|
| 9.4.1 | 34.0.0 | — | **OK** | **OK** | build-tools 36 (demandée < min) |
| 9.4.1 | 35.0.1 | — | **OK** | **OK** | build-tools 36 (demandée < min) |
| 9.4.1 | 36.0.0 | — | **OK** | — | aucune |
| 9.0.0 | 34.0.0 / 35.0.1 | — | **OK** | **OK** | build-tools 36 |
| 8.13.0 | 34.0.0 | **OK** | **OK** | — | build-tools 35 (demandée < min) |
| 8.13.0 | 35.0.1 | — | **OK** | — | **aucune** (≥ min) |
| 8.0.0 | 33.0.3 | **ÉCHEC** (aapt2) | **ÉCHEC** (aapt2) | — | aucune |
| 9.4.1 | 33.0.3 | — | **ÉCHEC** (aapt2) | — | — |

Correspondances Lzhiyong : 33.0.3 → colonne 33.0.3 ; 34.0.3 → colonne
34.0.0 ; 35.0.2 → colonne 35.0.1 ( mêmes sources, reconstruites pour
bionic).

### Conséquences pratiques pour CodeIDE

1. **AGP 9.x (chaîne CodeIDE actuelle, 9.4.1)** : le SDK doit contenir
   `build-tools/36.0.0` (minimum imposé). Bionic 36.0.0 n'existe pas chez
   Lzhiyong → trois voies documentées (ADR 0003) : (i) accepter
   l'auto-installation AGP de build-tools 36 **x86_64** (≈ 63 Mio morts ;
   le build réussit quand même car l'override aapt2 est posé et **rien
   d'autre n'est exécuté** depuis build-tools — voir note R7, E2) ;
   (ii) construire bionic 36.x via le pipeline propre (R1-b, non vérifié) ;
   (iii) rester sur AGP 8.x avec build-tools 35 bionique.
2. **AGP 8.13 + build-tools 35.0.2 bionique** : aucune auto-installation
   (35.0.2 ≥ min 35.0.0), l'aapt2 du SDK est utilisée nativement →
   combinaison recommandée pour les projets des utilisateurs tant que
   bionic 36.x n'existe pas.
3. **build-tools 33.0.3** : utilisable seulement avec `compileSdk ≤ 34`
   (aapt2 incapable de lire les tables 35+) et AGP ≤ 8.2 — gardée au
   catalogue pour la rétrocompatibilité, marquée en conséquence dans
   `COMPAT.md`.

## Décision

`catalog/compat.yaml` encode cette matrice ; `docs/COMPAT.md` est généré
depuis le catalogue, chaque ligne marquée « testé (hôte) » avec la référence
de la cellule, ou « non testé ». Le profil `default` vise
`build-tools@35.0.2` + `platform@android-36` ; le profil `agp9` ajoute la
note de migration vers 36.x.

## Sources

- Scripts et logs : `scripts/r2-matrice2.sh`, `scripts/r2-cellules.sh`,
  `/tmp/r7/logs-matrice/*.log` (2026-10-05) — sorties citées ci-dessus.
- Gradle 9.7.1/8.14.3, AGP 8.0.0/8.13.0/9.0.0/9.4.1 résolus depuis
  `dl.google.com` (google() maven) le 2026-10-05.
- Zips Google : `build-tools_r{33.0.3,34,35.0.1,36}_linux.zip`,
  `platform-{35,36,37.2}_r*.zip` (repository2-3.xml, 2026-10-05).

## Non vérifié

- **Exécution bionique sur appareil** des aapt2 34.0.3/35.0.2 avec AGP :
  la version et le protocole sont testés via les équivalents Linux ; la
  correction de l'exécution aarch64/arm est du ressort de `smoke.yml`.
- Cellules compileSdk 33/34 (plateformes non incluses au catalogue) ;
- AGP 8.1-8.12 (min bt déduite : 34.0.0 pour 8.3+ — marqué non testé) ;
- AGP 9.1-9.3 (min supposée 36.0.0 comme 9.0/9.4 — non testé).
