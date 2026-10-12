# awk — cheatsheet

> Jour 4 — Semaine 1. Le langage d'analyse de données en ligne de commande.

---

## 1. Le modèle mental

`awk` n'est pas une commande, c'est un **langage de programmation** avec une boucle implicite qu'on n'écrit jamais.

```
exécuter le bloc BEGIN (s'il existe)

POUR CHAQUE LIGNE :
    ├── stocker la ligne entière dans  $0
    ├── la découper sur les espaces →  $1, $2, $3 …
    ├── mettre le nombre de morceaux dans  NF
    ├── incrémenter le compteur de lignes  NR
    └── POUR CHAQUE PAIRE motif/action :
            si le motif est vrai → exécuter l'action

exécuter le bloc END (s'il existe)
```

Tu n'écris que le contenu de la dernière ligne : **« à quelle condition, faire quoi ».**

**`awk` ne comprend rien à tes données.** `$9` ne signifie pas « le code HTTP » — ça signifie « le neuvième mot de la ligne ». Le sens est dans ta tête, pas dans l'outil.

---

## 2. L'anatomie d'un programme

```
awk '  motif { action }  ' fichier
```

Les deux parties sont **facultatives**, d'où quatre formes :

| Forme | Signification | Exemple |
|---|---|---|
| `motif { action }` | si vrai, faire l'action | `$9==500 {print $7}` → l'URL des erreurs 500 |
| `motif` seul | action par défaut = `{print $0}` | `$9==500` → la **ligne entière** des erreurs 500 |
| `{ action }` seul | motif par défaut = vrai | `{print $1}` → le champ 1 de **toutes** les lignes |

```bash
awk '$1=="45.227.253.109"'               fichier   # filtre, affiche les lignes
awk '$1=="45.227.253.109" {print $9}'    fichier   # filtre, extrait un champ
awk '{print $1}'                         fichier   # extrait sur toutes les lignes
```

---

## 3. Les variables automatiques

| Variable | Contenu |
|---|---|
| `$0` | la ligne entière, non découpée |
| `$1`, `$2`, … | les champs, numérotés **à partir de 1** |
| `NF` | *Number of **F**ields* — combien de champs dans **cette** ligne |
| `NR` | *Number of **R**ecords* — le numéro de la ligne courante |
| `FS` | *Field Separator* en entrée — l'espace par défaut |
| `OFS` | *Output Field Separator* — ce que met la virgule dans un `print` |
| `FILENAME` | le nom du fichier en cours |

**`NF` ≠ `NR`.** Un *record* est une ligne, un *field* est un morceau de ligne.

Dans le bloc `END`, `NR` contient le **nombre total de lignes** — c'est le dénominateur pour tous les pourcentages. Mais `NF` y contient le nombre de champs de la **dernière ligne lue**, ce qui ne sert à rien et produit des résultats absurdes mais crédibles.

`$NF` n'est pas une syntaxe spéciale : c'est `$` appliqué à la valeur de `NF`. Si la ligne a 25 champs, `$NF` est `$25`. Idem `$(NF-1)` pour l'avant-dernier.

---

## 4. Découvrir les champs d'un format inconnu

**Le premier réflexe face à un fichier qu'on ne connaît pas** — remplace la documentation et ne se trompe pas :

```bash
head -n 1 fichier | awk '{for (i=1; i<=NF; i++) print i, $i}'
```

---

## 5. `BEGIN` et `END` sont des motifs

`BEGIN` est vrai une fois avant la première ligne, `END` une fois après la dernière.

```awk
BEGIN { ... }      # préparer (en-têtes, FS, initialisations)
      { ... }      # accumuler, ligne par ligne
END   { ... }      # conclure et imprimer
```

`BEGIN` permet aussi d'exécuter awk sans fichier d'entrée :

```bash
awk 'BEGIN {printf "%s mesure %.1f m\n", "la tour Eiffel", 330.2}'
```

---

## 6. Les variables persistent

Une variable awk n'est pas réinitialisée entre les lignes : elle vit pendant toute la lecture. Et une variable jamais déclarée vaut **0** en contexte numérique, **chaîne vide** en contexte texte — donc aucune initialisation à écrire.

```bash
awk '{s += $10} END {print s}' fichier
awk '$9==500 {n++} END {print n}' fichier
```

Équivalent JavaScript :

```javascript
let s = 0;
for (const ligne of lignes) { s += Number(ligne.split(/\s+/)[9]); }
console.log(s);
```

### Le piège du zéro absent

Si aucune ligne ne matche, la variable n'est jamais créée et `print n` affiche une **ligne vide**, pas `0`.

```bash
awk '$9==999 {n++} END {print n}'     fichier   # → ligne vide
awk '$9==999 {n++} END {print n+0}'   fichier   # → 0
```

Le `+0` force le contexte numérique. Dans un script de supervision, un seuil comparé à une chaîne vide ne se déclenche jamais.

### Pas de `set -u` en awk

Un mot nu est un **nom de variable**, pas du texte.

```awk
print "soit " x          # correct
print soit x             # "soit" est une variable vide → disparaît en silence
```

Aucune option ne fait échouer awk sur une variable non initialisée. Une faute de frappe sur un nom de variable ne produit jamais d'erreur — elle produit un **résultat faux**.

---

## 7. Les tableaux associatifs

Il n'existe qu'un seul type de tableau, et ses indices sont des **chaînes**. C'est un dictionnaire, un `Map`, un objet JavaScript.

```bash
awk '{codes[$9]++} END {for (c in codes) print codes[c], c}' fichier | sort -rn
```

| Expression | Valeur |
|---|---|
| `c` | la **clé** — le code HTTP : `200`, `404` |
| `codes[c]` | la **valeur** — le nombre d'occurrences : `43554` |

C'est un `GROUP BY … COUNT()` en une ligne. Avec `+=` au lieu de `++`, c'est un `SUM()` :

```bash
awk '{octets[$1] += $10} END {for (ip in octets) print octets[ip], ip}' fichier | sort -rn
```

### Les clés naissent des données

| Énumérer ce qu'on connaît | Indexer par les données |
|---|---|
| `$9=="200" {…} $9=="404" {…}` | `codes[$9]++` |
| ce qu'on n'a pas prévu est **invisible** | tout apparaît |
| il faut modifier la commande à chaque nouveau cas | la commande ne change jamais |

C'est la différence entre une alerte qui surveille les erreurs qu'on avait imaginées, et une alerte qui surveille les erreurs. La seconde réveille la nuit où quelque chose d'inédit se produit — c'est-à-dire la nuit où il faut être réveillé.

### L'ordre de parcours n'est pas défini

`for (clé in tableau)` sort les clés dans un ordre arbitraire. **Toujours** canaliser vers `sort`. Awk agrège, `sort` classe.

### Les noms sont libres

`codes[$9]++` et `baguettes[$9]++` sont équivalents. Seuls `$0`, `$1…`, `NF`, `NR`, `FS`, `OFS`, `BEGIN`, `END`, `print`, `printf`, `for`, `if`, `while` appartiennent au langage. Ne jamais écraser une variable automatique.

---

## 8. Conditions et opérateurs

| Opérateur | Sens |
|---|---|
| `==` `!=` `<` `>` `<=` `>=` | comparaison (numérique si les deux côtés ressemblent à des nombres) |
| `&&` `\|\|` `!` | et, ou, non |
| `~` | **correspond à** une expression régulière |
| `!~` | ne correspond pas |

```bash
awk '$9 >= 500'                     fichier   # seuil
awk '$9 ~ /^5/'                     fichier   # la famille 5xx
awk '$9 ~ /^4/ && $1 != "1.2.3.4"'  fichier   # conditions combinées
awk '$1=="45.227.253.109" && $9!=404' fichier # contrôle : doit renvoyer zéro ligne
```

`$9 >= 500` exprime un seuil, `$9 ~ /^5/` exprime une famille. Sur des codes HTTP à trois chiffres, les deux donnent le même résultat.

### `if` / `else` dans une action

```awk
{ total[h]++; if ($9 ~ /^5/) erreurs[h]++ }
```

```awk
{ if (h>=18 && h<=19) { s_in += $NF; n_in++ } else { s_out += $NF; n_out++ } }
```

Le `;` sépare deux instructions dans la même action.

---

## 9. Fonctions utiles

### `substr(chaîne, départ, longueur)`

Les positions commencent à **1**.

```
 [ 1 1 / O c t / 2 0  2  6  :  1  8  :  4  2  :  1  7
 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21
```

```bash
awk '{print substr($4, 14, 2)}' fichier    # → 18 (l'heure)
```

### `split(chaîne, tableau, séparateur)`

Remplit le tableau, renvoie le nombre de morceaux.

```bash
awk '{split($4, t, ":"); print t[2]}' fichier    # → l'heure
```

Sur `[11/Oct/2026:18:42:17` avec `:` :

```
t[1] = "[11/Oct/2026"   t[2] = "18"   t[3] = "42"   t[4] = "17"
```

**Préférer `split`** : elle ne dépend pas de la capacité à compter des caractères. `substr` reste utile quand il n'y a pas de séparateur exploitable.

### Autres

| Fonction | Rôle |
|---|---|
| `length($0)` | longueur d'une chaîne |
| `toupper()` / `tolower()` | changement de casse |
| `int(x)` | troncature vers l'entier |
| `sub(/motif/, "remp")` | remplace la **première** occurrence dans `$0` |
| `gsub(/motif/, "remp")` | remplace **toutes** les occurrences |
| `index(chaîne, sous-chaîne)` | position, ou 0 |

---

## 10. `printf`

```awk
printf "%-5s %7d %6.2f%%\n", c, codes[c], codes[c]*100/NR
```

```
%  -   6   .2   f
│  │   │    │   └─ type : s=chaîne, d=entier, f=flottant, %%=un %
│  │   │    └──── précision (décimales)
│  │   └───────── largeur minimale
│  └───────────── aligner à gauche (sans lui : à droite)
└──────────────── début de marqueur
```

- la correspondance est **positionnelle** : 1ᵉʳ marqueur ↔ 1ᵉʳ argument
- les largeurs sont des **minimums**, jamais des troncatures
- dans `%6.2f`, le 6 est la largeur **totale**
- `\n` est obligatoire
- **convention** : chaînes à gauche, nombres à droite

### `print` vs `printf`

| | `print` | `printf` |
|---|---|---|
| retour à la ligne | automatique | à écrire |
| format des nombres | `OFMT`, 6 chiffres significatifs → `1.06571` | contrôlé → `1.07` |
| alignement | aucun | colonnes |
| usage | explorer | produire un rapport |

### Virgule ou juxtaposition

```awk
print a b          # concaténation directe, rien entre les deux
print a, b         # joint par OFS (un espace par défaut)
```

---

## 11. Les trois pipelines à connaître par cœur

### Le *counting idiom*

```bash
awk '{print $1}' fichier | sort | uniq -c | sort -rn | head -n 10
```

`uniq` ne détecte que les doublons **adjacents** : le `sort` qui le précède est obligatoire. `sort -rn` : `-n` trie numériquement (sans lui, « 1008 » passe avant « 97 »), `-r` inverse.

### L'agrégation par clé

```bash
awk '{t[$7]++} END {for (k in t) printf "%-30s %6d\n", k, t[k]}' fichier | sort -k2 -rn
```

### La moyenne par clé, avec garde-fou d'effectif

```bash
awk '{somme[$7] += $NF; n[$7]++}
     END {for (u in n) if (n[u] > 100) printf "%-32s %6d %8.3f\n", u, n[u], somme[u]/n[u]}' \
    fichier | sort -k3,3nr
```

**Une moyenne sur un petit effectif n'est pas une mesure, c'est du bruit.** Toujours filtrer sur le nombre d'observations.

---

## 12. `sort` — les options qui comptent

| Option | Effet |
|---|---|
| `-n` | tri numérique |
| `-r` | ordre inverse |
| `-u` | dédoublonne |
| `-k2` | clé = de la colonne 2 **jusqu'à la fin de la ligne** |
| `-k2,2` | clé = la colonne 2 **seule** — plus rigoureux |
| `-t,` | séparateur de colonnes |

Pièges :

- `sort` ignore le sens des colonnes — il trie la **première** par défaut. Chaque changement d'ordre d'affichage impose de revérifier le `-k`.
- si la clé désignée est non numérique, `-n` la lit comme 0 : toutes les lignes sont « égales » et `sort` se rabat sur une comparaison de la ligne entière. Le tri semble fonctionner alors qu'il ne trie rien.
- des heures écrites `00`…`23` se trient correctement en alphabétique. C'est pourquoi on met un zéro devant.

---

## 13. Vérifier ses résultats

**Un sous-total qui ne réconcilie pas avec un total antérieur est toujours un bug.**

Exemple vécu : `$4 ~ /:18:/` a renvoyé 1 039 erreurs là où la ventilation horaire en annonçait 1 025. Cause : `:18:` matche aussi la **minute** 18 de l'heure 19. Un horodatage `[11/Oct/2026:19:18:42` contient trois fois une paire de chiffres entourée de `:`.

```bash
# faux — motif non ancré
awk '$4 ~ /:18:/ && $9 ~ /^5/'

# juste — ancré sur ce qui précède
awk '$4 ~ /^\[[^:]+:18:/ && $9 ~ /^5/'

# juste — comparaison numérique après découpage, sans ambiguïté
awk '{split($4,t,":")} t[2]==18 && $9 ~ /^5/'
```

`[^:]+` consomme la date jusqu'au premier `:`, donc le `:18:` qui suit ne peut être que l'heure.

---

## 14. Texte brut vs log structuré

```bash
# log texte : on compte les champs, et on espère
awk '{print $9}' access.log

# log JSON : on nomme ce qu'on veut
journalctl -u velocite -o json | jq -r '.MESSAGE' | jq -r '.status'
```

Le format Nginx *combined* est **ambigu** : l'user-agent contient des espaces, donc il occupe une dizaine de champs, donc tout ce qui le suit a une position variable. Aucun outil positionnel ne peut lever cette ambiguïté — d'où `$NF`, et d'où le logging structuré.

C'est le modèle de **Cloud Logging** sur GCP : chaque entrée est un objet, interrogé par champ nommé (`severity>=ERROR AND jsonPayload.status=500`).

Pourquoi apprendre awk malgré ça : les logs legacy existent ; en astreinte on a `awk` et rien d'autre, parfois sans réseau ; et c'est à cet exercice qu'on teste la capacité à raisonner sur un flux de données en entretien.

---

## 15. L'enquête du jour, en résumé

| Question | Commande |
|---|---|
| Top 10 IP | `awk '{print $1}' f \| sort \| uniq -c \| sort -rn \| head` |
| Nombre d'IP distinctes | `awk '{print $1}' f \| sort -u \| wc -l` |
| Répartition des codes | `awk '{c[$9]++} END {for (k in c) printf "%-5s %7d %6.2f\n", k, c[k], c[k]*100/NR}' f \| sort -k2 -rn` |
| Ventilation horaire des 5xx | `awk '{split($4,t,":"); h=t[2]; req[h]++; if ($9 ~ /^5/) err[h]++} END {for (h in req) printf "%sh %6d req %5d err %6.2f%%\n", h, req[h], err[h]+0, err[h]*100/req[h]}' f \| sort` |
| Temps moyen par URL | `awk '{s[$7]+=$NF; n[$7]++} END {for (u in n) if (n[u]>100) print u, n[u], s[u]/n[u]}' f \| sort -k3,3nr` |
| IP à plus de 100 erreurs 4xx | `awk '$9 ~ /^4/ {c[$1]++} END {for (i in c) if (c[i]>100) print i, c[i]}' f \| sort -k2,2nr` |
| Volume par IP | `awk '{o[$1]+=$10} END {for (i in o) printf "%12d %s\n", o[i], i}' f \| sort -rn \| head` |
| Comparer deux fenêtres | `awk '{split($4,t,":"); h=t[2]+0; if (h>=18 && h<=19) {a+=$NF; na++} else {b+=$NF; nb++}} END {printf "pendant %.3f / hors %.3f\n", a/na, b/nb}' f` |

### Ce que l'analyse a produit

- incident 18h00–19h59, 2 187 requêtes en échec sur 8 650 — **25 % du trafic de la soirée**
- temps de réponse 0,445 s → 1,753 s, facteur **3,9**
- **ce n'est pas la charge** : 20h a traité plus de trafic (4 690 req) sans une seule erreur
- erreurs réparties proportionnellement sur toutes les URL, fichiers statiques et `/health` inclus → **ressource partagée dégradée**, pas une fonctionnalité cassée
- bords alignés sur l'heure pile → **tâche planifiée** plutôt qu'incident aléatoire
- découverte annexe : `/produit/btwin-riverside-500` répond en **3,645 s** contre 0,571 et 0,535 s pour les deux autres fiches produit, à trafic comparable — facteur 6,4 sur un gabarit identique, permanent et sans lien avec l'incident

### La démarche, qui compte plus que les commandes

On ne demande pas de trouver la cause — on n'a pas accès au serveur. On demande de **réfuter les hypothèses faciles avec les données**. « Ce n'est pas la charge, et voici la ligne du log qui le prouve » vaut plus qu'une hypothèse correcte sans preuve.

Et « les données ne permettent pas de conclure » est une réponse professionnelle. Inventer une explication plausible pour ne pas avoir à le dire est la faute.

---

## 16. Les codes 5xx, à savoir pour l'examen

| Code | Signification | Émis par | Où regarder |
|---|---|---|---|
| **500** | erreur interne, l'application a planté sur la requête | l'application | les logs applicatifs |
| **502** | *Bad Gateway* : le proxy a joint l'application mais a reçu une réponse invalide | le proxy, à propos de l'app | l'application est-elle vivante ? |
| **503** | *Service Unavailable* : le proxy n'a pas pu joindre l'application | le proxy | l'application est-elle vivante ? |

**500 = regarde les logs de l'application. 502/503 = regarde si l'application est vivante.**

L'enchaînement classique de l'épuisement d'un pool de connexions : la base ralentit → les requêtes s'empilent → le pool se remplit → l'application cesse de répondre → le proxy renvoie du 503.

### Budget d'erreur

4,35 % d'erreurs sur la journée = **95,65 % de disponibilité**. Une cible marchande courante est 99,9 %, soit 43 minutes d'indisponibilité par mois. Notion centrale de la certification Professional Cloud DevOps Engineer.
