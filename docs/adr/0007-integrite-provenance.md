# ADR 0007 — Intégrité : SHA-256 + attestations de provenance GitHub, pas de signature en v2

- Statut : accepté (2026-10-05)
- Contexte : question de recherche R6 (note `docs/research/06`).

## Décision

1. **SHA-256 partout** (contrat 12.2, inchangé) : intégrité de chaque
   archive.
2. **Attestations de provenance GitHub** activées dans `publish.yml`
   (`actions/attest-build-provenance@v2`) sur les assets et le manifeste
   publié : coût nul (OIDC du runner), vérification publique
   (`gh attestation verify …`), documentée dans `SECURITY.md`.
3. **Pas de signature du manifeste** en v2 : le coût de gestion de clé
   (génération, stockage, rotation, clé publique embarquée dans l'app,
   ADR dans les deux dépôts à chaque changement) n'est pas justifié par
   le modèle de menace (dépôt public d'outils de développement).
4. La porte reste ouverte : champ optionnel additif (ex. `signature`)
   ignoré par les clients 2.x (« champs inconnus ignorés », 12.2) ;
   toute activation = incrément de `schemaVersion` + ADR dans **les deux**
   dépôts (règle 12).

## Conséquences

- L'app vérifie les SHA-256 des archives (déjà prévu par le prompt 1) ;
  rien à embarquer côté app dans l'immédiat.
- `gh attestation verify` reste à exécuter au premier passage réel de
  `publish.yml` (non vérifié ici — aucun workflow joué).

## Références

- `docs/research/06-r6-integrite.md` (comparatif, liens documentation).
- Prompt 2 § 12.7 (signature conditionnelle).
