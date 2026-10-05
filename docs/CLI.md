# CLI codeide-sdk — référence

POSIX `sh` strict (dash), non interactif par défaut, aucune mise à jour
système implicite, un seul téléchargement par artefact (cache adressé par
SHA-256, reprise `curl -C -`), vérification SHA-256 systématique, extraction
en staging puis déplacement atomique, verrou `flock`, idempotence (comparaison
d'état, jamais « si le fichier est absent »).

Le CLI n'est **ni embarqué ni appelé par l'app CodeIDE** (contrat 12.6) : il
sert à la CI (smoke tests), au dépannage et à l'usage manuel. L'équivalence
avec l'app est garantie par le manifeste, le format des archives et
`tests/golden/` — pas par du code partagé.

## Commandes

| Commande | Effet |
|---|---|
| `list` | composants disponibles (arch de l'appareil + `any`) et installés |
| `install <id>[@<version>]…` | installe les composants (version la plus récente si omise) |
| `install --profile <nom>` | installe un profil du manifeste (`default`…) |
| `remove <id>[@<version>]…` | supprime les chemins `installPath` et vide l'état |
| `verify [--deep]` | exécute le `verify` de chaque composant installé (motif + code) ; `--deep` ajoute le sha de l'état |
| `doctor` | diagnostic actionnable : outils, **JVM validée par exécution** (`java -XshowSettings:properties -version`), réseau, droits, espace, état — **sortie réelle** de toute commande en échec |
| `env --print` | transcription shell exacte du contrat d'environnement 12.4 |
| `help` / `version` | aide / semver |

## Options

| Option | Effet | Test bats |
|---|---|---|
| `--json` | sorties machine : une ligne JSON par évènement (`{"event":"…", …}`) | `list --json`, `install --json` |
| `--arch A` | force l'architecture (aarch64, arm, x86_64) | `--arch arm` |
| `--root DIR` | racine du SDK | (via CODEIDE_SDK_ROOT) |

## Variables d'environnement

| Variable | Défaut | Rôle |
|---|---|---|
| `CODEIDE_TOOLS_MANIFEST` | `https://jjoblab.github.io/codeide-tools/manifests/v2/latest.json` | URL ou chemin local du manifeste v2 |
| `CODEIDE_ARCH` | `uname -m` | architecture |
| `CODEIDE_SDK_ROOT` | `$HOME/android-sdk` | racine du SDK |
| `CODEIDE_CACHE` | `$HOME/.cache/codeide-tools` | cache des artefacts (adressé par SHA-256) |
| `CODEIDE_STATE` | `<sdk>/install-state.json` | état installé (format 12.4 : `id/version/revision/sha256`) |
| `CODEIDE_FETCH_CMD` | `curl -fSL --retry 3 -C -` | crochet de téléchargement (tests hors réseau) |

## Codes de sortie

| Code | Signification |
|---|---|
| 0 | succès |
| 1 | usage (commande/option inconnue, rien à installer) |
| 2 | manifeste : injoignable, JSON invalide, non conforme 12.2, profil inconnu |
| 3 | téléchargement (échec réseau) |
| 4 | SHA-256 invalide (archive corrompue ou manifeste mensonger) |
| 5 | extraction / déplacement / verify en échec (ou composants en échec) |
| 6 | environnement (commande requise absente, HOME indéfini) |
| 7 | verrou : une autre instance tourne (`<sdk>/.codeide-sdk.lock`) |

## Règles de résolution (contrat 12.2)

1. le canal `preview` est **ignoré** (l'app ignore preview) ;
2. pour un couple (`id`, `version`) : l'entrée de `revision` la plus haute dont
   l'arch est celle de l'appareil ou `any` ;
3. version exigée absente du manifeste → erreur « manifeste incompatible »,
   aucune autre version, aucune autre source ;
4. champs inconnus ignorés ; champ requis absent → manifeste invalide.

## Extraction (contrat 12.3)

Toutes les archives ont pour racine la racine du SDK et tous leurs chemins
sous l'`installPath` du composant : le CLI extrait en **staging** puis déplace
l'`installPath` de façon **atomique** (même système de fichiers). Les zips
externes Google (`cmdline-tools`, plateformes) ont une racine différente
(`archiveRoot`) : la racine extraite est déplacée vers l'`installPath`.
Désinstaller = supprimer l'`installPath`.

## Shim `codeidesetup` (dépréciation)

`scripts/codeidesetup` redirige vers `codeide-sdk` avec un avertissement.
Options v1 conservées : `-s VER` (→ install build-tools@VER + platform-tools@VER),
`-c` (+ cmdline-tools), `-L` (list), `-m URL` (manifeste), `-a ARCH`,
`-i DIR` (→ `--root DIR/android-sdk`), `-y` (ignoré : non interactif par
défaut). `-j/-g/-o` avertissent : le JDK vient du gestionnaire de paquets,
git/openssh ne sont pas des composants du manifeste. Retrait à la fin de la
transition v1 (date fixée par le propriétaire, README).
