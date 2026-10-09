# Diagnostic système — processus, ressources, méthode

> Fiche de révision · Jour 3 · Méthode construite et testée sur 4 pannes réelles.

---

## 1. ⭐ La méthode de diagnostic

**Le livrable de la journée.** À dérouler quand on te dit « le serveur est lent » sans autre information.

| # | Je vérifie | Commande | Seuil d'alerte | Si ça dépasse |
|---|---|---|---|---|
| 1 | **Charge** | `uptime` | > 0,7 × nombre de cœurs | → `top`, lire `%wa` |
| 2 | **Mémoire** | `free -h` | `available` < 10 % **ou** swap qui varie | → `ps --sort=-rss`, puis `journalctl -k` |
| 3 | **Espace disque** | `df -h` | > 90 % sur la partition applicative | → `du -sh /var/* \| sort -h` |
| 4 | **Inodes** | `df -i` | > 90 % | → chercher les répertoires à millions de fichiers |
| 5 | **CPU et I/O** | `top` | `wa` > 20 % | → `ps -eo stat \| grep ^D` |
| 6 | **Processus** | `ps -eo pid,user,%cpu,%mem,cmd --sort=-%cpu \| head` | un processus inconnu en tête | → identifier, décider |
| 7 | **Logs noyau** | `journalctl -k -n 50` | `Out of memory`, `I/O error` | → cause confirmée |

### Les deux principes qui ordonnent le tableau

**Du général au particulier.** On ne commence jamais par examiner un processus précis, mais par savoir **quelle ressource est saturée**.

**Du moins cher au plus cher.** `uptime`, `free` et `df` répondent en moins d'une seconde et couvrent déjà les trois ressources principales. `top` arrive après : c'est une loupe, pas un détecteur.

### Prendre sa référence avant l'incident

> **On ne peut pas reconnaître un système malade si on n'a jamais regardé un système sain.**

Une charge à 2,5 ne veut rien dire sans savoir ce que vaut la machine au repos.

```bash
nproc && uptime && free -h && df -h /
```

**Référence mesurée sur cette machine :**

| Indicateur | Au repos |
|---|---|
| Cœurs | **12** |
| Charge | `0.00 0.00 0.00` |
| Mémoire disponible | 7,1 Gi / 7,7 |
| Swap | 0 B |
| `/` | 1 % |

---

## 2. Les processus

| Attribut | Signification |
|---|---|
| **PID / PPID** | numéro du processus / de son parent |
| **UID / GID** | identité sous laquelle il tourne |
| **RSS** | mémoire **physique réellement occupée** ← la mesure utile |
| **VSZ** | mémoire **virtuelle réservée** — souvent énorme et trompeuse |

### Les états

| État | Signification |
|---|---|
| **R** | s'exécute ou attend son tour de CPU |
| **S** | attend un événement — **l'état normal** |
| **D** | **attend une I/O disque, ne répond à aucun signal, pas même SIGKILL** |
| **Z** | zombie : terminé, parent n'a pas lu son code de sortie |
| **T** | suspendu |

> ⚠️ **L'état `D` est le plus important à reconnaître.** Plusieurs processus en `D` = le **disque** est le goulot. C'est souvent l'explication d'une machine qui semble figée avec un CPU à 5 %.

Les zombies ne consomment rien — juste une entrée dans la table. Un zombie isolé est anodin ; des milliers signalent un parent qui ne nettoie pas.

---

## 3. Les signaux

| Signal | N° | Effet | Interceptable |
|---|---|---|---|
| **SIGTERM** | 15 | « termine-toi proprement » | **oui** |
| **SIGKILL** | 9 | tue immédiatement | **non** |
| **SIGINT** | 2 | Ctrl+C | oui |
| **SIGHUP** | 1 | souvent « recharge ta config » | oui |

**SIGTERM demande. SIGKILL impose.**

Avec SIGTERM, l'application ferme ses connexions, finit ses requêtes, vide ses tampons. Avec SIGKILL, le noyau la tue sans prévenir : requêtes coupées, données perdues.

> ⚠️ `kill -9` ne doit **jamais** être le premier réflexe. C'est l'équivalent de débrancher la machine.

C'est la séquence de systemd : `SIGTERM` → attente de `TimeoutStopSec` → `SIGKILL`.

> **`kill` est un nom trompeur** : la commande **envoie un signal**, elle ne tue pas forcément.

---

## 4. La charge système

```
uptime
→ load average: 5.29, 1.42, 0.47
                 1min  5min  15min
```

### Ce que ce n'est pas

**Ce n'est pas un pourcentage de CPU.**

### Ce que c'est

Le **nombre moyen de processus qui veulent s'exécuter**.

> ⚠️ **Spécificité Linux :** la charge compte aussi les processus en état **`D`**, qui attendent le disque.
>
> **Conséquence :** une charge de 15 avec un CPU à 3 % n'est pas une anomalie — c'est la signature d'un **problème d'I/O**, pas de calcul.

### L'interpréter

**Toujours rapporter au nombre de cœurs** (`nproc`).

| Charge | Sur 2 cœurs | Sur 12 cœurs |
|---|---|---|
| 1 | confortable | négligeable |
| 4 | **saturé** | confortable (33 %) |
| 12 | critique | **saturé** |
| 24 | effondré | critique |

> Le même chiffre, deux diagnostics opposés.

### La tendance compte plus que la valeur

| Lecture | Signification |
|---|---|
| `8.0 2.0 0.5` | ça **monte** — incident en cours |
| `0.5 2.0 8.0` | ça **descend** — incident passé |
| `4.0 4.0 4.0` | **stable** — régime normal |

> 🔬 **Vérifié :** après l'arrêt des processus, la série est passée de `7.16 / 8.31 / 4.94` à `0.63 / 5.11 / 4.22` puis `0.00 / 0.96 / 2.45`. La moyenne 1 min s'effondre vite, la 15 min traîne.

### Deux seuils distincts en supervision

| Type | Règle |
|---|---|
| **Absolu** | charge ≈ nproc → saturation |
| **Relatif** | écart au comportement habituel → anomalie |

Une charge de 4 sur 12 cœurs n'est pas une saturation, mais si la machine est à 0,00 d'habitude, c'est un **changement**.

---

## 5. Le CPU

```
%Cpu(s): 82.4 us, 0.0 sy, 0.0 ni, 16.4 id, 0.0 wa, 0.0 hi, 1.2 si, 0.0 st
```

| Champ | Signification |
|---|---|
| **us** | code applicatif |
| **sy** | appels au noyau |
| **id** | inactif |
| **wa** | **CPU inactif car il attend le disque** |
| **st** | **CPU volé par l'hyperviseur** (VM, cloud) |

### Les lectures qui orientent

| Observation | Diagnostic | Où creuser |
|---|---|---|
| charge haute + `us` élevé, `wa` bas | ça **calcule** | quel processus mange le CPU |
| charge haute + `wa` élevé, `us` bas | ça **attend le disque** | quel processus fait des I/O |
| `st` élevé | un **voisin** consomme le CPU physique | problème d'hébergement |

> `wa` est le champ le plus utile de `top`, et celui que presque personne ne regarde.

### La priorité

`nice` va de −20 à +19. **Plus le nombre est bas, plus la priorité est haute.** `nice -n 19` rend un processus *gentil*, donc peu prioritaire. Seul root descend sous 0.

---

## 6. La mémoire

```
          total   used   free   shared  buff/cache   available
Mem:      7.7Gi   557Mi  6.6Gi   3.5Mi   712Mi       7.1Gi
Swap:     2.0Gi      0B  2.0Gi
```

### ⚠️ La colonne à lire est `available`

**`free` ne veut rien dire sur Linux.** Le noyau utilise toute la RAM libre comme cache disque — c'est une optimisation, pas un gaspillage.

`available` = ce qu'une nouvelle application pourrait obtenir, **cache compris**, puisque le cache est libérable instantanément.

> **L'erreur classique :** « il ne reste que 1,2 Go de libre, il faut ajouter de la RAM ». Non : 5,3 Go sont disponibles.

### 🔬 La séquence observée pendant la saturation

| `available` | `buff/cache` | `Swap used` | Ce qui se passe |
|---|---|---|---|
| 2,9 Gi | 467 Mi | 0 B | consommation en cours |
| 1,1 Gi | 467 Mi | 0 B | le cache tient encore |
| **260 Mi** | 342 Mi | **780 Ki** | ← **le swap démarre** |
| 64 Mi | 150 Mi | 1,5 Mi | |
| 20 Mi | **31 Mi** | 148 Mi | ← **le cache s'effondre** |
| 4,3 Mi | 37 Mi | **959 Mi** | swap massif |

**Deux enseignements :**

1. **Le noyau sacrifie d'abord le cache** — de 467 Mi à 31 Mi. Il le rend entièrement avant de swapper.
2. **Le swap démarre quand `available` descend sous ~260 Mi**, pas avant.

### Le swap

Espace disque utilisé comme extension de la RAM. **Mille fois plus lent.**

| Observation | Signification |
|---|---|
| Swap utilisé, **stable** | pages inactives déplacées — **normal** |
| Swap qui **varie en permanence** | **thrashing** : la machine échange au lieu de travailler |

Le thrashing est une cause classique de machine figée : CPU bas, charge haute, tout rame.

---

## 7. L'OOM killer

Quand la mémoire est épuisée, le noyau tue un processus avec un SIGKILL — sans négociation.

**Le choix de la victime** dépend d'un score (`/proc/<pid>/oom_score`), basé sur la mémoire consommée.

> ⚠️ **Ce n'est pas forcément le coupable qui meurt.** Le plus gros consommateur est tué — souvent ta base de données, pas le script qui a provoqué la fuite.

**Le symptôme est déroutant :** un service **disparaît sans aucune trace dans ses propres logs**. Il n'a pas eu le temps d'écrire.

**La preuve est dans les logs du noyau :**

```bash
journalctl -k | grep -i "out of memory"
→ Out of memory: Killed process 1234 (node) total-vm:..., anon-rss:...
```

> 🔗 Dans un conteneur, Kubernetes affiche l'état **`OOMKilled`** — même mécanisme (S10).

---

## 8. Le disque — deux problèmes distincts

### L'espace (`df -h`)

Un disque plein produit `No space left on device` — **pas** `Permission denied`.

> ⚠️ **Identifier la bonne partition.** Sous WSL, `df -h` affiche `/mnt/c` et `drivers` à 95 % — c'est le disque Windows, sans rapport. La vraie partition est `/dev/sdd` sur `/`, à 1 %.
>
> Le réflexe vaut partout : **savoir quelle partition porte l'application** avant de s'alarmer.

### Les inodes (`df -i`)

**Un inode décrit un fichier** : permissions, propriétaire, dates, emplacement des données. Le **nom** vit dans le répertoire ; tout le reste dans l'inode.

**Le nombre d'inodes est fixé à la création du système de fichiers. Il ne grandit jamais.**

**Chaque fichier consomme un inode, même vide.**

> 🔬 **Vérifié :** 200 900 fichiers vides créés sur un tmpfs de 785 Mo.
> ```
> df -h  →  785M   20K  785M   1%   ← le disque est VIDE
> df -i  →  200888 200888  0  100%  ← les inodes sont PLEINS
> ```
> Les deux affirmations sont vraies en même temps. L'erreur du noyau est identique dans les deux cas : `No space left on device`.

**Où ça arrive en vrai :** serveur de mail, sessions PHP jamais purgées, cache applicatif sans rotation, `node_modules`.

### ⚠️ Le fichier supprimé mais encore ouvert

**Le symptôme : `df` et `du` se contredisent.**

```
df  →  701 Mo utilisés
du  →   20 Ko trouvés
```

**L'explication :** `rm` ne détruit pas les données, il retire le **nom** du répertoire. Les données ne sont libérées que lorsque plus personne ne référence le fichier — ni par son nom, **ni par un descripteur ouvert**.

`du` parcourt les noms → ne voit rien.
`df` interroge le système de fichiers → compte les blocs.

**Le trouver :**

```bash
sudo lsof +L1        # fichiers dont le nombre de liens est < 1
```

> 🔬 **Sortie observée :**
> ```
> COMMAND  PID  FD  SIZE/OFF   NLINK  NODE  NAME
> bash     607  3r  734003200    0     46   /run/user/1000/data.bin (deleted)
> sleep   1771  3r  734003200    0     46   /run/user/1000/data.bin (deleted)
> ```
> `NLINK = 0` : plus aucun nom ne pointe dessus. `NODE = 46` identique : c'est le **même fichier**.

> ⚠️ **Le piège du descripteur hérité.** `sleep` n'a jamais ouvert ce fichier — il l'a **hérité** de son parent `bash`. Les descripteurs ouverts se transmettent aux processus enfants.
>
> Tuer `sleep` ne libère rien. Il faut remonter au processus qui a **ouvert** le descripteur.

**Trois façons de libérer :**

| Méthode | Commande | Impact |
|---|---|---|
| Tuer le processus | `kill <pid>` | coupe le service |
| Fermer le descripteur | `exec 3<&-` | depuis le shell concerné |
| **Vider sans tuer** ⭐ | `sudo truncate -s 0 /proc/<pid>/fd/<n>` | **aucun** |

> La troisième est la réponse de production : le disque est plein, on ne peut pas couper le service, et l'espace est libéré en une seconde.
>
> 🔬 **Vérifié :** 701 Mo → 20 Ko, sans tuer un seul processus.

### Le montage en lecture seule

Quand le noyau détecte une corruption, il repasse le système de fichiers en lecture seule. Plus rien ne s'écrit, sans qu'aucune permission n'ait changé.

```
Read-only file system
```

```bash
findmnt -T /var/log     # vérifier les options de montage
```

---

## 9. Les descripteurs de fichiers

Chaque fichier ouvert, chaque socket, chaque connexion consomme un descripteur.

```bash
ulimit -n                  # limite du shell courant
cat /proc/<pid>/limits     # limites d'un processus précis
lsof -p <pid> | wc -l      # combien en utilise-t-il
```

**Le symptôme :** `Too many open files` (`EMFILE`).

**La cause habituelle :** une fuite — l'application ouvre sans fermer. Le problème apparaît après plusieurs heures, ce qui le rend difficile à reproduire en développement.

> Sous systemd, la limite se règle avec `LimitNOFILE=` dans l'unit.

---

## 10. Le réseau

```bash
ss -tulpn      # qui écoute sur quels ports
ss -s          # statistiques de connexions
```

| État | Signification |
|---|---|
| `LISTEN` | le service attend des connexions |
| `ESTABLISHED` | connexion active |
| `TIME_WAIT` | fermée récemment — normal sur un serveur chargé |
| `CLOSE_WAIT` | **l'application n'a pas fermé sa moitié** → bug applicatif |

Beaucoup de `CLOSE_WAIT` accompagne souvent une fuite de descripteurs.

---

## 11. 🔬 Les 4 pannes testées

| Panne | Signature | Révélée par | MTTD |
|---|---|---|---|
| **Saturation CPU** | charge 5,29 ↗, `us` 82 %, `wa` 0 %, 10 processus à 100 % | `uptime` → `top` | 1–2 min |
| **Saturation mémoire** | `available` 2,9 Gi → 4,3 Mi, cache effondré, swap 959 Mi | `free -h` **répété** | |
| **Fichier supprimé ouvert** | `df` 701 Mo vs `du` 20 Ko | `lsof +L1` | |
| **Inodes épuisés** | `df -h` 1 % mais `df -i` 100 % | `df -i` | |

**Ce que les quatre ont en commun :** le symptôme rapporté par l'équipe (« c'est lent », « plus de place ») ne désigne jamais la cause. Seule la méthode y conduit.

---

## 12. ⚠️ Pièges rencontrés

| Piège | Symptôme | À retenir |
|---|---|---|
| **`ps` sans `-e`** | ne liste que les processus du terminal courant | toujours `ps -eo ...` |
| **`pkill -f "while :"`** | ne tue rien | `while` est une **construction du shell**, pas une ligne de commande. Ces processus s'appellent juste `bash` |
| **Descripteur hérité** | tuer le mauvais processus ne libère rien | remonter au processus qui a **ouvert** le fichier |
| **`rm *` sur 200 000 fichiers** | `Argument list too long` | `rm -rf dossier/` ou `find . -type f -delete` |
| **`df -h` sous WSL** | `/mnt/c` à 95 % | c'est le disque Windows — identifier la vraie partition |
| **Lire `free` au lieu de `available`** | fausse alerte mémoire | le cache est libérable |

---

## 13. Mémo express

```bash
# ⭐ Les 4 premières commandes — moins d'une seconde
uptime                 # charge 1/5/15 min
free -h                # mémoire : lire "available"
df -h                  # espace disque
top                    # processus + %wa

# Référence
nproc                  # nombre de cœurs

# Processus
ps -eo pid,user,%cpu,%mem,stat,etime,cmd --sort=-%cpu | head
ps -eo pid,rss,cmd --sort=-rss | head        # par mémoire
ps -eo stat,pid,cmd | grep "^D"              # bloqués en I/O
ps -eo stat,pid,cmd | grep "^Z"              # zombies
pstree -p

# Disque
df -h                                   # espace
df -i                                   # ⭐ inodes
du -sh /var/* | sort -h | tail
sudo lsof +L1                           # ⭐ supprimés mais ouverts
sudo truncate -s 0 /proc/<pid>/fd/<n>   # ⭐ libérer sans tuer
findmnt -T /var/log                     # options de montage

# I/O
vmstat 1 5
iostat -x 1 3

# Descripteurs
ulimit -a
cat /proc/<pid>/limits
lsof -p <pid> | wc -l

# Réseau
ss -tulpn
ss -s

# Logs
journalctl -k -n 50                     # ⭐ noyau (OOM killer)
journalctl -k | grep -i "out of memory"
journalctl -p err --since today
dmesg | tail -30

# Signaux
kill -TERM <pid>       # demander
kill -KILL <pid>       # imposer — dernier recours
```

---

## 🎯 Questions d'entretien

1. *« Le serveur est lent. Décris ta démarche, étape par étape. »*
2. *« La charge est à 15 et le CPU à 3 %. Qu'est-ce que ça t'apprend ? »*
3. *« Quelle est la différence entre `free` et `available` dans `free -h` ? »*
4. *« Un service a disparu sans rien laisser dans ses logs. Que s'est-il passé ? »*
5. *« `df` dit que le disque est plein, mais `du` ne trouve rien. Explique. »*
6. *« `df -h` montre 1 % et pourtant l'application ne peut plus écrire. Pourquoi ? »*
7. *« SIGTERM ou SIGKILL : lequel d'abord, et pourquoi ? »*
8. *« Un processus est en état `D` et ne répond pas à `kill -9`. Pourquoi ? »*
9. *« Comment libérer l'espace d'un log supprimé sans redémarrer le service ? »*

---

## ✅ Auto-évaluation

- [ ] Je déroule ma méthode de diagnostic de mémoire, dans l'ordre
- [ ] J'interprète une charge en la rapportant au nombre de cœurs
- [ ] Je lis la tendance dans les trois moyennes de `uptime`
- [ ] J'explique pourquoi on lit `available` et non `free`
- [ ] Je reconnais le démarrage du swap et le sacrifice du cache
- [ ] Je distingue `%us` élevé de `%wa` élevé et je sais où creuser
- [ ] J'explique la différence entre `df -h` et `df -i`
- [ ] Je diagnostique un fichier supprimé mais ouvert avec `lsof +L1`
- [ ] Je libère l'espace sans tuer le processus
- [ ] Je sais où l'OOM killer laisse sa trace

---

## 🔗 Ce qui se poursuit

| Notion d'aujourd'hui | Où elle revient |
|---|---|
| SIGTERM et arrêt propre | `terminationGracePeriod` Kubernetes (S11) |
| OOM killer | état `OOMKilled`, `requests`/`limits` (S10) |
| Inodes, descripteurs | limites de conteneurs (S2) |
| Les 4 signaux d'or | latence, trafic, erreurs, **saturation** (S12) |
| MTTD / MTTR | post-mortem, chaos day (S13) |
| Méthode de diagnostic | gestion d'incidents SRE (S12) |




#	Je vérifie	Commande	Seuil d’alerte	Si ça dépasse
1	Charge	uptime	> 8 sur 12 cœurs	→ top, lire %wa
2	Mémoire	free -h	available < 10 % ou swap qui varie	→ ps --sort=-rss, puis journalctl -k
3	Espace disque	df -h	> 90 % sur une partition	→ du -sh /var/* | sort -h
4	Inodes	df -i	> 90 %	→ chercher les répertoires à millions de fichiers
5	CPU et I/O	top	wa > 20 %	→ ps -eo stat | grep ^D
6	Processus anormaux	ps --sort=-%cpu | head	un processus inconnu en tête	→ identifier, décider
7	Logs noyau	journalctl -k -n 50	Out of memory, I/O error	→ cause confirmée

