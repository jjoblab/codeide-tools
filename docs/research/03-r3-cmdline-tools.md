# R3 — cmdline-tools : révisions exécutables sur Android, mesures en environnement contrôlé

- Date : 2026-10-05 (UTC)
- Statut : décidé (voir ADR 0004)

## Question

Existe-t-il une révision récente de cmdline-tools exécutable sur Android
(binaire natif `android` ou alternative) ? La rev 100 % Java épinglée
(12.0) fonctionne-t-elle avec JDK 17 et 21 ? Quelle(s) révision(s)
retenir pour le manifeste v2 ?

## Méthode (commandes exactes)

```sh
# Inventaire des révisions (catalogue Google)
curl -fsSL https://dl.google.com/android/repository/repository2-3.xml
# Nature des révisions candidates (12.0 et 17.0)
unzip -q commandlinetools-linux-11076708_latest.zip -d /tmp/cmdline     # rev 12.0
unzip -q commandlinetools-linux-12700392_latest.zip -d /tmp/cmdline17   # rev 17.0
ls /tmp/cmdline*/cmdline-tools/bin/          # présence de « android » ?
file -b /tmp/cmdline*/cmdline-tools/bin/android   # ELF x86_64 → refus
# Mesures en environnement contrôlé (hôte Linux x86_64, disposition officielle)
mkdir -p /tmp/sdkroot/cmdline-tools && cp -a /tmp/cmdline/cmdline-tools /tmp/sdkroot/cmdline-tools/latest
cd /tmp/sdkroot/cmdline-tools/latest
JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 PATH="$JAVA_HOME/bin:$PATH" ./bin/sdkmanager --version
# JDK 17 : Temurin 17.0.16+8 décompressé puis même commande avec ce JAVA_HOME
```

## Résultats (mesuré le 2026-10-05, JVM x86_64 — cmdline-tools est 100 % Java, indépendant de l'architecture)

### Nature des révisions

| Révision | `bin/android` | Nature | Exécutable sur Android aarch64 ? |
|---|---|---|---|
| 12.0 (11076708) | absent (vérifié) | scripts sh + jars | oui (utilisée par CodeIDE v0.48.0) |
| 17.0 (12700392) | **absent** (vérifié) | scripts sh + jars (`d8`, `r8` en plus) | oui (mesuré ici) |
| 19.0 → 23.0 (13114758 → 16111833) | présent | binaire natif | **non** : Google ne publie Linux qu'en x86_64 |

### Sorties complètes des mesures

```
$ (rev 12.0, disposition /cmdline-tools/latest, JDK 21.0.12.1) ./bin/sdkmanager --version
12.0
code=0

$ (rev 12.0, JDK 17.0.16+8 Temurin) ./bin/sdkmanager --version
12.0
code=0

$ (rev 17.0, disposition /cmdline-tools/latest, JDK 21.0.12.1) ./bin/sdkmanager --version
17.0
code=0

$ (rev 12.0, HORS disposition attendue, sans --sdk_root) ./bin/sdkmanager --version
Error: Could not determine SDK root.
Error: Either specify it explicitly with --sdk_root= or move this package into its expected location: <sdk>/cmdline-tools/latest/
code=1
```

La dernière sortie documente un piège de test : **la vérification
fonctionnelle doit se faire depuis la disposition officielle
`<sdk>/cmdline-tools/latest`** (ou avec `--sdk_root`), sinon l'échec est un
artefact de disposition, pas un défaut de la révision — le `verify` du
manifeste et le smoke test l'appliquent.

`java -XshowSettings:properties -version` (JDK 21 de l'hôte) :
`java.home = /usr/lib/jvm/java-21-openjdk-amd64`,
`java.version = 21.0.12.1`, `java.version.date = 2026-08-18`.

### Revs 19+ : pourquoi elles restent exclues

Le binaire `bin/android` est un ELF x86_64 Linux (constat de l'erreur
appareil v0.48.0 de CodeIDE : « /…/cmdline-tools/latest/bin/android: not
executable: 64-bit ELF file », dépôt CodeIDE
`core/bootstrap/src/main/kotlin/jo/codeide/core/bootstrap/EcrivainSdkAndroidCli.kt`
@ e36692e, doc de classe ; ADR 0082 ; garde du `scripts/package-sdk.sh`
du dépôt actuel, qui refuse la fabrication). La rev 19.0 (13114758)
fonctionne sur le poste de dev x86_64 (`docs/ENVIRONNEMENT.md` du dépôt
CodeIDE, vérifié 2026-09-22) : la limite est bien l'**architecture**, pas
la révision.

## Décision

1. Cataloguer **deux** révisions 100 % Java : `cmdline-tools@12.0`
   (référence éprouvée, épinglée par l'app v0.48.0) et
   `cmdline-tools@17.0` (dernière révision sans binaire natif — apport :
   `d8`/`r8` en plus). Toutes deux `critical: false` (12.2),
   `requires: ["jdk>=17"]`, pointeur direct `dl.google.com` + SHA-256
   épinglé (R4 — pas de miroir).
2. Profil « default » : `cmdline-tools@17.0` ; l'app CodeIDE reste libre
   d'exiger 12.0 tant que son épinglage v0.48.0 n'est pas retiré (les deux
   coexistent dans le manifeste).
3. `verify` : `cmdline-tools/latest/bin/sdkmanager --version` exécuté
   depuis la racine du SDK (disposition officielle), motif `^\d+\.\d+$`.
4. La veille `watch-upstream.yml` signale toute nouvelle révision : une
   rev ≥ 19 ne sera cataloguée **que si** `bin/android` est absent du zip
   (contrôle du packaging, hérité de la garde v1).

## Sources

- `repository2-3.xml` (2026-10-05) : révisions 1.0→23.0, URLs, tailles.
- Mesures ci-dessus (2026-10-05, cmdline-tools 12.0/17.0, JDK 21.0.12.1
  Debian + Temurin 17.0.16+8).
- `jjoblab/CodeIDE` @ e36692e : `EcrivainSdkAndroidCli.kt` (doc v0.48.0,
  erreur appareil), ADR 0082, `docs/ENVIRONNEMENT.md`.
- `jjoblab/codeide-tools` @ 07d75d9 : `scripts/package-sdk.sh` (garde
  anti-ELF).

## Non vérifié

- Exécution **sur appareil** (aarch64 bionic) des revs 12.0/17.0 : la JVM
  du bootstrap (openjdk-17) diffère de celles de l'hôte ; comportement à
  confirmer par `smoke.yml` (rev 12.0 déjà prouvée sur appareil par
  CodeIDE v0.48.0 → seul 17.0 reste à confirmer).
- Contenu du zip rev 23.0 non re-téléchargé ici (181 Mio) : statut
  « bin/android x86_64 » hérité des sources croisées ci-dessus.
- Révisions 13.0/16.0 non mesurées (sans apport identifié face à 12.0/17.0).
