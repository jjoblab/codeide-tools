# Sécurité

## Modèle de menace

Les artefacts de ce dépôt sont **exécutés sur les appareils des utilisateurs**
(outils de build du SDK). Les vecteurs couverts :

1. **altération d'une archive en transit** — couvert par le SHA-256 de chaque
   composant (contrat 12.2) : l'installeur (app ou CLI) refuse toute divergence,
   rien n'est extrait ;
2. **altération d'un asset publié** — couvert par l'immuabilité : un quadruplet
   publié n'est jamais modifié (jamais d'écrasement d'asset, correctif =
   révision `r2`) et un test CI vérifie qu'aucun sha256 publié ne change entre
   deux générations du manifeste ;
3. **compromission du dépôt / du runner** — couvert par les attestations de
   provenance GitHub (ADR 0007) : chaque build publié est attesté via l'OIDC
   du runner, vérifiable publiquement :
   ```sh
   gh attestation verify <archive> --repo jjoblab/codeide-tools
   ```
4. **manifeste hostile** (MITM sur son transport) — transport HTTPS ;
   le manifeste v2 valide le **schéma** (champs requis, URL HTTPS absolues,
   sha256 minuscule, installPath sans `..` ni chemin absolu) côté app, CLI et
   CI. Une signature du manifeste est explicitement différée (ADR 0007,
   champ additif prévu) : le modèle de menace actuel (dépôt public d'outils de
   développement) ne la justifie pas.

## Vérification manuelle

```sh
# sommes publiées par release
gh release view <tag> --repo jjoblab/codeide-tools
sha256sum -c SHA256SUMS
# provenance
gh attestation verify <archive> --repo jjoblab/codeide-tools
```

Les composants Google (cmdline-tools, plateformes) sont des pointeurs directs
`dl.google.com` avec SHA-256 épinglé : si Google modifie un fichier,
l'installation **échoue proprement** (jamais de repli silencieux vers une
autre source ou version).

## Signalement

- vulnérabilités des scripts/outils de ce dépôt : ouvrez une **issue
  confidentielle** (GitHub Security Advisory) sur `jjoblab/codeide-tools` ;
- binaires amont (AOSP/Lzhiyong) : signalez aux projets amont ET ouvrez une
  issue ici pour organiser la révision (`r<n+1>`) ;
- un sha256 publié qui ne correspond plus à un asset : c'est une urgence —
  ouvez une issue immédiatement (la révision suivante doit la remplacer ;
  l'asset fautif n'est jamais « réparé » en place).

## Ce que ce dépôt ne couvre pas

- Les paquets du bootstrap (Termux-like) : dépôt `codeide-packages` ;
- l'installation côté app (CodeIDE, prompt 1) : son propre SECURITY.md ;
- les licences : voir ADR 0005 (aucune licence pré-acceptée n'est livrée ;
  l'app écrit `licenses/` après acceptation explicite de l'utilisateur).
