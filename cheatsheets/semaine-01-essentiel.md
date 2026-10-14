# Semaine 1 — l'essentiel

> Ce qui doit être su sans réfléchir. Le reste se cherche.
> Les ⚠ marquent ce qui a été raté à l'auto-évaluation du 14/10 — à relire en priorité.

---

## Permissions

- `umask` : on **retire** les bits présents dans le masque — masquage, pas soustraction
  - fichiers : base 666 · répertoires : base 777 · `umask 022` → 644 et 755
- ⚠ sur un **répertoire** : `r` = lire la liste des noms · `x` = **traverser** (entrer, accéder au contenu)
  - `r` sans `x` = cul-de-sac : `ls` marche, `ls -l`, `cd` et `cat` échouent
  - un répertoire a presque toujours `x` là où il a `r` → 755, 750, jamais 644
- un seul triplet s'applique : propriétaire, sinon groupe, sinon autres
- `namei -l /chemin/complet` → les permissions de **chaque niveau** du chemin

## systemd

- ⚠ `systemctl daemon-reload` après **toute** modification d'unité — sinon `restart` relance l'ancienne config
- `systemd-analyze verify unite.service` → valider **avant** de charger
- `journalctl -u SERVICE -n 50 --no-pager` → premier réflexe en cas d'échec
- `systemctl reset-failed SERVICE` → réarmer après épuisement des tentatives
- `Wants=` + `After=` vont ensemble : `Wants` = dépendance souple, `After` = ordre
  - `Requires` = si la dépendance échoue, le service est arrêté aussi
- `StartLimitBurst` / `StartLimitIntervalSec` : fenêtre **glissante**, pas un compteur cumulatif
- `EnvironmentFile` peut être en 600 root:root : systemd le lit **en root, avant** de déposer les privilèges
- ⚠ **Isolation ≠ permissions.** `ProtectHome=true` **remonte** `/home` vide dans l'espace de noms du service
  - invisible pour `ls -l` · `sudo -u` n'applique aucun espace de noms, systemd si
  - valeurs acceptées : `true` / `read-only` / `tmpfs` / `false` — `strict` appartient à `ProtectSystem`
  - durcissement qui casse quelque chose → **déplacer ce qui est cassé**, pas retirer la protection
- `203/EXEC` = binaire introuvable ou non exécutable (souvent : un binaire de nvm sous `/home`)
- le score `systemd-analyze security` mesure la **couverture** du durcissement, pas le risque

## Tâches planifiées

- cron, les 5 champs : **minute, heure, jour du mois, mois, jour de la semaine**
- cron n'a ni `.bashrc`, ni ton `$PATH`, ni **terminal** → chemins absolus, sortie redirigée, rien d'interactif
  - reproduire ses conditions : `env -i PATH=/usr/bin:/bin bash --noprofile --norc -c '…'`
  - a-t-il seulement lancé la tâche ? `grep CRON /var/log/syslog`
- ⚠ **cron ne rattrape jamais** une exécution manquée (machine éteinte = perdue)
  - timer systemd + `Persistent=true` → rattrape au démarrage suivant

## Diagnostic

- load average : se compare à **`nproc`**, jamais dans l'absolu — 8 sur 12 cœurs = confortable
  - les 3 valeurs = moyennes à 1, 5, 15 min · décroît lentement après correction → regarder `top`
- dans `top` : `%us` = calcul · `%wa` = **disque** · `%sy` = noyau
- mémoire : on lit **`available`**, jamais `free` — `available` = `free` + cache récupérable
  - `buff/cache` diminue sous pression : le noyau récupère son cache avant de tuer
  - OOM killer : tue le plus gros score, **pas forcément le coupable** → `MemoryMax=` dans l'unité
- `df` vs `du` divergent → fichier supprimé mais encore ouvert : `lsof +L1`
- `df -h` bas mais écriture impossible → inodes épuisés : `df -i`

## Bash — l'en-tête, de mémoire

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "[ERREUR] ligne $LINENO : code $?" >&2' ERR
```

- `-E` **obligatoire** dès qu'il y a une fonction : sinon le trap n'est pas hérité
- `-e` arrête au premier échec · `-u` erreur sur variable **non définie** · `pipefail` : code du dernier élément en échec
- sans `pipefail`, un pipeline renvoie le code de sa **dernière** commande → échec silencieux
- `set -e` **jamais** dans un shell interactif — tester avec `bash -c '…'`
- `grep` renvoie **1 quand il ne trouve rien** → `|| true`, ou le mettre dans un `if`
  - `if` et `while` désactivent temporairement `errexit`

### Quoting

- `"$var"` **toujours** · `"$@"` jamais `$@` · `"${1:-}"` pour un argument optionnel
- sans guillemets : word splitting (sur `$IFS`) **et** expansion des globs
- `set -u` n'attrape que le **non défini**, pas le **vide** → `"${VAR:?message}"` sur tout chemin destructeur
- `[[ ]]` et non `[ ]` : `[` est une commande, ses arguments subissent le word splitting
- inspecter des arguments : `printf '[%s]\n'`, jamais `echo` qui les recolle

## Idempotence

- relancer doit laisser le **même état**, pas seulement ne pas planter
- `mkdir -p` · `rm -f` · `ln -sfn` (le `-n` est obligatoire, sinon `ln` descend dans le lien)
- ⚠ `install -D -m 0640 -o root -g root src dst` = `mkdir -p` + `cp` + `chmod` + `chown` en une opération idempotente
  - l'ancêtre de `ansible.builtin.copy`, mêmes paramètres
- `echo … >>` n'est **jamais** idempotent et ne lève aucune erreur → tester avec `grep -qxF` avant d'écrire
- `cmp -s a b` → 0 si identiques. **Redémarrer un service seulement si quelque chose a changé**

## Analyse de logs

- counting idiom : `awk '{print $N}' f | sort | uniq -c | sort -rn | head`
  - `uniq` ne voit que les doublons **adjacents** → le `sort` avant est obligatoire
  - `sort -rn` : sans `-n`, « 1008 » passe avant « 97 »
- awk = `motif { action }`, les deux parties facultatives
  - motif seul → affiche la ligne entière · action seule → s'applique à toutes les lignes
- `NF` = nombre de **champs** · `NR` = numéro de **ligne** · dans `END`, `NR` = total des lignes
- ⚠ `$NF` = dernier champ — indispensable quand un champ du milieu contient des espaces (user-agent)
- agrégation : `awk '{t[$1]++} END {for (k in t) print t[k], k}' | sort -rn`
  - les clés **naissent des données** : ce qu'on n'a pas prévu apparaît quand même
  - l'ordre de `for (k in t)` n'est pas défini → toujours canaliser vers `sort`
- `printf "%-5s %7d %6.2f\n"` pour produire · `print` pour explorer
- **ancrer les motifs** : `:18:` matche aussi les minutes → `^\[[^:]+:18:` ou comparaison numérique

## sed ⚠ — le point faible de la semaine

- `sed` **change** du texte · `grep` **trouve** des lignes · `awk` **calcule** sur des colonnes
- ⚠ `s/a/b/` ne remplace que la **première occurrence de chaque ligne** → `s/a/b/g` pour toutes
- `-E` systématiquement : regex étendues, même syntaxe qu'en JavaScript
- séparateur libre : `s|/opt/app|/srv/app|` pour les chemins
- captures : `( … )` puis `\1` — ne capturer que si on doit **réutiliser**
- adresses : `/^#/d` · `/^$/d` · `3,7d` · `$d` · `-n '/motif/p'` = équivalent de `grep`
- ⚠ **`sed -i` est irréversible.** Discipline en trois temps, sans exception :
  ```bash
  sed -E 's/…/…/g' f | head -n 20      # 1. je regarde
  sed -i.bak -E 's/…/…/g' f            # 2. j'applique avec sauvegarde
  diff f.bak f                         # 3. je vérifie
  ```
- format **structuré** (YAML, JSON) → `yq`, `jq`, jamais `sed`

## Codes HTTP

- **500** = l'application a planté → lire les logs applicatifs
- **502 / 503** = le proxy, à propos de l'application → vérifier si elle est vivante
- 404 servi par le proxy en ~5 ms = l'application n'a jamais été sollicitée

## Méthode

- un **sous-total qui ne réconcilie pas** avec un total antérieur est toujours un bug
- regarder 3 lignes avant d'en compter 50 000
- réfuter l'hypothèse facile **avec une donnée**, pas avec un raisonnement
- « les données ne permettent pas de conclure » est une réponse professionnelle
- ce qui échoue **bruyamment** se corrige · ce qui échoue **en silence** reste en production
