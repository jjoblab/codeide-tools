# codeide-tools

Outils de build Android pour **CodeIDE** (`jo.codeide`) : build-tools,
platform-tools, plateformes et command-line tools **exécutables sur un
téléphone Android** (bionic : aarch64, arm, x86_64), distribués par un
**manifeste v2** multi-versions, reproductible et vérifiable.

Ce dépôt est l'équivalent CodeIDE d'`androidide-tools` (AndroidIDE),
volontairement séparé de [`codeide-packages`](https://github.com/jjoblab/codeide-packages)
(bootstrap) : les versions du SDK et les paquets du système n'ont pas le même
cycle de vie.

## Contenu

```
catalog/                 SEULE SOURCE DE VÉRITÉ (ajouter une version = une PR ici)
  upstream/*.yaml        épinglage des amonts (aosp: commits sources, lzhiyong : zips
                        historiques 33–35, google : pointeurs + jar stub) — ADR 0012
  components/*.yaml      une définition par composant (versions, verify, statut smoke)
  compat.yaml            matrice AGP ↔ build-tools ↔ aapt2 ↔ compileSdk ↔ JDK
  profiles.yaml          profils recommandés (default, minimal, full, agp9)
schema/manifest.v2.schema.json   schéma normatif du manifeste (contrat 12.2)
build/
  package.sh             fabrication DÉTERMINISTE des archives (tar.xz reproductibles)
  gen-manifest.py        catalogue + sommes → manifeste v2 + manifeste v1 + COMPAT.md
  gen-golden.py          vecteurs de référence (régénération déterministe)
  check-elf.py           contrôle ABI ELF de chaque binaire natif
  vendor/                jar core-lambda-stubs (AOSP Apache-2.0, par version)
cli/codeide-sdk          CLI POSIX sh (remplace codeidesetup — shim conservé)
tests/golden/            vecteurs de référence partagés avec l'app CodeIDE
tests/cli/               tests bats du CLI
docs/                    recherche (R1-R7), ADR, COMPAT.md, CONTRIBUTING, SECURITY
.github/workflows/       ci, build-component, publish (smoke obligatoire), veille
```

Les archives ne sont pas versionnées dans git : elles vivent dans les
**releases** (`<id>-<version>-r<rev>` par quadruplet versionné — immuable).

## Installation (terminal de CodeIDE)

```sh
curl -fsSL https://raw.githubusercontent.com/jjoblab/codeide-tools/main/cli/codeide-sdk -o codeide-sdk
sh codeide-sdk install --profile default
```

Le CLI n'est **ni embarqué ni appelé par l'app** CodeIDE (contrat 12.6) : il
sert à la CI, au dépannage (`doctor`) et à l'usage manuel. L'app implémente la
même logique en Kotlin à partir du **même manifeste** ; l'équivalence est
garantie par `tests/golden/` (manifestes valides/invalides, archives
minuscules à sommes connues — importés par les tests de l'app).

Commandes : `list`, `install <id>[@<version>]… | install --profile <nom>`,
`remove`, `verify [--deep]`, `doctor`, `env --print`, option `--json`.
Codes de sortie et surcharges (`CODEIDE_TOOLS_MANIFEST`, `CODEIDE_ARCH`,
`CODEIDE_SDK_ROOT`) : `docs/CLI.md`.

## URL du manifeste (à embarquer par CodeIDE)

- **latest** : `https://jjoblab.github.io/codeide-tools/manifests/v2/latest.json`
- **immuable** : `…/manifests/v2/<AAAAMMJJ-HHMMSS>.json`

Servies par GitHub Pages (branche `gh-pages`, alimentée par `publish.yml`) ;
**Pages est à activer une fois** par le propriétaire (Settings → Pages →
branche `gh-pages`). Jusqu'à activation, l'app utilise sa constante
configurable pointant le faux manifeste de test conforme :
`tests/golden/manifest-test.json` (12.7).
Le manifeste v1 reste publié, régénéré, à son URL historique :
`https://raw.githubusercontent.com/jjoblab/codeide-tools/main/manifest.json`.

## Compatibilité AGP (l'essentiel — voir docs/COMPAT.md, généré)

| AGP | build-tools minimale | avec build-tools 35.0.2 bionique |
|---|---|---|
| 9.x | **36.0.0** | demande ignorée → AGP auto-installe 36 **x86_64** ; le build passe grâce à l'override `android.aapt2FromMavenOverride` (aapt2 34/35 compatibles, mesuré) |
| 8.13 | 35.0.0 | **aucune auto-installation**, aapt2 du SDK utilisée — combinaison recommandée |
| 8.0 | 33.0.1 | 33.0.3 native — mais aapt2 33 ne lit pas `android.jar` ≥ 35 |

**aapt2 33.0.3 ne lit pas les plateformes ≥ 35** (échec de link, mesuré) ;
aapt2 34.0.0/35.0.1 compilent compileSdk 36 **et** 37 via override.

## Ajouter une version (une PR, rien d'autre — critère d'acceptation)

1. `catalog/upstream/lzhiyong.yaml` (ou `google.yaml`) : pin du zip amont
   (tag + SHA-256 + taille) ;
2. `catalog/components/<id>.yaml` : entrée de version (+ statut smoke
   `pending` — **jamais `ok` sans exécution prouvée**) ;
3. PR. La CI valide le catalogue, `publish.yml` fabrique → smoke → publie,
   les manifestes sont régénérés automatiquement.

Détail pas à pas : `docs/CONTRIBUTING.md`.

## Publication d'une révision

**Actions → Publier → Run workflow** avec `id@version` (ex.
`build-tools@35.0.2,platform-tools@35.0.2`). Séquence (ADR 0009) :
build déterministe → **smoke sur bionique aarch64 (porte obligatoire)** →
release immuable + `SHA256SUMS` + `provenance.json` + attestation GitHub →
manifestes v2 (immuable + latest) **et** v1 → `main` + `gh-pages`.

Jamais d'écrasement d'asset : un quadruplet (`id`, `version`, `revision`,
`arch`) publié n'est jamais modifié — un correctif = révision `r2` (test CI :
les sha256 publiés ne bougent pas entre générations).

## Rétrocompatibilité v1 (transition)

- `manifest.json` (v1) est **généré depuis le v2** et reste à son URL
  historique — les apps v1 déjà installées continuent de fonctionner sans
  changement (parité testée par la CI : octet-identique) ;
- les releases v1 existantes (`v35.0.2`, `sdk`) et leurs URLs ne sont ni
  supprimées ni modifiées ;
- `scripts/codeidesetup` est un **shim de dépréciation** redirigeant vers
  `codeide-sdk` (options v1 les plus utilisées conservées) ;
- fin de transition (retrait du manifeste v1 et du shim) : **date à fixer par
  le propriétaire** — announcez-la dans le CHANGELOG le moment venu.

## Licences et redistribution (ADR 0005)

- build-tools / platform-tools : binaires **AOSP Apache-2.0** — depuis 36.0.0,
  construits par NOTRE pipeline depuis les sources AOSP épinglées
  (`build/native/`, ADR 0012 ; versions 33–35 : zips amont
  [Lzhiyong/android-sdk-tools](https://github.com/Lzhiyong/android-sdk-tools)
  immuables, recette Apache-2.0 vendue)
  — redistribués avec `NOTICE` ; le jar `core-lambda-stubs.jar` embarqué est
  un artefact AOSP Apache-2.0 (jamais exécuté, exigé par la validation AGP) ;
- cmdline-tools et plateformes : **pointeurs directs** `dl.google.com` avec
  SHA-256 épinglé (clause 3.4 du contrat SDK Google : pas de miroir) — si
  Google modifie un fichier, l'installation échoue proprement ;
- **aucune licence pré-acceptée n'est livrée** : l'app CodeIDE écrit
  `licenses/` après acceptation explicite de l'utilisateur (12.5).

Licence du dépôt : GPL-3.0 (voir `LICENSE` et `NOTICE`).

## Vérification d'intégrité

Chaque archive est protégée par son SHA-256 (manifeste) ; la provenance des
builds est attestée par GitHub (ADR 0007) :

```sh
gh attestation verify build-tools-35.0.2-r1-aarch64.tar.xz --repo jjoblab/codeide-tools
```

## Développement

```sh
sh scripts/ci-checks.sh          # miroir exact de la CI (shellcheck, schéma,
                                 # bats, parité v1, immuabilité, reproductibilité)
python3 build/gen-manifest.py    # régénère manifestes + COMPAT.md
bash build/package.sh <id>@<version>   # fabrique les archives (déterministe)
```

Dépendances locales : `python3` (+ `pyyaml`, `jsonschema`), `shellcheck`,
`bats`, `curl`, `unzip`, `tar`, `xz`, `jq`.
