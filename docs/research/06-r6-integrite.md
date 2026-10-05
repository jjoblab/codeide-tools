# R6 — Intégrité : SHA-256, signature du manifeste, attestation de provenance

- Date : 2026-10-05 (UTC)
- Statut : décidé (voir ADR 0007)

## Question

SHA-256 seul, ou aussi signature du manifeste (minisign/cosign) et
attestation de provenance GitHub (`actions/attest-build-provenance`) ?

## Méthode

Lecture de la documentation des actions et des mécanismes :
- `actions/attest-build-provenance` (GitHub, OIDC du runner, artifact
  attestations consultables via `gh attestation verify`, API
  `/orgs/<o>/attestations` — https://docs.github.com/en/actions/security-for-github,
  consulté le 2026-10-05) ;
- minisign/cosign : gestion de clé hors GitHub (signature + distribution
  de la clé publique aux clients).

## Résultats

| Mécanisme | Apport | Coût / risque |
|---|---|---|
| SHA-256 par archive (12.2) | intégrité archive par archive, déjà exigée par le contrat | nul |
| Signature du manifeste (minisign/cosign) | authentifie l'ÉMETTEUR du manifeste (anti-man-in-the-middle sur le manifeste lui-même) | clé à générer, stocker, migrer ; clé publique à embarquer dans l'app ; rotation à documenter ; une clé perdue complique la re-prise en main |
| `actions/attest-build-provenance` | atteste QUE les assets publiés ont été produits par CE workflow GitHub (commit, runner, horodatage) — vérifiable publiquement, sans clé à gérer | requiert GitHub ; ne protège pas le transport vers l'appareil |

Le maillon faible restant sans signature est le **manifeste** (servi par
GitHub Pages / raw.githubusercontent, TLS seul) : un tiers contrôlant le
réseau de l'appareil ne peut pas altérer les archives (SHA-256) mais
pourrait, en brisant TLS, servir un manifeste cohérent avec des archives
hostiles. TLS + HTTPS épinglés rendent l'attaque marginale pour notre
menace (dépôt public d'outils de développement, pas de chaîne de signature
de production).

## Décision

1. **SHA-256 partout** (contrat 12.2, inchangé) — c'est la garantie
   d'intégrité des archives.
2. **Attestations de provenance GitHub activées** dans `publish.yml`
   (`actions/attest-build-provenance@v2` sur les assets + le manifeste) :
   coût nul, traçabilité publique du processus de fabrication.
3. **Pas de signature du manifeste en v2** (schéma 2.0) : le coût de
   gestion de clé n'est pas justifié aujourd'hui. Le champ
   `schemaVersion` + un futur champ optionnel `signature` (ignoré par les
   clients 2.x — « champs inconnus ignorés ») laissent la porte ouverte
   sans casser les clients : toute activation future = incrément de
   `schemaVersion` + ADR dans les DEUX dépôts (règle 12).
4. Procédure de vérification manuelle documentée dans `SECURITY.md` :
   `gh attestation verify <archive> --repo jjoblab/codeide-tools` et
   comparaison des SHA-256 publiés.

## Sources

- https://docs.github.com/en/actions/security-for-github/using-artifact-attestations/using-artifact-attestations-to-establish-provenance-for-builds (2026-10-05)
- Prompt 2 § 12.7 (signature : « si R6 la retient… » — clause conditionnelle, non déclenchée).
- R5 (transport : TLS, GitHub Pages/Releases).

## Non vérifié

- Exécution réelle de `actions/attest-build-provenance` (aucun workflow
  joué ici) — activer dans `publish.yml`, vérifier au premier run.
