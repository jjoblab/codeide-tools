# Contribuer — ajouter une version en UNE PR

Le catalogue (`catalog/`) est la **seule source de vérité** : manifeste,
`COMPAT.md`, workflows et README en dérivent. Ajouter une version ne touche
qu'aux fichiers de catalogue ; tout le reste est automatique.

## 1. Épingler l'amont

### Composant natif (build-tools / platform-tools)

L'amont est [`Lzhiyong/android-sdk-tools`](https://github.com/Lzhiyong/android-sdk-tools).
Téléchargez le zip de chaque architecture visée et calculez SHA-256 + taille :

```sh
tag=36.0.0   # exemple : tag amont
for arch in aarch64 arm x86_64; do
  curl -fSL -o /tmp/static-$arch.zip \
    "https://github.com/Lzhiyong/android-sdk-tools/releases/download/$tag/android-sdk-tools-static-$arch.zip"
  sha256sum /tmp/static-$arch.zip; stat -c%s /tmp/static-$arch.zip
done
```

Ajoutez l'entrée dans `catalog/upstream/lzhiyong.yaml` (`pins`) :

```yaml
  "36.0.0":
    aarch64: { sha256: <somme>, size: <taille> }
    arm:     { sha256: <somme>, size: <taille> }
    x86_64:  { sha256: <somme>, size: <taille> }
```

Ajoutez le jar `core-lambda-stubs.jar` de la version : extrayez-le du zip
Google **de la même version** (`build-tools_r<version>_linux.zip`, champ
`root`) et vendez-le :

```sh
unzip -p build-tools_r36_linux.zip android-16/core-lambda-stubs.jar \
  > build/vendor/core-lambda-stubs/36.0.0.jar
```

Renseignez `catalog/upstream/google.yaml` (`lambda-stubs-source`) — le pin du
zip Google sert de provenance.

### Composant pointeur (cmdline-tools / platform)

Ajoutez l'entrée dans `catalog/upstream/google.yaml` (`cmdline-tools` ou
`platforms`) : URL du zip `dl.google.com` + SHA-256 (calculé après
téléchargement intégral) + taille + racine du zip.

> **cmdline-tools** : une révision ≥ 19 n'est acceptée que si `bin/android`
> est **absent** du zip (binaire natif x86_64 seulement — note de recherche
> 03). Vérifiez : `unzip -l commandlinetools-linux-*.zip | grep bin/android`.

## 2. Déclarer la version du composant

`catalog/components/<id>.yaml`, section `versions` :

```yaml
  - version: "36.0.0"
    revision: r1
    notes: "…"
```

et le **statut smoke** (section `smoke`) : laissez `pending` avec une raison —
jamais `ok` sans exécution réelle prouvée (règle § 0 du prompt : rien n'est
« supporté » sans test d'exécution). Le composant sera publié `channel:
preview` jusqu'au passage de `smoke.yml`.

## 3. Compatibilité

Ajoutez les lignes pertinentes dans `catalog/compat.yaml` (`status: untested`
par défaut ; `tested` seulement avec une cellule de mesure reproductible —
voir `docs/research/02` pour la méthode).

## 4. Valider et publier

```sh
sh scripts/ci-checks.sh          # tout doit passer localement
```

Puis la PR. Après fusion :

1. **Actions → Fabriquer un composant** (facultatif, pour tester) ;
2. **Actions → Publier** avec `id@version` : build déterministe → **smoke
   bionic aarch64 (porte obligatoire)** → release immuable + manifestes
   régénérés (v2 + v1) + `gh-pages`.

Après le smoke réel, une PR met `smoke.<version>.<arch>.status: ok` (avec la
source de preuve) : le composant bascule `stable` au prochain `gen-manifest`.

## Conventions

- **Immuabilité** : un quadruplet (`id`, `version`, `revision`, `arch`) publié
  ne change jamais — un correctif = révision `r2` + ADR si motif ;
- archives : racine = racine du SDK, tous les chemins sous l'`installPath`
  (contrat 12.3) — le packaging l'impose et le teste ;
- aucun `sdkmanager` sur le chemin critique ; aucune mise à jour système
  implicite ; aucune sortie jetée ; aucun repli silencieux ;
- scripts shell : POSIX sh pour `cli/` et le shim, bash pour `build/` ;
  `shellcheck -S warning` doit passer ;
- documentation en français ; identifiants de code cohérents avec l'existant.
