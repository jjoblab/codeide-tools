# ADR 0004 — cmdline-tools : révisions 12.0 et 17.0 en pointeur direct Google

- Statut : accepté (2026-10-05)
- Contexte : question de recherche R3 (note `docs/research/03`).

## Décision

1. Cataloguer **deux** révisions 100 % Java : `cmdline-tools@12.0`
   (11076708, référence éprouvée — épinglée par l'app CodeIDE v0.48.0) et
   `cmdline-tools@17.0` (12700392, dernière révision sans binaire natif,
   apporte `d8`/`r8` en plus). Toutes deux mesurées en environnement
   contrôlé (JDK 17 et 21, disposition officielle, sortie « 12.0 »/« 17.0 »
   code 0).
2. Profil `default` : `cmdline-tools@17.0` ; l'app reste libre d'exiger
   12.0 (les deux coexistent — règles de résolution 12.2).
3. `critical: false`, `requires: ["jdk>=17"]`, `arch: any`,
   `installPath: cmdline-tools/latest`.
4. **Pointeur direct** `https://dl.google.com/android/repository/…` avec
   SHA-256 épinglé (pas de miroir — ADR 0005).
5. Veille (`watch-upstream.yml`) : une révision ≥ 19 ne sera cataloguée
   que si `bin/android` est absent du zip (contrôle hérité de la garde v1
   de `package-sdk.sh`).
6. Le `verify` s'exécute depuis la racine du SDK (disposition
   `cmdline-tools/latest`) : `sdkmanager --version` exige cette
   disposition — sinon l'échec est un artefact de test (note 03, mesure 4).

## Justification

Les révisions ≥ 19 délèguent à un binaire natif `bin/android` publié Linux
x86_64 seulement — inexécutable sur téléphone aarch64 (constat appareil
CodeIDE v0.48.0, ADR 0082 du dépôt CodeIDE). La 17.0 est la dernière
révision « scripts + jars » et fonctionne avec JDK 17 et 21 (mesuré).

## Conséquences

- `sdkmanager` reste hors du chemin critique (confort/extras) — les
  plateformes et cmdline-tools s'installent depuis le manifeste.
- La cause racine des échecs `sdkmanager --version` **dans l'app**
  relève du prompt 1 (E1, 12.1) : non traitée ici.

## Références

- `docs/research/03-r3-cmdline-tools.md` (mesures complètes).
- `jjoblab/CodeIDE` @ e36692e : `EcrivainSdkAndroidCli.kt` (v0.48.0),
  ADR 0082 ; `repository2-3.xml` (révisions, 2026-10-05).
