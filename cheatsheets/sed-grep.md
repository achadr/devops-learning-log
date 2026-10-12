# sed & grep — cheatsheet

> Jour 4 — Semaine 1. Trouver des lignes, transformer du texte.

---

## 1. La carte de la boîte à outils

Chaque outil Unix fait **une** chose. C'est ce qui rend les tuyaux possibles.

| Outil | Son unique métier | Équivalent mental |
|---|---|---|
| `touch` | créer un fichier vide | « Nouveau fichier » |
| `cat` | afficher le contenu | ouvrir pour lire |
| `grep` | **trouver** les lignes qui contiennent quelque chose | `Ctrl+F` |
| `sed` | **changer** du texte dans les lignes | `Ctrl+H` |
| `awk` | **calculer** à partir des colonnes | une formule de tableur |
| `sort` | ordonner des lignes | trier une colonne |
| `uniq -c` | compter les lignes identiques | un tableau croisé dynamique |
| `wc -l` | compter les lignes | le compteur de lignes de l'éditeur |
| `>` | écrire le résultat dans un fichier | « Enregistrer sous » |

Aucun ne sait faire le métier des autres. La puissance vient de la **combinaison**, pas de chaque outil isolé.

---

## 2. `sed` en une phrase

**C'est le « rechercher / remplacer » de l'éditeur de texte, en ligne de commande.**

```
VS Code :  Ctrl+H → chercher "replicas: 2" → remplacer par "replicas: 4" → clic
sed     :  sed -i 's/replicas: 2/replicas: 4/' deployment.yaml
```

Même opération. La seule différence : une version demande un humain, l'autre non.

Plus précisément : **`sed` transforme du texte au fil de sa lecture, ligne par ligne, sans se soucier de ce que ce texte représente.** Il travaille sur un **flux**, pas forcément un fichier :

```bash
sed 's/a/b/' fichier.txt             # depuis un fichier
echo "aaa" | sed 's/a/b/'            # depuis un tuyau
journalctl -u velocite | sed '…'     # depuis la sortie d'une commande
```

### Pourquoi pas simplement ouvrir un éditeur

| Situation | Pourquoi l'éditeur ne peut pas |
|---|---|
| un pipeline CI/CD tourne à 3h du matin | **personne** ne cliquera |
| une VM GCP en SSH | pas d'écran, pas de souris, pas de VS Code |
| 200 fichiers Terraform à modifier | 200 ouvertures contre 3 secondes |
| transformer au milieu d'un tuyau | un éditeur ne se branche pas dans un flux |

---

## 3. La substitution — 90 % des usages

```
s/motif/remplacement/drapeaux
│ │     │            │
│ │     │            └─ g = toutes les occurrences de la ligne, I = insensible à la casse
│ │     └────────────── par quoi remplacer (vide = suppression)
│ └──────────────────── quoi chercher (expression régulière)
└────────────────────── substitute
```

**Sans `g`, seule la première occurrence de chaque ligne est remplacée.** Piège numéro un.

```bash
echo "velos velos velos" | sed 's/velos/VTT/'     # → VTT velos velos
echo "velos velos velos" | sed 's/velos/VTT/g'    # → VTT VTT VTT
```

### Le séparateur est libre

N'importe quel caractère après le `s`. Indispensable pour les chemins — on évite le *syndrome du cure-dent penché* :

```bash
echo "/opt/velocite/server.js" | sed 's/\/opt\/velocite/\/srv\/app/'   # illisible
echo "/opt/velocite/server.js" | sed 's|/opt/velocite|/srv/app|'       # lisible
```

### Toujours `-E`

`-E` active les expressions régulières **étendues** — la même syntaxe qu'en JavaScript. Sans lui, `sed` utilise les regex POSIX basiques où les parenthèses et les `+` doivent être échappés : `\(...\)`, `\+`. Illisible.

---

## 4. Les groupes de capture

```bash
echo "produit/btwin-riverside-500" | sed -E 's|produit/(.*)|fiche: \1|'
```

- `( … )` capture
- `\1`, `\2`… rappellent les captures dans le remplacement
- `&` rappelle la totalité de ce qui a matché

### Ne capturer que si on doit réutiliser

Deux façons d'arriver au même genre de résultat :

```bash
# garder le début, réécrire la fin → capture nécessaire
echo "92.151.59.167" | sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+/\1.0/'
# → 92.151.59.0

# ne matcher que la fin, et la supprimer → aucune capture
echo "92.151.59.167" | sed -E 's/\.[0-9]+$//'
# → 92.151.59
```

`sed` ne réécrit **que** la portion qui a matché ; tout le reste est intact. Si on peut écrire un motif qui ne décrit que la partie à supprimer, on n'a pas besoin de groupes.

Décodage de `\.[0-9]+$` :

| Morceau | Sens |
|---|---|
| `\.` | un point **littéral** — sans `\`, `.` signifie « n'importe quel caractère » |
| `[0-9]+` | un ou plusieurs chiffres |
| `$` | fin de ligne |

---

## 5. Les adresses — à quelles lignes appliquer

Sans adresse, la commande s'applique à toutes les lignes.

```bash
sed '3d'              fichier    # supprime la ligne 3
sed '1,5d'            fichier    # supprime les lignes 1 à 5
sed '$d'              fichier    # supprime la dernière ligne
sed '/^#/d'           fichier    # supprime les lignes commençant par #
sed '/^$/d'           fichier    # supprime les lignes vides
sed -n '/500/p'       fichier    # n'affiche QUE les lignes contenant 500
sed -n '/BEGIN/,/END/p' fichier  # une plage délimitée par deux motifs
sed '2i\texte'        fichier    # insère avant la ligne 2
sed '2a\texte'        fichier    # ajoute après la ligne 2
```

### Le couple `-n` + `p`

Par défaut `sed` imprime chaque ligne après traitement. `-n` coupe cette impression automatique, `p` l'impression explicite. Donc `-n '/motif/p'` = « n'imprime rien, sauf ce qui matche » = l'équivalent de `grep motif`.

### Enchaîner des commandes

```bash
sed -e '/^#/d' -e '/^$/d' config.conf
sed '/^#/d;/^$/d'          config.conf     # le ; fonctionne aussi
```

---

## 6. `-i` — modifier en place

```bash
sed -i     's/a/b/g' fichier      # écrase, sans retour possible
sed -i.bak 's/a/b/g' fichier      # écrase ET garde fichier.bak
```

**La commande la plus dangereuse de la famille.** Pas de confirmation, pas de corbeille, pas d'annulation.

La discipline en production, sans exception :

```bash
sed -E 's/…/…/g' fichier | head -n 20      # 1. je regarde ce que ça donne
sed -i.bak -E 's/…/…/g' fichier            # 2. j'applique avec sauvegarde
diff fichier.bak fichier                   # 3. je vérifie ce qui a changé
```

---

## 7. La limite qu'il faut connaître

`sed` ne comprend **rien** à la structure de ce qu'il modifie. Un YAML, pour lui, c'est du texte avec des espaces devant.

```bash
# fragile — casse le jour où l'indentation change
sed -i 's/replicas: 2/replicas: 4/' deployment.yaml

# robuste — l'outil connaît la structure
yq -i '.spec.replicas = 4' deployment.yaml
```

**Pour un format structuré, utiliser l'outil de ce format** : `jq` (JSON), `yq` (YAML), `crudini` (INI). `sed` est pour le texte non structuré, ou pour des marqueurs placés exprès (`IMAGE_TAG`), conçus pour être uniques et donc insubstituables par erreur.

Les incidents causés par un `sed -i` sur du YAML sont une catégorie à part entière.

---

## 8. Les usages réels en DevOps

### Injecter une valeur dans un pipeline CI/CD

```bash
sed -i "s|IMAGE_TAG|${GIT_SHA}|" k8s/deployment.yaml
```

**Guillemets doubles obligatoires** : bash doit remplacer `${GIT_SHA}` avant de passer la commande à `sed`. Avec des apostrophes, `sed` recevrait littéralement `${GIT_SHA}`.

### Configurer un conteneur au démarrage

```bash
#!/usr/bin/env bash
set -euo pipefail
sed -i "s/^listen .*/listen ${PORT};/" /etc/nginx/conf.d/default.conf
exec nginx -g 'daemon off;'
```

L'image reste générique, la configuration s'adapte à l'environnement au lancement.

### Modifier un paramètre système

```bash
sudo sed -i.bak 's/^#\?PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
```

`#\?` rend le dièse optionnel : fonctionne que la ligne soit commentée ou non. C'est ce que fait le module `lineinfile` d'Ansible.

### Comparer deux configurations

```bash
sed -e '/^#/d' -e '/^$/d' config-prod.conf    > /tmp/a
sed -e '/^#/d' -e '/^$/d' config-staging.conf > /tmp/b
diff /tmp/a /tmp/b
```

Première chose à faire quand « ça marche en staging mais pas en prod ».

### Modifier en masse

```bash
find . -name '*.tf' -exec sed -i 's|europe-west1|europe-west9|g' {} +
```

### Réparer les fins de ligne Windows

```bash
sed -i 's/\r$//' script.sh
```

---

## 9. LAB — anonymiser un log pour le RGPD

Une adresse IP est une **donnée personnelle**. On ne transmet pas un log brut à un prestataire. La pratique standard (Google Analytics, Matomo) masque le dernier octet : la géolocalisation approximative et l'opérateur sont conservés, l'identification d'une personne devient impossible.

```bash
sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+/\1.0/' velocite-access.log | head -n 3
sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+)\.[0-9]+/\1.0/' velocite-access.log > velocite-access-anon.log
```

L'ancre `^` garantit que seul le champ 1 est touché — une IP qui apparaîtrait dans une URL ou un referer est préservée.

### Vérifier

```bash
awk '{print $1}' velocite-access-anon.log | grep -v '\.0$' | head
```

Cherche toute IP qui **ne** finit pas par `.0`. Doit ne rien renvoyer.

**Une anonymisation qu'on n'a pas vérifiée n'est pas une anonymisation — c'est une intention.**

### Et mesurer le k-anonymat

```bash
awk '{print $1}' velocite-access.log      | sort -u | wc -l      # 405 avant
awk '{print $1}' velocite-access-anon.log | sort -u | wc -l      # 402 après

awk '{print $1}' velocite-access.log | sort -u | sed -E 's/\.[0-9]+$//' \
  | sort | uniq -c | sort -rn | head
```

405 → 402 : trois adresses seulement se sont fondues. **402 visiteurs restent individuellement distinguables.** Un pseudonyme unique par personne n'est pas un anonymat, c'est un identifiant de remplacement.

Le **k-anonymat** : une donnée est k-anonyme si chaque enregistrement est indistinguable de k−1 autres. Ici k = 1 presque partout.

**On ne déclare pas un jeu de données anonymisé sans avoir mesuré la taille des groupes obtenus.** C'est ce que demande la CNIL, et ce qui manque à la plupart des pipelines « anonymisés » en production.

Et masquer l'octet ne suffit pas : le log conserve l'**user-agent**, assez discriminant pour permettre un recoupement — c'est le principe du *fingerprinting*. Un log réellement transmissible réduirait aussi l'user-agent à sa famille (« Chrome sur Windows ») plutôt que sa version exacte.

---

## 10. `grep` — l'essentiel

```bash
grep motif          fichier
grep -i motif       fichier    # insensible à la casse
grep -v motif       fichier    # les lignes qui NE contiennent PAS
grep -c motif       fichier    # compte les lignes correspondantes
grep -n motif       fichier    # avec les numéros de ligne
grep -r motif       dossier/   # récursif
grep -l motif       *.log      # juste les noms de fichiers concernés
grep -q motif       fichier    # silencieux, ne renvoie qu'un code — pour les if
grep -E 'a|b'       fichier    # regex étendues
grep -F 'texte'     fichier    # chaîne littérale, aucune regex
grep -A3 -B1 motif  fichier    # 3 lignes après, 1 avant
```

### Les codes de retour

| Code | Sens |
|---|---|
| `0` | au moins une correspondance |
| `1` | **aucune correspondance** — ce n'est pas une erreur |
| `2` | vraie erreur (fichier introuvable, regex invalide) |

Le `1` tue un script sous `set -e`. Voir `bash-robuste.md` §3.

### Le point est un métacaractère

```bash
grep "45.227.253.109"      fichier    # accepte aussi 45X227Y253Z109
grep -F "45.227.253.109"   fichier    # chaîne littérale
grep "^45\.227\.253\.109 " fichier    # ancré, points échappés
awk '$1=="45.227.253.109"' fichier    # le plus précis : comparaison de champ
```

`grep` cherche **n'importe où dans la ligne**. Une IP peut apparaître dans une URL ou un referer et être comptée à tort. Pour un champ précis, `awk` est le bon outil.

### Les ancres

| Motif | Sens |
|---|---|
| `^abc` | la ligne commence par `abc` |
| `abc$` | la ligne finit par `abc` |
| `^abc$` | la ligne est exactement `abc` |
| `^$` | ligne vide |
| `[^:]` | un caractère qui **n'est pas** `:` |

**Les motifs non ancrés sont la première cause de faux résultats.** Exemple vécu : `:18:` matche aussi la minute 18, parce qu'un horodatage `[11/Oct/2026:19:18:42` contient trois paires de chiffres entourées de `:`. La parade :

```bash
'^\[[^:]+:18:'    # [^:]+ consomme la date jusqu'au premier :, donc :18: est forcément l'heure
```

---

## 11. La philosophie, et pourquoi elle revient

```bash
awk '{print $1}' access.log | sort -u | sed -E 's/\.[0-9]+$//' | sort | uniq -c
 └── extrait la colonne 1  └ dédoublonne  └ coupe l'octet     └── compte
```

Quatre outils, quatre métiers, assemblés en une phrase. Si `sed` savait aussi trier et compter, il serait aussi gros que Python et il faudrait apprendre son dialecte complet.

**Un outil, un métier, des tuyaux pour les relier.** C'est la même culture que l'architecture des conteneurs : un conteneur, un processus, un rôle, et un réseau pour les relier. Ce n'est pas une coïncidence.
