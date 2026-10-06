# ADR 0012 — Indépendance amont : build natif depuis les sources AOSP (amont « aosp »)

- Statut : accepté (2026-10-06)
- Contexte : directive du propriétaire — « je ne veux pas dépendre de
  Lzhiyong ». ADR 0002 avait retenu (a) consommer Lzhiyong + (b) pipeline
  propre « préparé sans activer » ; `build/native/` n'avait pas été créé.
- Complète : ADR 0002 (b devient l'amont par défaut des NOUVELLES versions).

## Décision

1. **Nouvel amont `aosp`** (`catalog/upstream/aosp.yaml`) : les sources sont
   épinglées **par dépôt et par commit** (40 dépôts android.googlesource.com,
   résolus depuis le tag `android-16.0.0_r1` pour 36.0.0) — immuable, sans
   dépendance à un tiers mainteneur. Les tags `platform-tools-*` amont
   s'arrêtent à 35.0.2 (vérifié 2026-10-06) : les versions 36.x/37.x se
   pincent désormais par refs de release (`android-16.0.0_rN`, `android-17…`).
2. **Recette vendée** dans `build/native/` (Apache-2.0, attribution NOTICE) :
   `get_source.py` adapté (clonage aux commits épinglés, pas au tag global),
   `build.py`/CMake/patchs de l'amont, `Dockerfile` (ubuntu:24.04 par digest,
   NDK r27c épinglé), `build-native.sh` (orchestrateur Docker).
3. **Pas de pin binaire du zip construit** : le sha256 du zip amont est un
   résultat journalisé (provenance) ; les entrées épinglées sont sources +
   recette + NDK + image. Nos archives restent déterministes (package.sh).
4. **Surcharge d'amont par version** (`upstream: aosp` dans l'entrée de
   version du composant) : 33–35 restent lzhiyong (immuables — les octets
   publiés ne bougent jamais), 36.0.0 est aosp, l'amont par défaut reste le
   champ composant. `package.sh` résout l'amont effectif par version.
5. **Première version** : build-tools@36.0.0 (r1) — comble le gap AGP 9.x
   (minimale 36.0.0, ADR 0003 stratégie ii : « construire bionic 36.x »).
   `platform-tools@36.0.0` suivra par la même voie (le zip natif contient déjà
   les deux).

## Justification

- **Runtime déjà indépendant** : rien ne télécharge Lzhiyong à l'installation
  (releases + manifeste auto-hébergés, épinglés par SHA-256). Ce qui restait :
  la provenance (binaires construits par un tiers) et les versions futures
  (amont figé août 2024, jamais de 36.x — constat R1).
- La recette Lzhiyong ≡ AndroidIDE (R1) est Apache-2.0, publique et légère
  (58 fichiers) : la vender est licite et élimine le risque « dépôt tiers
  disparaît ». AOSP (android.googlesource.com) reste l'amont ultime — c'est
  la source de vérité de Google, pas un mainteneur personnel.
- Patchs à porter par tag (mise en garde de l'amont) : coût accepté, assumé
  par itérations CI documentées.

## Conséquences

- 33–35 : inchangés (immuabilité). 36.0.0+ : aosp par défaut pour tout
  nouveau build-tools/platform-tools ; toute nouvelle version = entrée de
  catalogue + pins aosp (une PR par version — CONTRIBUTING mis à jour).
- Durée de build ≈ 1 h/arche en première exécution (sources ~2 Go + protoc
  hôte + CMake) ; cache `build/cache/native/<version>/` (sources + protoc +
  builds) entre arches et exécutions ; le workflow cache le répertoire.
- `watch-upstream.yml` : la source à surveiller pour 37.x devient les refs
  `android-1[7-9].0.0_r*` AOSP (Google repository2-3.xml pour build-tools) —
  Lzhiyong n'est plus la contrainte de couverture.
- Si un patch échoue sur un nouveau tag : échec NET du build (jamais de repli
  silencieux) — mise au point documentée dans ce dépôt.

## Références

- `build/native/` (recette vendue + README + NOTICE)
- `catalog/upstream/aosp.yaml` (39 pins commits, tag android-16.0.0_r1)
- `build/native/build-native.sh`, `Dockerfile` (digest ubuntu, NDK r27c)
- `docs/research/01-r1-origine-binaires.md` (mesures initiales ; addendum
  2026-10-06 : tags platform-tools-* ≤ 35.0.0 vérifiés sur AOSP)
- ADR 0002 (décision initiale), ADR 0003 (gap AGP 9.x — stratégie ii)
