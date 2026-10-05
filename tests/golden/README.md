# Vecteurs de référence (tests/golden/)

Partagés entre ce dépôt (tests CLI, CI) et l'app CodeIDE (prompt 1,
importés dans ses tests — contrat 12.7).

- `manifest-test.json` : **faux manifeste conforme 12.2** — cible de la
  constante configurable de l'app tant que l'URL Pages réelle n'est pas
  activée (§ 12.7). Ses composants pointent vers `archives/`.
- `manifest-valid-minimal.json` : manifeste minimal valide au schéma.
- `manifest-invalide-*.json` : 14 cas que le schéma doit REJETER
  (champ requis absent, sha256 mal formé, URL non HTTPS/relative,
  installPath `..`/absolu, arch inconnue, schemaVersion erroné, …).
- `archives/*.tar.xz` : archives minuscules aux sommes connues
  (racine = racine du SDK, contrat 12.3) ;
  `manifest-sha-errone.json` : archive réelle + somme fausse
  (l'installation doit échouer proprement).

Régénération déterministe : `python3 build/gen-golden.py`
(les octets sont stables : tar trié + mtime fixé + xz -T1).
