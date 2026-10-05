# ADR 0008 — Validation du contrat d'environnement (12.4) sur hôte

- Statut : accepté (2026-10-05) — validation hôte ; appareil à confirmer
- Contexte : question de recherche R7 (note `docs/research/07`).

## Décision

Le contrat d'environnement 12.4 est **validé côté hôte, sans
modification** (aucune divergence constatée — règle de la section 12 : un
point invalide aurait exigé un ADR dans les deux dépôts et un incrément
de schéma, non nécessaire ici) :

1. AGP retrouve le SDK par `ANDROID_HOME` seul ; aucun
   `local.properties`, aucun `sdk.dir` — 25+ builds mesurés avec
   exactement les variables du contrat.
2. Le contenu de `build-tools/<v>/` exigé par AGP (validation
   `BuildToolInfo.isValid` de sdklib) : `aapt`, `aapt2`, `aidl`,
   `dexdump`, `split-select`, `zipalign`, `core-lambda-stubs.jar`,
   `source.properties` (révision cohérente). Sont inutiles : `lib/`,
   `lib64/`, `package.xml`, `NOTICE.txt`, `apksigner`, `d8`,
   `runtime.properties`. → l'archive v2 embarque exactement le jeu
   exigé + `NOTICE.txt` (Apache-2.0).
3. `platforms/android-N/` : le contenu du zip Google suffit (pas de
   `package.xml`).
4. `licenses/` : uniquement nécessaires à l'auto-installation d'AGP ;
   un SDK complet construit **sans** licences (avertissements seuls).
   L'app écrit les licences après acceptation (12.5) : ce n'est pas sur
   le chemin critique.
5. `platform-tools` : présence suffisante, jamais exécuté pendant un
   build ; le PATH 12.4 (incluant `platform-tools`) sert à
   l'utilisateur, pas à AGP.
6. `zipalign` n'est pas exécuté par `assembleDebug` (AGP 9.4.1) ; sa
   présence reste exigée par la validation.
7. L'override `android.aapt2FromMavenOverride` est honoré (chemin
   inexistant → échec explicite) ; le binaire `aapt2` du répertoire
   reste exigé **à l'existence** même avec override.

## Conséquences

- Aucune divergence de contrat : le prompt 1 peut appliquer 12.4 tel
  quel ; le détail (exigences de contenu, comportement licences) est
  documenté dans la note 07 pour son ADR.
- `targetSdk 28` + exécution depuis le stockage privé : **non vérifié
  ici** (pas d'appareil) — référence ADR 0045 CodeIDE + ADR 0082
  (constat aarch64 réel v0.51.0) ; à re-confirmer par les smoke tests
  de chaque côté (12.4).

## Références

- `docs/research/07-r7-contrat-environnement.md` (méthode, bissect,
  bytecode sdklib, sorties).
- `sdklib-31.13.0.jar` : `BuildToolInfo.isValid`,
  `BuildToolInfo$PathId` (tables minRevision/removalRevision).
