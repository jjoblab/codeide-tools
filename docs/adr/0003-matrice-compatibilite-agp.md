# ADR 0003 — Matrice de compatibilité AGP ↔ build-tools ↔ aapt2 ↔ compileSdk

- Statut : accepté (2026-10-05)
- Contexte : question de recherche R2 (note `docs/research/02`).

## Décision

1. `catalog/compat.yaml` encode la matrice mesurée (note 02) ;
   `docs/COMPAT.md` est **généré** depuis le catalogue, chaque ligne
   marquée `tested` (avec la cellule de mesure) ou `untested`.
2. Constats encodés :
   - AGP 9.x (9.0/9.4 testés) : build-tools minimale **36.0.0** — une
     demande inférieure est ignorée et 36.0.0 est auto-installée par AGP
     (licences + réseau requis).
   - AGP 8.13 : minimale **35.0.0** ; AGP 8.0 : **33.0.1**.
   - aapt2 33.0.3 **ne lit pas** `android.jar` ≥ 35 (échec de link) ;
     aapt2 34.0.0/35.0.1 compilent `compileSdk` 36 et 37 via l'override
     avec AGP 9.4.1.
   - `android.aapt2FromMavenOverride` est honoré y compris en versions
     croisées (AGP 9.4.1 + aapt2 34/35).
3. Profils : `default` = build-tools 35.0.2 + platform android-36
   (compatible aapt2 35.0.2 → compileSdk ≤ 37 sans auto-install avec
   AGP 8.13) ; profil `agp9` documenté avec la contrainte 36.0.0 et les
   trois stratégies ci-dessous.

## Stratégies documentées pour AGP 9.x (build-tools bionic 36.x absent)

| Stratégie | Coût | État |
|---|---|---|
| (i) Accepter l'auto-installation AGP de build-tools 36 **x86_64** (≈ 63 Mio) : le build réussit — l'override aapt2 est posé et **rien d'autre n'est exécuté** depuis build-tools (note 07 § 6 : zipalign non exécuté en `assembleDebug`) | bande passante + espace ; licences requises | testé (hôte) |
| (ii) Construire bionic 36.x (pipeline ADR 0002-b) | mise au point du pipeline | non vérifié |
| (iii) Projets sur AGP 8.13 + build-tools 35.0.2 bionique : aucune auto-installation | AGP 8.x | testé (hôte) |

L'app CodeIDE (prompt 1) choisit sa stratégie via son catalogue ;
ce dépôt fournit les faits (`COMPAT.md`).

## Conséquences

- La ligne « aapt2 33.0.3 + compileSdk ≥ 35 » est marquée incompatible
  (échec dur) ; build-tools 33.0.3 reste au catalogue pour compileSdk
  ≤ 34 (non testé ici — aucune plateforme ≤ 34 au catalogue).
- Toute nouvelle combinaison testée (CI `smoke.yml` : build AGP minimal
  avec override, si faisable) met à jour `status: tested`.

## Références

- `docs/research/02-r2-compat-aapt2-agp.md` (matrice, sorties brutes,
  scripts `r2-matrice2.sh` / `r2-cellules.sh`).
