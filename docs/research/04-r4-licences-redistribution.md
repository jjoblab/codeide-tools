# R4 — Licences et redistribution des composants

- Date : 2026-10-05 (UTC)
- Statut : décidé (voir ADR 0005)

## Question

Peut-on miroiter sur GitHub Releases : (1) les binaires build-tools /
platform-tools ; (2) les cmdline-tools de Google ; (3) les plateformes
(`android.jar`) ? Faut-il livrer des licences pré-acceptées ?

## Méthode (commandes exactes)

```sh
# Texte intégral des licences du dépôt Google (16 962 et 17 251 caractères)
curl -fsSL https://dl.google.com/android/repository/repository2-3.xml
python3 - <<'PY'   # extraction des éléments <license id=…>
...
PY
# Licence du dépôt amont des binaires natifs
git clone --depth 5 https://github.com/Lzhiyong/android-sdk-tools.git
head -5 LICENSE.txt   # Apache-2.0, 177 lignes
```

## Résultats

### Texte du « Android SDK License Agreement » (extrait, repository2-3.xml, 2026-10-05)

> **3.4** You may not use the SDK for any purpose not expressly permitted by
> the License Agreement. Except to the extent required by applicable third
> party licenses, you may not **copy** (except for backup purposes), **modify,
> adapt, redistribute**, decompile, reverse engineer, disassemble, or create
> derivative works of **the SDK or any part of the SDK**.
>
> **3.5** Use, reproduction and distribution of **components of the SDK
> licensed under an open source software license** are governed solely by the
> terms of that open source software license and not the License Agreement.

Le préambule (1.1) définit le SDK comme incluant « specifically including the
Android system files, **packaged APIs**, and Google APIs add-ons » : les
zips `platform-*.zip` (android.jar) sont des « packaged APIs », les zips
`commandlinetools-*.zip` et `build-tools_r*_linux.zip` portent
`uses-license ref="android-sdk-license"` dans le même XML (vérifié sur chaque
entrée « cmdline-tools;N.0 », « build-tools;N.N.N », « platforms;android-N »).

### Composants natifs (Lzhiyong)

Construits depuis les **sources AOSP** (recette `get_source.py` + NDK,
note de recherche 01) par un tiers ; licence du dépôt et des sources :
**Apache-2.0** (`LICENSE.txt` du dépôt amont, 177 lignes, vérifié). La clause
3.5 ci-dessus ne s'applique même pas : ces binaires ne sont pas des
« composants du SDK » distribués par Google, ce sont des œuvres dérivées des
sources AOSP sous Apache-2.0 → **redistribution autorisée** avec conservation
de la licence et attribution (NOTICE).

Fait vérifié en complément : les binaires Lzhiyong sont compilés **dans
Termux** (chemins `/data/data/com.termux/files/home/proj/…` dans les
binaires, vérifié par `strings build-tools/aapt2`), NDK r27b, liés
statistiquement, API 30 (`.note.android.ident`, `readelf -n`) — aucune
donnée propriétaire Google embarquée.

### Pré-acceptation des licences (12.5)

AndroidIDE livre `licenses/android-sdk-license` déjà rempli (prompt 2,
§ 1 bis a) : la licence est acceptée **à la place** de l'utilisateur. Le
contrat commun 12.5 (confirmé par le propriétaire le 2026-10-05) prend le
parti inverse : l'app affiche la licence, recueille l'acceptation explicite
(case à cocher, date conservée dans l'état), puis écrit `licenses/` elle-même.
Le manifeste v2 ne contient donc **aucun composant `licenses`** et aucune
archive ne livre de fichier de licence acceptée.

## Décision

| Composant | Source v2 | Redistribué sur nos GitHub Releases ? |
|---|---|---|
| build-tools, platform-tools (natifs) | zips Lzhiyong épinglés (tag + SHA-256 amont) | **Oui** (Apache-2.0, NOTICE + LICENSE livrés) |
| cmdline-tools (rev 12.0) | `https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip` | **Non** (clause 3.4) : pointeur direct, SHA-256 épinglé |
| platform (`android.jar`) | `https://dl.google.com/android/repository/platform-<N>_r<rev>.zip` | **Non** (clause 3.4) : pointeur direct, SHA-256 épinglé |

Si Google modifie un fichier pointé (checksum ne correspond plus),
l'installation échoue proprement avec un message actionnable — comportement
voulu (12.2, règles de résolution). Aucun miroir secondaire n'est ajouté
pour ces composants ; les `sources` réduites à l'URL Google ordonnée
restent conformes au schéma (tableau à un élément).

**Point d'honnêteté sur l'existant** : la release v1 `sdk` du dépôt
(`cmdline-tools.tar.xz` rev 12.0 reconditionné) **est** une redistribution
publiée avant cette analyse. Les règles du prompt (§ 9 : les releases
existantes ne sont ni supprimées ni modifiées ; § 14 : jamais modifier une
release publiée) imposent de la laisser en place pour la rétrocompatibilité
v1. Le manifeste v2 ne référence plus cet asset pour les installations v2 ;
la suppression éventuelle de la release `sdk` relève du propriétaire (risque
juridique estimé faible pour un dépôt personnel public, mais décision qui ne
nous appartient pas). Signalé dans l'ADR 0005.

## Sources

- `https://dl.google.com/android/repository/repository2-3.xml` (2026-10-05) :
  texte des licences `android-sdk-license` (clauses 1.1, 3.4, 3.5) et
  `android-sdk-preview-license`, `uses-license` de chaque composant.
- `Lzhiyong/android-sdk-tools` @ HEAD `5071328` : `LICENSE.txt` (Apache-2.0).
- Prompt 2, § 1 bis a (état vérifié d'AndroidIDE : licences pré-acceptées).
- Réponse du propriétaire du 2026-10-05 : acceptation explicite dans l'app
  (défaut 12.5 confirmé).

## Non vérifié

- Interprétation juridique : je ne suis pas juriste. La clause 3.4 a été
  lue littéralement et l'option la plus prudente retenue (pointeur direct
  épinglé), conformément au prompt.
- Sommes SHA-256 des pointeurs Google : calculées au moment de la
  génération du manifeste (téléchargement intégral vérificateur), pas
  déduites du `sha1` du XML.
