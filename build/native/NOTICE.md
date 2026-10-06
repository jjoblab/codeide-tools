# NOTICE — recette de build natif vendue

Le répertoire `build/native/` adapte et redistribue la recette de build de
[`Lzhiyong/android-sdk-tools`](https://github.com/Lzhiyong/android-sdk-tools)
(commit amont épinglé lors du vendoring : HEAD `5071328`, vérifié 2026-10-05
dans la note de recherche R1), elle-même alignée sur celle d'
[`AndroidIDEOfficial/platform-tools`](https://github.com/AndroidIDEOfficial/platform-tools)
(@ `c000942`).

- Licence : **Apache-2.0** (`LICENSE.txt` — texte intégral de l'amont).
- Fichiers vendus à l'identique : `build.py`, `repos.json`, `CMakeLists.txt`,
  `build-tools/*.cmake`, `platform-tools/*.cmake`, `lib/*.cmake`,
  `others/*.cmake`, `patches/`, `LICENSE.txt`.
- Fichiers adaptés par ce dépôt : `get_source.py` (clonage par COMMITS épinglés
  du catalogue au lieu d'un tag global — l'original clone tous les dépôts au
  même tag ; motif : immuabilité et robustesse aux déplacements de tags amont).
- Fichiers propres à ce dépôt : `Dockerfile` (image épinglée), `build-native.sh`
  (orchestrateur), `README.md`, ce `NOTICE.md`.

Les binaires produits dérivent des sources AOSP (Apache-2.0) aux commits
épinglés dans `catalog/upstream/aosp.yaml` — pas d'exécutable amont téléchargé.
