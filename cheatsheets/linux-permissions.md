# Linux — permissions, utilisateurs, arborescence

> Fiche de révision · Jour 1 · Tout ce qui suit a été vérifié en pratique.

---

## 1. Lire une ligne de `ls -l`

```
drwxr-xr-x  2  achraf  docker  4096  Oct 6 18:20  team
│└─┬┘└─┬┘└─┬┘    │       │
│  u   g   o     │       └── groupe propriétaire
│                └── propriétaire
└── type
```

**Types rencontrés :**

| Caractère | Type | Exemple |
|---|---|---|
| `-` | fichier ordinaire | `config.txt` |
| `d` | répertoire | `/etc` |
| `l` | lien symbolique | `/bin -> usr/bin` |
| `s` | socket | `/var/run/docker.sock` |
| `c` | périphérique caractère | `/dev/null` |
| `b` | périphérique bloc | un disque |

→ 9 caractères de permissions, pas 10 : le premier est le **type**.

---

## 2. La notation octale

| Droit | Lettre | Valeur |
|---|---|---|
| Lecture | `r` | **4** |
| Écriture | `w` | **2** |
| Exécution / traversée | `x` | **1** |

On additionne par position :

| Combinaison | Calcul | Chiffre |
|---|---|---|
| `rwx` | 4+2+1 | **7** |
| `rw-` | 4+2 | **6** |
| `r-x` | 4+1 | **5** |
| `r--` | 4 | **4** |
| `--x` | 1 | **1** |

**Les valeurs courantes :**

| Octal | Symbolique | Usage |
|---|---|---|
| `644` | `rw-r--r--` | fichier normal |
| `755` | `rwxr-xr-x` | répertoire, script exécutable |
| `600` | `rw-------` | fichier sensible |
| `700` | `rwx------` | répertoire privé (`~/.ssh`, logs applicatifs) |

> Jamais de 8 ni de 9 : chaque position code 3 bits, donc 0 à 7.

---

## 3. ⚠️ Sur un répertoire, le sens change

**Le point le plus important de la journée.**

| Droit | Sur un **fichier** | Sur un **répertoire** |
|---|---|---|
| `r` | lire le contenu | lister les **noms** |
| `w` | modifier le contenu | **créer et supprimer** des entrées |
| `x` | exécuter | **traverser** (entrer, accéder aux fichiers) |

### Vérifié en pratique

| Droits du répertoire | `ls dossier` | `cat dossier/fichier` |
|---|---|---|
| `644` → `rw-r--r--` | ✅ noms seulement (+ erreur) | ❌ |
| `711` → `rwx--x--x` | ❌ | ✅ si le nom est connu |
| `755` → `rwxr-xr-x` | ✅ | ✅ |

**`r` sans `x`** = voir le sommaire d'un livre sans pouvoir l'ouvrir.
**`x` sans `r`** = lire un fichier dont on connaît le nom exact, sans pouvoir découvrir ce qui existe. Vraie technique de protection.

> Sur un répertoire, `x` ne veut pas dire « exécuter » mais **« traverser »**.
> C'est pourquoi un répertoire est en `755` et pas `644`.

### Le cas du script

| Type de fichier | Droits minimum pour exécuter |
|---|---|
| Binaire compilé | `--x` suffit |
| **Script shell** | **`r-x` obligatoire** |

Un script n'est pas exécuté par le noyau mais **lu ligne par ligne par l'interpréteur** (`bash`, via le `#!`). Sans `r`, bash ne peut rien lire.

→ Script : **755** · Binaire : 711 possible si on veut en cacher le contenu.

---

## 4. Supprimer ≠ modifier

**Un fichier en `444` (lecture seule pour tous) peut être supprimé.**

Parce que supprimer ne modifie pas le fichier : ça retire une ligne de la table du répertoire. **Seul le `w` sur le répertoire compte.**

`rm` demande confirmation quand il voit un fichier protégé en écriture — c'est une politesse de `rm`, pas une protection du système. `rm -f` ne demande rien.

> Rendre un fichier en lecture seule ne le protège **pas** de la suppression.
> Pour le protéger, il faut restreindre le répertoire parent.

---

## 5. Le umask

Linux part d'une valeur maximale et **masque** :

```
Fichier    :  666 − umask
Répertoire :  777 − umask
```

Avec le défaut `022` :

```
Fichier    :  666 − 022 = 644
Répertoire :  777 − 022 = 755
```

### ⚠️ L'opération se fait chiffre par chiffre

**Pas une soustraction décimale.** `666 − 077` ne fait pas 589.

```
       666  →  rw-  rw-  rw-
umask  077  →  ---  rwx  rwx
       ───
       600  →  rw-  ---  ---
```

Aucune retenue ne circule, le résultat ne descend jamais sous 0.

### Pourquoi 666 et pas 777 pour un fichier

Le bit `x` n'est **jamais** attribué automatiquement à un fichier. Garde-fou : un fichier ne doit pas devenir exécutable par accident. Il faut `chmod +x` explicitement.

### Pourquoi le umask contient quand même un 7

Le umask est **unique** mais s'applique aux deux valeurs de départ. Les répertoires, eux, ont besoin du `x`. Avec `066` un répertoire resterait en `711` (traversable par tous) ; avec `077` il tombe à `700`.

### Umasks utiles

| Umask | Fichier | Répertoire | Contexte |
|---|---|---|---|
| `022` | 644 | 755 | défaut, poste personnel |
| `027` | 640 | 750 | **serveur partagé** : groupe lit, autres rien |
| `077` | 600 | 700 | maximum de confidentialité |
| `002` | 664 | 775 | répertoire d'équipe (avec SGID) |

---

## 6. Les trois bits spéciaux

Un **quatrième chiffre** devant les trois autres.

| Bit | Valeur | Effet | Se repère à |
|---|---|---|---|
| **SUID** | 4 | Le programme s'exécute avec les droits de **son propriétaire** | `s` à la place du `x` du **propriétaire** |
| **SGID** | 2 | Sur un répertoire : les fichiers créés héritent du **groupe du répertoire** | `s` à la place du `x` du **groupe** |
| **Sticky** | 1 | Seul le propriétaire du fichier (ou du répertoire) peut supprimer | `t` en **dernière** position |

### SUID — exemple `passwd`

```
-rwsr-xr-x  root root  /usr/bin/passwd
```

`passwd` doit écrire dans `/etc/shadow`, réservé à root. Grâce au SUID, il tourne **en tant que root** le temps de son exécution, quel que soit celui qui le lance.

→ Le SUID **accorde** un privilège, il n'en retire pas.

**Audit de sécurité :**
```bash
find / -xdev -perm -4000 -type f 2>/dev/null
```
Le `-xdev` évite de parcourir `/mnt/c`, `/proc`, `/sys` (indispensable sous WSL).

Les SUID légitimes se répartissent en 3 familles :
- **changer d'identité** : `su`, `sudo`, `newgrp`, `pkexec`
- **modifier des fichiers système** : `passwd`, `chsh`, `chfn`, `gpasswd`
- **système de fichiers** : `mount`, `umount`

> 🚩 **Alerte :** un SUID dans `/tmp`, `/home` ou `/opt`, ou une copie de `bash`/`cp` avec ce bit = porte dérobée classique.

### SGID — répertoire d'équipe

```bash
mkdir team
sudo chgrp docker team
chmod 2775 team
```

Tout fichier créé dedans appartient au groupe `docker`, quel que soit son créateur. Résout le problème des dossiers partagés où chacun crée des fichiers avec son groupe personnel, illisibles par les autres.

> ⚠️ **Piège vérifié :** le SGID agit **au moment de la création**, pas rétroactivement. Changer le groupe du répertoire ne touche pas les fichiers existants.
> → `sudo chgrp -R groupe dossier/`

Se combine avec `umask 002` pour que le groupe puisse aussi écrire.

### Sticky bit — `/tmp`

```
drwxrwxrwt  /tmp     = 1777
```

Tout le monde écrit, mais **chacun ne supprime que ses propres fichiers**. Sans lui, un espace partagé en écriture serait ingérable (cf. section 4).

> Le **propriétaire du répertoire** garde le droit de tout supprimer — sinon il ne pourrait pas faire le ménage chez lui.

---

## 7. Utilisateurs et groupes

### Les trois zones d'UID

| UID | Catégorie | Shell | Exemples |
|---|---|---|---|
| **0** | root — tous les droits | `/bin/bash` | root |
| **1–999** | comptes **système** | `/usr/sbin/nologin` | daemon, docker (989), monapp (999) |
| **1000+** | humains | `/bin/bash` | achraf (1000) |

> **UID 0 = root.** Le noyau teste le **numéro**, pas le nom. Tout compte avec UID 0 est root — porte dérobée classique à chercher en audit.

### Anatomie de `/etc/passwd`

```
monapp : x : 999 : 988 : : /home/monapp : /usr/sbin/nologin
  nom    │   UID   GID  │      home            shell
         │              └── commentaire
         └── mot de passe dans /etc/shadow
```

| Fichier | Contenu | Lisible par |
|---|---|---|
| `/etc/passwd` | liste des utilisateurs | tout le monde |
| `/etc/group` | liste des groupes | tout le monde |
| `/etc/shadow` | mots de passe chiffrés | **root seulement** |

### `nologin`

Programme qui affiche un refus et quitte. Bloque la **connexion interactive**, mais **n'empêche pas** le compte de faire tourner un service.

```bash
sudo su - monapp
# → This account is currently not available
```

### Créer un compte de service

```bash
sudo useradd --system --no-create-home --shell /usr/sbin/nologin monapp
```

### Le groupe `docker`

Être membre du groupe `docker` = **équivalent root en pratique** : on peut lancer un conteneur qui monte tout le système de fichiers. Point d'audit réel, question d'entretien classique.

```bash
sudo usermod -aG docker $USER   # le "a" = append, sans lui on sort de tous les autres groupes
```
→ Effectif seulement à la **prochaine session**.

---

## 8. Commandes

```bash
# Lire
ls -l fichier          # permissions, propriétaire, groupe
ls -ld dossier         # le répertoire lui-même, pas son contenu
stat fichier           # octal ET symbolique côte à côte
namei -l /chemin/complet/fichier    # ⭐ permissions de CHAQUE niveau du chemin

# Modifier
chmod 755 fichier      # octal
chmod u+x,g-r fichier  # symbolique
chmod -R 755 dossier/  # récursif
chown user fichier     # propriétaire — root uniquement
chown user:group f     # les deux d'un coup
chgrp group fichier    # groupe seulement

# Identité
id                     # UID, GID, groupes
id -u                  # UID seul
sudo -u nobody cmd     # exécuter en tant qu'un autre utilisateur

# umask
umask                  # afficher
umask 027              # définir (session courante)

# Audit
find / -xdev -perm -4000 -type f 2>/dev/null   # binaires SUID
```

---

## 9. ⭐ Méthode — diagnostiquer un « permission denied »

**L'ordre compte.** On remonte du fichier vers le répertoire, puis vers les parents, puis on sort des permissions.

| # | Cause | Commande |
|---|---|---|
| 1 | Droits du **fichier** | `ls -l /var/log/monapp/app.log` |
| 2 | Droits du **répertoire** (si le fichier doit être créé : `w` + `x`) | `ls -ld /var/log/monapp` |
| 3 | **Un répertoire parent bloque le chemin** | `namei -l /var/log/monapp/app.log` |
| 4 | **Disque plein** | `df -h /var/log` |
| 5 | Système de fichiers **monté en lecture seule** | `mount \| grep /var` |
| 6 | Le processus ne tourne pas sous **l'identité annoncée** | `ps -eo user,cmd \| grep monapp` |

### Pourquoi le point 3 est le plus traître

Pour atteindre `/var/log/monapp/app.log`, il faut le `x` sur **chaque** niveau :

```
/var/log/monapp/app.log
 └┬┘ └┬┘ └──┬──┘
  x   x     x      ← un seul manquant = tout échoue
```

**Vérifié en pratique :** `folder` était en `711` (traversable par tous), et pourtant `nobody` échouait — parce que `/home/achraf` était en `750`. Le blocage était 2 niveaux plus haut.

> En production : le fichier a l'air parfait, et le problème est trois répertoires au-dessus.

### Pourquoi le point 5 arrive vraiment

Quand le noyau détecte une corruption du système de fichiers, il le **repasse en lecture seule** pour protéger les données. Plus rien ne s'écrit, sans qu'aucune permission n'ait changé.

---

## 10. Pièges rencontrés

| Piège | Symptôme | À retenir |
|---|---|---|
| **Chemin relatif vs absolu** | `cat proc/cpuinfo` → No such file | Le `/` initial part de la racine ; sans lui, c'est relatif au dossier courant |
| **`grep` silencieux** | aucune sortie, aucune erreur | Un résultat vide = « rien trouvé » **ou** « recherche mal écrite » (`"modelname"` ≠ `"model name"`) |
| **`find /` sans `-xdev`** | semble figé | Sous WSL, il parcourt tout `/mnt/c` à travers une couche lente. `-xdev` reste sur la partition racine |
| **`usermod -G` sans le `a`** | perte de tous les autres groupes | `-aG` = **append** |
| **`chown` sans `sudo`** | Operation not permitted | Seul root peut **donner** un fichier à quelqu'un d'autre (sinon : contournement de quotas, fichiers piégés) |
| **SGID non rétroactif** | les anciens fichiers gardent leur groupe | `chgrp -R` pour rattraper |
| **Confondre fichier et répertoire** | `ls -l dossier` liste le contenu | `ls -ld` pour le répertoire lui-même |

---

## 11. `/proc` — tout est fichier

`/proc` n'existe pas sur le disque. Le noyau **génère** ces fichiers au moment de la lecture.

```bash
cat /proc/uptime      # 2254.06 27011.73 → change à chaque lecture
cat /proc/loadavg     # 0.00 0.00 0.00 1/268 1399
cat /proc/cpuinfo     # une entrée par processeur logique
```

**`/proc/uptime` :** temps depuis le démarrage · temps d'inactivité cumulé **de tous les cœurs** (d'où une valeur bien plus grande).

**`/proc/loadavg` :** charge sur 1, 5 et 15 min · processus actifs/total · dernier PID.

> ⚠️ La charge **n'est pas** un pourcentage de CPU. C'est le nombre moyen de processus qui veulent tourner. Une charge de 4 est confortable sur 12 cœurs, critique sur 2.

`top`, `htop`, `free` ne font que lire `/proc` et mettre en forme.

---

## 12. Vocabulaire pour les entretiens

- **Moindre privilège** : donner à un programme juste ce dont il a besoin, rien de plus. Décliné partout : utilisateur système (J2 systemd), `USER` non-root dans un Dockerfile (J5), compte de service GCP (S3), Workload Identity (S11).
- **Élévation de privilèges** : mécanisme par lequel un processus obtient plus de droits que l'utilisateur qui l'a lancé (SUID, sudo).
- **Défense en profondeur** : plusieurs barrières indépendantes plutôt qu'une seule.

---

## 🎯 Question d'entretien du jour

> *« Une application n'arrive pas à écrire dans son fichier de log alors que le fichier a les bonnes permissions. Comment diagnostiques-tu ? »*

**La bonne réponse ne commence pas par une commande, mais par une méthode** : on remonte du fichier vers le répertoire, puis vers les parents (`namei -l`), puis on vérifie sous quelle identité tourne réellement le processus, et enfin on sort des permissions — disque plein, montage en lecture seule.

---

## ✅ Auto-évaluation

- [ ] Je convertis `750` ⟷ `rwxr-x---` instantanément, dans les deux sens
- [ ] J'explique ce que fait `x` sur un répertoire et pourquoi c'est différent d'un fichier
- [ ] Je sais pourquoi un script a besoin de `r` et pas seulement de `x`
- [ ] J'explique pourquoi on peut supprimer un fichier en lecture seule
- [ ] Je calcule un umask chiffre par chiffre, sans retenue
- [ ] Je cite les 3 bits spéciaux avec un cas d'usage réel pour chacun
- [ ] Je connais `namei -l` et je sais quand l'utiliser
- [ ] Je déroule les 6 causes d'un « permission denied » dans l'ordre

---

## Demain — Jour 2 : systemd

L'utilisateur `monapp` et le répertoire `/var/log/monapp` (créés aujourd'hui) servent au **LAB-01** : transformer une application lancée à la main en service systemd résilient, tournant sous un compte sans shell.

C'est le même principe de moindre privilège, appliqué à un service qui tourne.