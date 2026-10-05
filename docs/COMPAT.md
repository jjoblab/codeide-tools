# Matrice de compatibilité AGP ↔ build-tools ↔ aapt2 ↔ compileSdk ↔ JDK

Document **généré** depuis `catalog/compat.yaml` (ne pas éditer à la main).
« testé » = mesuré sur hôte Linux x86_64 (note `docs/research/02`, scripts
`r2-matrice2.sh` / `r2-cellules.sh`) — l'exécution bionique sur appareil reste à
confirmer par les smoke tests. « non testé » = déduit, à confirmer.

| AGP | build-tools | aapt2 | compileSdk | JDK | Statut | Remarque |
|---|---|---|---|---|---|---|
| 9.4.1 | 36.0.0 | 36.0.0 | 37 | >=17 | non testé | défaut AGP 9.4.1 ; bionic 36.x inexistant chez Lzhiyong (ADR 0002/0003) |
| 9.4.1 | 35.0.2 | 35.0.2 | 36 | >=17 | testé (hôte) | via android.aapt2FromMavenOverride ; AGP auto-installe build-tools 36 x86_64 (63 Mio morts) sauf si 36 présent — preuve : hôte r2-matrice2 (AGP 9.4.1 x bt 35.0.1, apk OK, override aapt2) ; bionique équivalent 35.0.2 — appareil : smoke |
| 9.4.1 | 35.0.2 | 35.0.2 | 37 | >=17 | testé (hôte) | idem — compileSdk 37 (android-37.2) lisible par aapt2 35 — preuve : hôte r2-cellules (AGP 9.4.1 x bt 35.0.1 x cs 37, apk OK) |
| 9.4.1 | 34.0.3 | 34.0.3 | 36 | >=17 | testé (hôte) | aapt2 34 lit les tables 35+ ; auto-install AGP de bt 36 x86_64 en sus — preuve : hôte r2-matrice2 (AGP 9.4.1 x bt 34.0.0 équivalent, apk OK via override) |
| 9.4.1 | 33.0.3 | 33.0.3 | >=35 | >=17 | **incompatible** (testé) | INCOMPATIBLE compileSdk >= 35 — preuve : hôte : aapt2 33 ne lit pas android.jar >= 35 (LoadedArsc.cpp, note 02 découverte 2) |
| 9.0.0 | 35.0.2 | 35.0.2 | 36 | >=17 | testé (hôte) | min bt 36.0.0 constatée aussi sur 9.0.0 — preuve : hôte r2-matrice2 (AGP 9.0.0 x bt 35.0.1 équivalent) |
| 8.13.0 | 35.0.2 | 35.0.2 | 36 | >=17 | testé (hôte) | combinaison recommandée : aucune auto-installation, aapt2 du SDK utilisée — preuve : hôte r2-matrice2 (AGP 8.13.0 x bt 35.0.1 équivalent, AUCUNE auto-installation — min 35.0.0 satisfaite) |
| 8.13.0 | 34.0.3 | 34.0.3 | 35 | >=17 | testé (hôte) | bt 34 < min 35.0.0 : AGP auto-installe bt 35 en sus (demande ignorée) — preuve : hôte r2-cellules (AGP 8.13.0 x bt 34.0.0 équivalent x cs 35, apk OK) |
| 8.0.0 | 33.0.3 | 33.0.3 | 34 | >=17 | non testé | min bt 33.0.1 : 33.0.3 utilisée nativement (aucune auto-installation constatée) ; compileSdk <= 34 (aapt2 33) — plateformes <= 34 hors catalogue |
| 8.x | 35.0.2 | 35.0.2 | 36 | >=17 | non testé | AGP 8.1-8.12 : mins bt déduites (34.0.0 pour 8.3+) — à confirmer en CI |

## Lecture rapide

- AGP **9.x** (9.0/9.4 testés) : build-tools minimale **36.0.0** — une demande
  inférieure est ignorée et AGP auto-installe 36.0.0 **x86_64** (≈ 63 Mio) ;
  l'override `android.aapt2FromMavenOverride` fait fonctionner aapt2 34/35.
- AGP **8.13** : minimale 35.0.0 — `build-tools@35.0.2` satisfait sans aucune
  auto-installation (combinaison recommandée).
- **aapt2 33.0.3 ne lit pas** `android.jar` ≥ 35 (échec de link) : compileSdk
  ≤ 34 pour build-tools 33.0.3.
- Stratégies détaillées pour AGP 9.x : ADR 0003 ; mesures : note de recherche 02.
