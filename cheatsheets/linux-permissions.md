# Linux — permissions, utilisateurs, arborescence

> Fiche de révision · Jour 1 · Les passages marqués « vérifié en pratique » ont été testés à la main ; le reste a été complété en relecture.

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
| `p` | tube nommé (FIFO) | créé par `mkfifo` |

→ 9 caractères de permissions, pas 10 : le premier est le **type**.

→ Un `+` après les permissions (`drwxr-xr-x+`) signale une **ACL** : des droits supplémentaires invisibles dans `ls -l`. À lire avec `getfacl`.

### Quel triplet s'applique ?

Le noyau ne teste **qu'un seul** triplet, le premier qui correspond :

1. Tu es le **propriétaire** → seul `u` compte
2. Sinon, tu es dans le **groupe** → seul `g` compte
3. Sinon → `o`

Pas de cumul : un fichier en `077` (`----rwxrwx`) est accessible à tout le monde **sauf à son propriétaire**.

> **root** ignore `r` et `w`. Pour exécuter un fichier, il lui faut quand même au moins un `x` posé quelque part.

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

Test fait par un **autre utilisateur** (`sudo -u nobody`), donc c'est le triplet **o** qui s'applique. Pour le propriétaire, `711` donne `rwx` et `ls` fonctionne.

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

À l'inverse, `bash script.sh` n'a besoin **que de `r`** : c'est bash qui est exécuté, le script est seulement lu.

→ Script : **755** · Binaire : 711 possible si on veut en cacher le contenu (sauf à root, qui peut toujours le lire).

---

## 4. Supprimer ≠ modifier

**Un fichier en `444` (lecture seule pour tous) peut être supprimé.**

Parce que supprimer ne modifie pas le fichier : ça retire une ligne de la table du répertoire. **Ce sont les droits du répertoire qui comptent : `w` + `x`.** Les droits du fichier ne jouent aucun rôle. Exception : le sticky bit (section 6).

`rm` demande confirmation quand il voit un fichier protégé en écriture (si on est dans un terminal). C'est une politesse de `rm`, pas une protection du système. `rm -f` ne demande rien.

> Rendre un fichier en lecture seule ne le protège **pas** de la suppression.
> Pour le protéger : restreindre le répertoire parent, ou poser l'attribut **immuable** `sudo chattr +i fichier`. Même root ne peut alors ni le modifier ni le supprimer sans d'abord retirer l'attribut (`chattr -i`). Pour vérifier : `lsattr fichier`.

---

## 5. Le umask

Le programme qui crée le fichier **demande** un mode. Le noyau **retire** de ce mode tous les bits présents dans le umask :

```
mode final = mode demandé  ET  NON umask
```

Les modes demandés habituels :

```
Fichier    :  666  (touch, éditeurs, redirection >)
Répertoire :  777  (mkdir)
```

Avec le défaut `022` :

```
Fichier    :  666 masqué par 022 = 644
Répertoire :  777 masqué par 022 = 755
```

### ⚠️ C'est un masquage de bits, pas une soustraction

Le umask **éteint des bits**, il ne soustrait rien. Ce n'est même pas une soustraction chiffre par chiffre :

```
       666  →  rw-  rw-  rw-
umask  077  →  ---  rwx  rwx     ← bits à éteindre
       ───
       600  →  rw-  ---  ---
```

`6 − 7` serait négatif. En réalité, on éteint `rwx` dans `rw-` et il reste `---`, soit 0.

**Le contre-exemple qui piège :** avec `umask 033` sur un fichier,

```
       666  →  rw-  rw-  rw-
umask  033  →  ---  -wx  -wx
       ───
       644  →  rw-  r--  r--     (et pas 633 !)
```

Le bit `x` du masque n'avait rien à éteindre, et seul `w` est retiré.

> Méthode : convertir en lettres, puis **barrer** dans le mode demandé les lettres présentes dans le umask.

### Pourquoi 666 et pas 777 pour un fichier

Le umask ne fait que **retirer** des bits. C'est le programme qui choisit le mode de départ. La plupart des programmes (`touch`, éditeurs, `>`) demandent `666`, sans `x`, pour qu'un fichier ne devienne pas exécutable par accident. Il faut alors un `chmod +x` explicite.

Certains programmes demandent quand même `x` :
- `gcc` demande `777` → `a.out` sort en `755`
- `cp` reprend le mode du fichier source

### Pourquoi le umask contient quand même un 7

Le umask est **unique** mais s'applique aux deux valeurs de départ. Les répertoires, eux, ont besoin du `x`. Avec `066` un répertoire resterait en `711` (traversable par tous) ; avec `077` il tombe à `700`.

### Umasks utiles

| Umask | Fichier | Répertoire | Contexte |
|---|---|---|---|
| `022` | 644 | 755 | défaut, poste personnel |
| `027` | 640 | 750 | **serveur partagé** : groupe lit, autres rien |
| `077` | 600 | 700 | maximum de confidentialité |
| `002` | 664 | 775 | répertoire d'équipe (avec SGID) |

`umask 027` ne vaut que pour le shell courant. Pour le rendre persistant :
- `~/.bashrc` : pour un utilisateur
- `/etc/login.defs` (`UMASK`) : pour tout le système
- `UMask=0027` dans l'unité : pour un service systemd

---

## 6. Les trois bits spéciaux

Un **quatrième chiffre** devant les trois autres.

| Bit | Valeur | Effet | Se repère à |
|---|---|---|---|
| **SUID** | 4 | Le programme s'exécute avec les droits de **son propriétaire** | `s` à la place du `x` du **propriétaire** |
| **SGID** | 2 | Sur un **exécutable** : il s'exécute avec les droits du **groupe du fichier**. Sur un **répertoire** : les fichiers créés héritent du **groupe du répertoire** | `s` à la place du `x` du **groupe** |
| **Sticky** | 1 | Seuls le propriétaire du fichier, celui du répertoire et root peuvent supprimer ou renommer | `t` en **dernière** position |

**Majuscule = bit spécial sans `x`.** `S` ou `T` en majuscule (`-rwSr--r--`) signale un bit spécial posé alors que le `x` en dessous est absent. C'est presque toujours une erreur de configuration : le bit n'a aucun effet utile.

### SUID — exemple `passwd`

```
-rwsr-xr-x  root root  /usr/bin/passwd
```

`passwd` doit écrire dans `/etc/shadow`, réservé à root. Grâce au SUID, il tourne **en tant que root** le temps de son exécution, quel que soit celui qui le lance.

→ Le SUID **accorde** un privilège, il n'en retire pas.

→ Linux **ignore** le SUID sur les scripts (`#!`) : ce serait une faille trop facile à exploiter. Il ne fonctionne que sur les binaires.

**Audit de sécurité :**
```bash
find / -xdev -perm -4000 -type f 2>/dev/null   # SUID
find / -xdev -perm -2000 -type f 2>/dev/null   # SGID
find / -xdev -perm /6000 -type f 2>/dev/null   # l'un OU l'autre
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
chgrp docker team      # pas besoin de sudo si on est propriétaire ET membre du groupe
chmod 2775 team
```

Tout fichier créé dedans appartient au groupe `docker`, quel que soit son créateur. Les **sous-répertoires** héritent aussi du bit SGID, donc tout l'arbre se comporte de la même façon. Résout le problème des dossiers partagés où chacun crée des fichiers avec son groupe personnel, illisibles par les autres.

> ⚠️ **Piège vérifié :** le SGID agit **au moment de la création**, pas rétroactivement. Changer le groupe du répertoire ne touche pas les fichiers existants.
> → `sudo chgrp -R groupe dossier/` (sudo nécessaire si des fichiers appartiennent à d'autres utilisateurs)

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

Les bornes sont des **conventions** fixées dans `/etc/login.defs` (`UID_MIN`, `SYS_UID_MAX`) et varient selon la distribution. Exemple : les anciens RHEL commençaient les humains à 500. Cas particulier : `nobody` = **65534**.

> **UID 0 = root.** Le noyau teste le **numéro**, pas le nom. Tout compte avec UID 0 est root — porte dérobée classique à chercher en audit.

### Anatomie de `/etc/passwd`

```
monapp : x : 999 : 988 : : /home/monapp : /usr/sbin/nologin
  nom    │   UID   GID  │      home            shell
         │              └── commentaire (champ GECOS)
         └── mot de passe dans /etc/shadow
```

| Fichier | Contenu | Lisible par |
|---|---|---|
| `/etc/passwd` | liste des utilisateurs | tout le monde |
| `/etc/group` | liste des groupes | tout le monde |
| `/etc/shadow` | mots de passe **hachés** | root (+ groupe `shadow` sur Debian/Ubuntu) |

> **Haché ≠ chiffré.** Un hachage est à sens unique : on ne peut pas retrouver le mot de passe à partir du hash. On vérifie un mot de passe en hachant ce qu'a tapé l'utilisateur et en comparant les deux. Un chiffrement, lui, se déchiffre avec une clé. La distinction compte en entretien.

### `nologin`

Programme qui affiche un refus et quitte. Bloque la **connexion interactive**, mais **n'empêche pas** le compte de faire tourner un service.

```bash
sudo su - monapp
# → This account is currently not available
```

> Ça ne bloque **pas root** : `sudo -u monapp commande` ou `sudo su -s /bin/bash monapp` fonctionnent toujours, car ils ne passent pas par le shell de connexion du compte.

### Créer un compte de service

```bash
sudo useradd --system --no-create-home --shell /usr/sbin/nologin monapp
```

### Le groupe `docker`

Être membre du groupe `docker` = **équivalent root en pratique** : on peut lancer un conteneur qui monte tout le système de fichiers. Point d'audit réel, question d'entretien classique.

```bash
sudo usermod -aG docker $USER   # le "a" = append, sans lui on sort de tous les autres groupes
```
→ Effectif seulement à la **prochaine session**, ou tout de suite dans le shell courant avec `newgrp docker`.

> Un processus garde les groupes qu'il avait **au moment de son démarrage**. Un service déjà lancé ne voit pas un nouveau groupe tant qu'on ne l'a pas redémarré.

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
chmod -R u=rwX,go=rX dossier/   # récursif : X majuscule = x seulement sur les répertoires
                                # (⚠️ chmod -R 755 rendrait TOUS les fichiers exécutables)
chown user fichier     # propriétaire — root uniquement
chown user:group f     # les deux d'un coup
chgrp group fichier    # groupe — le propriétaire peut le faire vers un groupe dont il est membre

# ACL et attributs
getfacl fichier        # droits ACL (le "+" dans ls -l)
lsattr fichier         # attributs : i = immuable, a = ajout seulement
sudo chattr +i fichier # rendre immuable

# Identité
id                     # UID, GID, groupes
id -u                  # UID seul
sudo -u nobody cmd     # exécuter en tant qu'un autre utilisateur

# umask
umask                  # afficher
umask -S               # afficher en symbolique (u=rwx,g=rx,o=rx)
umask 027              # définir (session courante)

# Audit
find / -xdev -perm -4000 -type f 2>/dev/null   # binaires SUID
find / -xdev -perm -2000 -type f 2>/dev/null   # binaires SGID
```

---

## 9. ⭐ Méthode — diagnostiquer un « permission denied »

### Étape 0 : lire le message d'erreur exact

Plusieurs problèmes différents se ressemblent, mais le noyau renvoie une erreur précise pour chacun :

| Message | Code | Piste |
|---|---|---|
| `Permission denied` | `EACCES` | droits, ACL, SELinux/AppArmor |
| `Operation not permitted` | `EPERM` | attribut `chattr`, action réservée à root |
| `Read-only file system` | `EROFS` | montage en lecture seule |
| `No space left on device` | `ENOSPC` | disque plein **ou** plus d'inodes libres |

Dans les logs d'une application, le message est souvent reformulé : on retrouve l'erreur exacte avec `strace -f -e trace=file -p <PID>`.

### Ensuite, dans l'ordre

**L'ordre compte.** On remonte du fichier vers le répertoire, puis vers les parents, puis on vérifie l'identité du processus, et enfin on sort des permissions classiques.

| # | Cause | Commande |
|---|---|---|
| 1 | Droits du **fichier** | `ls -l /var/log/monapp/app.log` |
| 2 | Droits du **répertoire** (si le fichier doit être créé : `w` + `x`) | `ls -ld /var/log/monapp` |
| 3 | **Un répertoire parent bloque le chemin** | `namei -l /var/log/monapp/app.log` |
| 4 | Le processus ne tourne pas sous **l'identité annoncée**, ou n'a pas les **groupes attendus** (ajoutés après son démarrage) | `ps -o user,group,supgrp,cmd -C monapp` |
| 5 | **ACL** qui restreint (le `+` dans `ls -l`) | `getfacl /var/log/monapp/app.log` |
| 6 | **Attribut** immuable ou ajout seulement (`i`, `a`) | `lsattr /var/log/monapp/app.log` |
| 7 | **SELinux / AppArmor** : bloque même quand les droits sont bons | `ls -Z` · `ausearch -m avc` · `aa-status` · `dmesg` |
| 8 | **Sandbox systemd** (`ProtectSystem=`, `ReadWritePaths=`) | `systemctl cat monapp` |
| 9 | **Disque plein** ou **plus d'inodes** | `df -h /var/log` · `df -i /var/log` |
| 10 | Système de fichiers **monté en lecture seule** | `findmnt -T /var/log` |

> Les points 7 et 8 sont la réponse classique à « les permissions ont l'air bonnes et pourtant ça échoue ». Le point 8 sera directement utile au J2.

### Pourquoi le point 3 est le plus traître

Pour atteindre `/var/log/monapp/app.log`, il faut le `x` sur **chaque** niveau :

```
/var/log/monapp/app.log
 └┬┘ └┬┘ └──┬──┘
  x   x     x      ← un seul manquant = tout échoue
```

**Vérifié en pratique :** `folder` était en `711` (traversable par tous), et pourtant `nobody` échouait — parce que `/home/achraf` était en `750`. Le blocage était 2 niveaux plus haut.

> En production : le fichier a l'air parfait, et le problème est trois répertoires au-dessus.

### Pourquoi le point 10 arrive vraiment

Quand le noyau détecte une erreur sur le système de fichiers et qu'il est monté avec l'option `errors=remount-ro` (le défaut sur Ubuntu, voir `/etc/fstab`), il le **repasse en lecture seule** pour protéger les données. Plus rien ne s'écrit, sans qu'aucune permission n'ait changé.

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

**`/proc/loadavg` :** charge sur 1, 5 et 15 min · tâches exécutables/total (threads compris) · dernier PID attribué.

> ⚠️ La charge **n'est pas** un pourcentage de CPU. C'est le nombre moyen de tâches qui tournent ou attendent le CPU, **plus**, sous Linux, celles bloquées en état **D** (attente d'I/O disque ou réseau type NFS). Une charge de 4 est confortable sur 12 cœurs, critique sur 2.
>
> **Charge élevée + CPU au repos** = probablement un problème d'I/O, pas de CPU.

`top`, `htop`, `free` ne font que lire `/proc` et mettre en forme.

---

## 12. Vocabulaire pour les entretiens

- **Moindre privilège** : donner à un programme juste ce dont il a besoin, rien de plus. Décliné partout : utilisateur système (J2 systemd), `USER` non-root dans un Dockerfile (J5), compte de service GCP (S3), Workload Identity (S11).
- **Élévation de privilèges** : mécanisme par lequel un processus obtient plus de droits que l'utilisateur qui l'a lancé (SUID, sudo).
- **Défense en profondeur** : plusieurs barrières indépendantes plutôt qu'une seule.

---

## 🎯 Question d'entretien du jour

> *« Une application n'arrive pas à écrire dans son fichier de log alors que le fichier a les bonnes permissions. Comment diagnostiques-tu ? »*

**La bonne réponse ne commence pas par une commande, mais par une méthode** :
1. lire l'**erreur exacte** (`EACCES`, `EPERM`, `EROFS`, `ENOSPC`) ;
2. remonter du fichier vers le répertoire, puis vers les parents (`namei -l`) ;
3. vérifier sous quelle **identité et avec quels groupes** tourne réellement le processus ;
4. regarder ce que `ls -l` ne montre pas : ACL, `chattr`, **SELinux/AppArmor**, sandbox systemd ;
5. sortir des permissions : disque ou inodes pleins, montage en lecture seule.

---

## ✅ Auto-évaluation

- [ ] Je convertis `750` ⟷ `rwxr-x---` instantanément, dans les deux sens
- [ ] J'explique ce que fait `x` sur un répertoire et pourquoi c'est différent d'un fichier
- [ ] Je sais pourquoi un script a besoin de `r` et pas seulement de `x`
- [ ] J'explique pourquoi on peut supprimer un fichier en lecture seule
- [ ] Je sais qu'un seul triplet (u, g ou o) s'applique, et pourquoi `077` bloque le propriétaire
- [ ] J'applique un umask comme un masque de bits, et je sais pourquoi `umask 033` donne `644` et pas `633`
- [ ] Je cite les 3 bits spéciaux avec un cas d'usage réel pour chacun
- [ ] Je connais `namei -l` et je sais quand l'utiliser
- [ ] Je distingue `EACCES`, `EPERM`, `EROFS` et `ENOSPC`
- [ ] Je déroule les causes d'un « permission denied » dans l'ordre, y compris ce que `ls -l` ne montre pas (ACL, `chattr`, SELinux/AppArmor)

---

## Demain — Jour 2 : systemd

L'utilisateur `monapp` et le répertoire `/var/log/monapp` (créés aujourd'hui) servent au **LAB-01** : transformer une application lancée à la main en service systemd résilient, tournant sous un compte sans shell.

C'est le même principe de moindre privilège, appliqué à un service qui tourne.