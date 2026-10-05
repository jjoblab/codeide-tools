# ADR 0010 — CLI `codeide-sdk` (POSIX sh) et shim `codeidesetup`

- Statut : accepté (2026-10-05)
- Contexte : prompt 2 § 8, § 12.6 ; réponses du propriétaire (2026-10-05 :
  CLI maintenu pour la CI et l'usage manuel).

## Décision

1. **`cli/codeide-sdk`** remplace `codeidesetup` : POSIX `sh` strict
   (le bootstrap fournit `dash` — pas de bashismes), testé shellcheck +
   bats (`tests/cli/`), messages utilisateur en français.
2. Commandes : `list`, `install <id>[@<version>]… | install --profile
   <nom>`, `remove <id>[@<version>]`, `verify [--deep]`, `doctor`,
   `env --print`, option globale `--json`. Surcharges :
   `CODEIDE_TOOLS_MANIFEST`, `CODEIDE_ARCH`, `CODEIDE_SDK_ROOT`.
3. Exigences (§ 8) : non interactif par défaut (confirmations seulement
   derrière option explicite), aucune mise à jour système implicite,
   `curl --fail --location`, **un seul téléchargement par artefact**
   (cache adressé par SHA-256, reprise `curl -C -`), vérification
   SHA-256 systématique, extraction en staging puis **déplacement
   atomique**, verrou `flock` contre les exécutions concurrentes,
   plusieurs versions de build-tools côte à côte, idempotence, codes de
   sortie documentés (`docs/CLI.md`), aucune sortie jetée, aucun
   repli silencieux (seuls les miroirs du manifeste, journalisés).
4. **`env --print`** = transcription shell exacte du contrat 12.4
   (`ProcessEnvironmentProvider` côté app) : même source de vérité que
   l'app, testée par golden vectors.
5. **Shim `scripts/codeidesetup`** : traduit les options v1 les plus
   utilisées (`-s`, `-c`, `-y`, `-L`, `-m`) vers `codeide-sdk install …`,
   affiche un avertissement de dépréciation ; supprimé à la fin de la
   transition v1 (date fixée par le propriétaire, annoncée dans le
   README).
6. Le CLI n'est **ni embarqué ni appelé** par l'app (12.6) : il sert à
   la CI (`smoke.yml`), au dépannage (`doctor` affiche la **sortie
   réelle** des commandes en échec) et à l'usage manuel.
7. Chaque option documentée a un test bats — le sens d'une option ne
   peut pas être inversé sans casser un test.

## Conséquences

- La duplication v1 (script/app) disparaît : l'équivalence passe par le
  manifeste, le format des archives et `tests/golden/`.
- `doctor` valide la JVM **par exécution**
  (`java -XshowSettings:properties -version`), héritage du diagnostic
  v0.53.0 de CodeIDE.

## Références

- Prompt 2 § 8, § 12.4, § 12.6, § 13 (critères d'acceptation CLI).
- `jjoblab/CodeIDE` @ e36692e : `EcrivainSdkAndroidCli.kt` (précédents
  de diagnostic v0.53.0).
