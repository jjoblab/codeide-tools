# ADR 0005 — Licences et redistribution

- Statut : accepté (2026-10-05)
- Contexte : question de recherche R4 (note `docs/research/04`).

## Décision

| Composant | Source v2 | Redistribué sur nos GitHub Releases ? |
|---|---|---|
| build-tools, platform-tools (natifs Lzhiyong) | zips amont épinglés | **oui** — Apache-2.0 (AOSP), `LICENSE` + `NOTICE` livrés |
| `core-lambda-stubs.jar` (embarqué dans l'archive build-tools, exigé par la validation AGP — note 07 § 2) | extrait du zip Google build-tools de la même version, SHA-256 épinglé au catalogue | **oui** — jar AOSP Apache-2.0 (11 classes stub, jamais exécuté) ; NOTICE conservé |
| cmdline-tools (12.0/17.0) | `dl.google.com` | **non** — pointeur direct épinglé |
| plateformes (`android.jar`) | `dl.google.com` | **non** — pointeur direct épinglé |

**Aucune licence pré-acceptée n'est livrée** (12.5, confirmé par le
propriétaire le 2026-10-05) : l'app CodeIDE affiche la licence du SDK,
recueille l'acceptation explicite, puis écrit `licenses/` elle-même. Le
manifeste v2 ne contient aucun composant `licenses`.

## Justification

Clause 3.4 du « Android SDK License Agreement » (texte intégral dans
`repository2-3.xml`, 2026-10-05) : interdiction de redistribuer « the SDK
or any part of the SDK » — les zips Google (cmdline-tools, plateformes)
sont couverts, y compris « packaged APIs » (android.jar). Clause 3.5 : les
composants sous licence open source (AOSP, Apache-2.0) restent régis par
cette licence — les binaires Lzhiyong et `core-lambda-stubs.jar`.

## Point d'honnêteté sur l'existant

La release v1 `sdk` du dépôt (`cmdline-tools.tar.xz` rev 12.0
reconditionné) **est** une redistribution publiée avant cette analyse.
La règle d'immuabilité des releases (prompt § 9/14) impose de la laisser
en place pour la rétrocompatibilité v1 : elle reste référencée par le
manifeste v1 généré (les apps v1 installées continuent de fonctionner),
mais **aucune installation v2 ne la consomme**. La suppression éventuelle
de la release `sdk` appartient au propriétaire (risque juridique estimé
faible pour un dépôt personnel public ; décision non technique).

## Conséquences

- Si Google modifie un zip pointé (SHA-256 divergent), l'installation
  échoue proprement (comportement voulu, 12.2).
- `NOTICE` et `THIRD_PARTY_NOTICES` du dépôt documentent chaque
  composant redistribué (binaire AOSP, jar AOSP, provenance).
- Je ne suis pas juriste : option la plus prudente retenue pour tout
  composant Google (pointeur direct), conformément au prompt (R4).

## Références

- `docs/research/04-r4-licences-redistribution.md` (extraits de clauses,
  méthode).
- `repository2-3.xml` (2026-10-05) — licences et `uses-license`.
- Réponse du propriétaire (2026-10-05) : acceptation explicite côté app.
