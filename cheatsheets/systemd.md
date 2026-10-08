# systemd — services, logs, diagnostic

> Fiche de révision · Jour 2 · Tout ce qui suit a été vérifié en pratique sur le service `velocite`.

---

## 1. Ce qu'est systemd

**systemd est le processus numéro 1.** Le noyau le lance en premier, tout le reste en descend.

```bash
ps -p 1 -o comm=    # → systemd
```

Le `d` final signifie **daemon** — un programme qui tourne en arrière-plan. Même convention que `sshd`, `dockerd`, `containerd`.

> Toujours écrit en minuscules : `systemd`. Jamais « SystemD ».

### Son rôle

- démarrer les services dans le bon ordre, en parallèle quand c'est possible
- les surveiller et les redémarrer en cas de crash
- centraliser leurs logs
- les isoler les uns des autres

### Les units

| Type | Rôle | Exemple |
|---|---|---|
| `.service` | **un programme qui tourne** | `velocite.service` |
| `.socket` | un port qui déclenche un service | `docker.socket` |
| `.timer` | tâche planifiée (remplaçant moderne de cron) | `apt-daily.timer` |
| `.target` | groupe d'units, état du système | `multi-user.target` |
| `.mount` | point de montage | `var-log.mount` |

### Où vivent les fichiers

| Répertoire | Contenu | Priorité |
|---|---|---|
| `/usr/lib/systemd/system/` | units fournies par les **paquets** — ne jamais modifier | basse |
| `/etc/systemd/system/` | units de l'**administrateur** — **c'est ici qu'on écrit** | **haute** |
| `/run/systemd/system/` | units temporaires, disparaissent au reboot | moyenne |

> Un fichier de même nom dans `/etc/` surcharge celui de `/usr/lib/`. C'est le mécanisme prévu pour personnaliser sans risquer qu'une mise à jour de paquet écrase ton travail.

### Les cgroups

```
CGroup: /system.slice/velocite.service
        └─3411 /usr/bin/node /opt/velocite/server.js
```

Un **cgroup** enferme un service et **tous ses processus enfants**. C'est ce qui permet à systemd de tout arrêter proprement, de mesurer la mémoire et le CPU, et d'imposer des limites.

> 🔗 Les conteneurs Docker reposent sur ce même mécanisme, combiné aux *namespaces*.

---

## 2. Anatomie d'un fichier `.service`

Format INI, toujours trois sections.

```ini
[Unit]       # qui je suis, de quoi je dépends
[Service]    # comment me lancer, sous quelle identité, que faire si je tombe
[Install]    # faut-il me démarrer au boot
```

### Exemple complet — `/etc/systemd/system/velocite.service`

```ini
[Unit]
Description=Boutique Velocite - serveur de rendu
After=network-online.target
Wants=network-online.target
StartLimitBurst=4
StartLimitIntervalSec=120

[Service]
Type=simple
User=velocite
Group=velocite
WorkingDirectory=/opt/velocite
EnvironmentFile=/etc/velocite/velocite.env
ExecStart=/usr/bin/node /opt/velocite/server.js
Restart=on-failure
RestartSec=5
TimeoutStopSec=15
UMask=0027
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
LogsDirectory=velocite
LogsDirectoryMode=0750

[Install]
WantedBy=multi-user.target
```

> ⚠️ **Les directives s'écrivent en PascalCase** : `WantedBy`, `ReadWritePaths`, `NoNewPrivileges`. Une faute de casse = directive ignorée ou rejetée.

---

## 3. `[Unit]` — identité et dépendances

### Les trois types de dépendance

| Directive | Garantit | Si l'autre échoue |
|---|---|---|
| `After=` | **l'ordre seulement** | on démarre quand même |
| `Wants=` | tente de démarrer l'autre (**souple**) | on démarre quand même |
| `Requires=` | exige l'autre (**strict**) | **on ne démarre pas** |

> ⚠️ **Piège classique :** `Requires=` ne garantit **pas** l'ordre. Sans `After=`, les deux démarrent en parallèle. En pratique on écrit presque toujours les deux ensemble.

**Règle de conception :** réserver `Requires=` à ce qui est réellement indispensable. Trop de `Requires` crée des chaînes fragiles où un service secondaire en panne bloque toute la pile.

### Les cibles utiles

| Cible | Signifie |
|---|---|
| `network.target` | la pile réseau est configurée (**pas forcément joignable**) |
| `network-online.target` | le réseau est **réellement utilisable** |
| `multi-user.target` | système démarré, prêt à servir — la cible normale d'un serveur |

→ Pour une application qui a besoin du réseau : `network-online.target`.

### La protection anti-boucle

```ini
StartLimitBurst=4
StartLimitIntervalSec=120
```

**Maximum 4 démarrages par fenêtre glissante de 120 secondes.** Au-delà, systemd abandonne et marque le service `failed`.

> 🔬 **Vérifié en pratique :** c'est bien une **fenêtre glissante**, pas un compteur absolu.
> ```
> 19:59:00  ← hors fenêtre au moment du refus
> 20:00:57  ┐
> 20:01:03  │ 4 démarrages dans les
> 20:01:09  │ 120 dernières secondes
> 20:01:15  ┘
> 20:01:19  ← le 5e dans la fenêtre : REFUSÉ
> ```
> Conséquence : un service qui crashe une fois par heure n'est jamais bloqué ; un service qui crashe en rafale l'est immédiatement.

---

## 4. `[Service]` — l'exécution

### `ExecStart` — la ligne essentielle

```ini
ExecStart=/usr/bin/node /opt/velocite/server.js
```

**Chemin absolu obligatoire.** systemd n'utilise pas le `PATH`. `ExecStart=node app.js` échoue.

| Directive | Rôle |
|---|---|
| `ExecStartPre=` | commande lancée **avant** le démarrage (migrations, vérifications) |
| `ExecStop=` | commande d'arrêt personnalisée |
| `ExecReload=` | ce que fait `systemctl reload` |

### `User=` et `Group=`

**Sans ces lignes, le service tourne en root.** C'est le défaut, et c'est dangereux.

```bash
sudo useradd --system --no-create-home --shell /usr/sbin/nologin velocite
```

| Propriété | Pourquoi |
|---|---|
| UID < 1000 | compte système, filtré par les outils d'audit |
| `/usr/sbin/nologin` | **aucune session interactive**, même après compromission |
| pas de home | un service n'en a pas besoin |

> Le compte peut malgré tout faire tourner un service — seule la **connexion interactive** est bloquée.

### La configuration

```ini
EnvironmentFile=/etc/velocite/velocite.env
```

Format du fichier : `CLE=valeur`, une par ligne. **Pas de `export`, pas de guillemets, pas d'espaces autour du `=`.**

> 🔑 **Nuance majeure :** `EnvironmentFile=` est lu par **systemd**, qui tourne en root, *avant* d'abaisser les privilèges vers `User=`.
> → Le fichier peut appartenir à **root en 600**. Le compte de service ne le lit jamais, il reçoit les variables déjà injectées.
> ```bash
> sudo -u velocite cat /etc/velocite/velocite.env   # → Permission denied
> # et pourtant l'app démarre avec "dbPassConfigured":true
> ```

> ⚠️ **Jamais de secret dans l'unit elle-même.** `/etc/systemd/system/` est en `755` : un `systemctl cat` exposerait le mot de passe à tout le monde.

### Les types de service

| Type | Le programme... | systemd considère le service démarré... |
|---|---|---|
| **`simple`** | reste au premier plan | **immédiatement** |
| `exec` | idem | après exécution effective du binaire |
| `forking` | se détache en arrière-plan | quand le processus **parent** se termine |
| `oneshot` | fait une tâche et se termine | quand le processus se termine |
| `notify` | prévient systemd lui-même | à la réception du signal |

**Les deux erreurs symétriques :**

- `forking` sur un programme au premier plan → systemd attend un parent qui ne meurt jamais → timeout de 90 s puis échec, **alors que le service fonctionne**
- `simple` sur un programme qui se démonise → systemd croit à un crash → relance en boucle pendant que le vrai processus tourne, invisible

> **Règle :** une application moderne (Node, Python, Go, Java) reste au premier plan → **`Type=simple`**.

### La politique de redémarrage

| Valeur | Redémarre quand... |
|---|---|
| `no` | jamais (défaut) |
| `on-failure` | code ≠ 0, signal, timeout |
| `on-abnormal` | signal ou timeout seulement |
| `always` | **dans tous les cas**, même après un arrêt propre |

**`on-failure` vs `always` :** `on-failure` respecte un arrêt volontaire (code 0) ; `always` relance quand même. Pour une application métier, `on-failure` est généralement le bon choix.

```ini
RestartSec=5
```

Sans délai (défaut 100 ms), un service qui échoue au démarrage sature le CPU.

> ⚠️ `Restart=always` **sans** `StartLimitBurst` = boucle infinie garantie. Les deux vont ensemble.

### L'arrêt propre

```ini
TimeoutStopSec=15
```

Délai accordé après `SIGTERM` avant que systemd envoie `SIGKILL`.

Si l'application s'accorde 10 s pour finir ses requêtes, une valeur inférieure la ferait tuer avant la fin — et toute la logique d'arrêt propre du code ne servirait à rien.

> 🔬 **Vérifié :** requête de 8 s en cours, `restart` du service après 2 s → la requête se termine avec **`200`**.
> ```
> Stopping velocite.service...
> "SIGTERM recu, arret en cours"
> "arret termine"
> Deactivated successfully.
> ```

### `UMask=` vs `LogsDirectoryMode=`

**Deux acteurs, deux moments.**

| | Créé par | Quand | Contrôlé par |
|---|---|---|---|
| Le **répertoire** `/var/log/velocite` | **systemd** | avant que le processus existe | `LogsDirectoryMode=` |
| Le **fichier** `audit.log` | **l'application** | pendant l'exécution | `UMask=` |

Le umask est une propriété du **processus**. Il ne s'applique pas à ce que systemd crée lui-même, en root, avant le lancement.

```ini
UMask=0027              # fichiers créés par l'app → 640 (666 − 027)
LogsDirectoryMode=0750  # répertoire créé par systemd → 750
```

---

## 5. Le durcissement (sandboxing)

systemd isole un service **sans conteneur**. Ces directives sont gratuites et efficaces.

| Directive | Effet |
|---|---|
| `NoNewPrivileges=true` | le processus ne peut **jamais** gagner de privilèges, même via un binaire SUID |
| `PrivateTmp=true` | `/tmp` privé et isolé |
| `ProtectSystem=strict` | **tout le système de fichiers en lecture seule** |
| `ProtectHome=true` | `/home`, `/root`, `/run/user` **masqués** |
| `PrivateDevices=true` | pas d'accès aux périphériques physiques |
| `ReadWritePaths=` | exceptions en écriture à `ProtectSystem=strict` |

### Les directories managées

| Directive | Crée et gère | Persiste à l'arrêt |
|---|---|---|
| `LogsDirectory=` | `/var/log/<nom>` | oui |
| `StateDirectory=` | `/var/lib/<nom>` — données persistantes | oui |
| `CacheDirectory=` | `/var/cache/<nom>` — données jetables | oui |
| `RuntimeDirectory=` | `/run/<nom>` | **non**, effacé |

`LogsDirectory=velocite` fait **quatre choses** en une ligne :
1. crée `/var/log/velocite`
2. lui donne le `User=`/`Group=` du service
3. le rend accessible en écriture **malgré** `ProtectSystem=strict`
4. crée les dépendances de montage si `/var/log` est sur une partition séparée

→ Remplace `mkdir` + `chown` + `chmod` + `ReadWritePaths=`.

> ⚠️ **`ConfigurationDirectory=` n'est PAS nécessaire pour lire `/etc`.** `ProtectSystem=strict` rend le système en **lecture seule**, pas illisible. Et cette directive créerait le répertoire en `0755` — ce qui exposerait un fichier de secrets.

### Mesurer le durcissement

```bash
systemd-analyze security velocite
```

> 🔬 **Résultats constatés :**
> - `velocite.service` → **8.3 EXPOSED** (4 directives posées)
> - `docker.service` → **9.6 UNSAFE**
>
> Ce score mesure l'**écart entre ce qu'un service peut faire et ce dont il a besoin**, pas sa qualité. Docker a besoin des périphériques, namespaces et cgroups : il ne peut pas être confiné. Le même score sur un serveur web serait un problème.

---

## 6. `[Install]` — le démarrage au boot

```ini
[Install]
WantedBy=multi-user.target
```

**Sans cette section, `systemctl enable` échoue** et le service ne repart pas au reboot.

### enabled ≠ active

| | Question | Commande |
|---|---|---|
| **active** | Tourne-t-il **maintenant** ? | `systemctl is-active` |
| **enabled** | Démarre-t-il **au boot** ? | `systemctl is-enabled` |

Les quatre combinaisons existent :

| État | Signification |
|---|---|
| active + enabled | fonctionnement normal en production |
| active + disabled | démarré à la main, ne survivra pas au reboot |
| inactive + enabled | arrêté temporairement, repartira au reboot |
| inactive + disabled | complètement désactivé |

---

## 7. Commandes

```bash
# Cycle de vie
sudo systemctl start   velocite
sudo systemctl stop    velocite
sudo systemctl restart velocite
sudo systemctl reload  velocite        # recharge la config sans arrêter

# Boot
sudo systemctl enable  velocite
sudo systemctl disable velocite
sudo systemctl enable --now velocite   # enable + start

# État et inspection
systemctl status velocite              # vue complète (q pour quitter)
systemctl is-active velocite
systemctl is-enabled velocite
systemctl cat velocite                 # afficher le fichier d'unit
systemctl show velocite                # TOUTES les propriétés résolues
systemctl --failed                     # ⭐ les services en échec
systemd-analyze verify /etc/systemd/system/velocite.service
systemd-analyze security velocite

# ⭐ Après TOUTE modification d'une unit
sudo systemctl daemon-reload
sudo systemctl restart velocite

# ⭐ Débloquer après dépassement de StartLimitBurst
sudo systemctl reset-failed velocite
sudo systemctl start velocite
```

> ⚠️ **`daemon-reload` est l'oubli le plus fréquent.** systemd garde les units en mémoire : sans cette commande, il utilise l'ancienne version et le débogage tourne à vide.

> 🔬 **Constaté :** `reset-failed` est nécessaire **dans les 120 s** suivant le dépassement. Au-delà, la fenêtre glissante s'est vidée et un simple `start` suffit. En astreinte, faire `reset-failed` systématiquement évite de se poser la question.

---

## 8. Les logs avec `journalctl`

systemd capture automatiquement **stdout et stderr** de chaque service. Rien à configurer.

> 💡 **Conséquence pour ton code :** n'écris pas dans un fichier de log depuis l'application. Écris sur la **sortie standard**, systemd s'occupe du reste. C'est aussi la bonne pratique en conteneur (12-factor app).

```bash
journalctl -u velocite                 # logs de ce service
journalctl -u velocite -n 50           # les 50 dernières lignes
journalctl -u velocite -f              # ⭐ suivi en direct
journalctl -u velocite --since "10 min ago"
journalctl -u velocite --since today
journalctl -u velocite -p err          # erreurs et plus grave
journalctl -u velocite --no-pager      # sans pagination (scripts)
journalctl -b                          # depuis le dernier démarrage
journalctl -u velocite -o json-pretty  # format structuré complet
```

Priorités, de 0 à 7 : `emerg`, `alert`, `crit`, `err`, `warning`, `notice`, `info`, `debug`. `-p err` affiche 0 à 3.

### Pourquoi mieux qu'un fichier de log

| | Fichier `app.log` | journald |
|---|---|---|
| Rotation | à configurer (logrotate) | automatique |
| Horodatage | à faire dans le code | automatique et uniforme |
| Filtrage par service | grep approximatif | natif |
| Métadonnées (PID, UID, unit) | absentes | automatiques |
| Survit à une relance | **non si redirection `>`** | oui |

> 🔬 **Le problème constaté sur l'ancien déploiement :**
> ```bash
> nohup node server.js > /tmp/out.log 2>&1 &
> ```
> La redirection `>` **écrase** le fichier à chaque relance. Les traces de l'incident disparaissent au moment précis où on relance le service pour le réparer.

---

## 9. ⭐ Méthode — diagnostiquer un service

**Dans l'ordre.**

| # | Étape | Commande |
|---|---|---|
| 1 | Lire le message exact | `systemctl status velocite` |
| 2 | **Lire les logs complets** | `journalctl -u velocite -n 50 --no-pager` |
| 3 | Vérifier la syntaxe de l'unit | `systemd-analyze verify /etc/systemd/system/velocite.service` |
| 4 | Vérifier que le binaire existe | `ls -l /usr/bin/node` |
| 5 | Vérifier l'identité réelle du processus | `ps -eo user,pid,cmd \| grep server.js` |
| 6 | Vérifier les droits sur le chemin complet | `namei -l /chemin/fichier` |
| 7 | **Vérifier le sandboxing** | relire `ProtectSystem=`, `ProtectHome=`, `LogsDirectory=` |
| 8 | Vérifier qu'un `daemon-reload` a été fait | `systemctl status` signale le décalage |

> **Le `status` donne l'état. Le `journalctl` donne la cause.** Ne jamais s'arrêter au premier.

### Codes de sortie

| Code | Signification |
|---|---|
| `0` | arrêt normal |
| `1/FAILURE` | erreur générique de l'application |
| `126` | fichier trouvé mais **non exécutable** |
| `127` | **commande introuvable** |
| `200/CHDIR` | `WorkingDirectory=` inexistant |
| `203/EXEC` | systemd n'a pas pu **exécuter** le binaire |
| `217/USER` | l'utilisateur de `User=` n'existe pas |

---

## 10. ⚠️ Le piège du `203/EXEC` — à retenir absolument

**Le symptôme :** le service échoue avec `203/EXEC`, alors que le binaire est accessible.

```bash
sudo -u velocite /home/achraf/.nvm/.../node --version   # → v24.21.0 ✅
namei -l /home/achraf/.nvm/.../node                     # → tout en 755 ✅
systemctl status velocite                               # → 203/EXEC ❌
```

**La cause :** `ProtectHome=true` **masque `/home` par un mécanisme de montage**, indépendamment des permissions.

> `sudo` n'applique **aucun** confinement. systemd si. Les deux ne testent donc pas la même chose.

**Les deux solutions :**

| Option | Conséquence |
|---|---|
| Retirer `ProtectHome=true` | on perd une protection pour contourner un problème de déploiement |
| Installer le binaire à un emplacement système | on garde le confinement et on corrige la vraie cause |

**La bonne :** la seconde. Un binaire applicatif dans le répertoire personnel d'un développeur crée une dépendance fragile — compte supprimé = service mort ; changement de version pour un autre projet = production cassée.

```bash
sudo apt install -y nodejs
which -a node    # nvm pour toi, /usr/bin/node pour les services
```

> 🔗 **C'est la 7e cause de la méthode de diagnostic du Jour 1** : « les permissions ont l'air bonnes et pourtant ça ne marche pas ». Le sandboxing en est une variante.

---

## 11. Pièges rencontrés

| Piège | Symptôme | À retenir |
|---|---|---|
| **Casse des directives** | directive ignorée | PascalCase : `WantedBy`, `ReadWritePaths` |
| **Oubli de `daemon-reload`** | les modifications ne prennent pas | systemd garde les units en mémoire |
| **Dépendance inexistante en `Requires=`** | le service refuse de démarrer | ne mettre en `Requires` que l'indispensable |
| **`ProtectHome=true` + binaire dans `/home`** | `203/EXEC` | voir §10 |
| **Faute de frappe dans `ExecStart`** | `1/FAILURE` + `MODULE_NOT_FOUND` | `journalctl` donne le chemin exact cherché |
| **Directive vide** (`Documentation=`) | inutile au mieux, erreur au pire | supprimer plutôt que laisser vide |
| **`EADDRINUSE`** | le port est déjà pris | un processus fantôme tourne : `pkill -f server.js` |
| **Autocomplétion muette sur `/etc/velocite/`** | `Tab` ne propose rien | normal : le shell tourne sous ton compte, pas root. **C'est la preuve que la protection marche.** |

---

## 12. Mémo express

```bash
# Écrire / modifier
sudo nano /etc/systemd/system/mon-service.service
sudo systemctl daemon-reload          # ⭐ ne jamais oublier
sudo systemctl enable --now mon-service

# Vérifier
systemctl status mon-service
systemctl is-active mon-service
systemctl is-enabled mon-service

# Débugger
journalctl -u mon-service -n 50 --no-pager
journalctl -u mon-service -f

# Débloquer
sudo systemctl reset-failed mon-service
sudo systemctl start mon-service
```

---

## 🎯 Questions d'entretien

1. *« Comment fais-tu pour qu'un service redémarre automatiquement s'il crashe, sans partir en boucle infinie ? »*
2. *« Quelle est la différence entre `Requires=` et `Wants=` ? »*
3. *« Un service est `enabled` mais pas `active`. Qu'est-ce que ça veut dire ? »*
4. *« Tu as modifié un fichier d'unit et rien ne change. Pourquoi ? »*
5. *« Pourquoi un service ne doit-il pas tourner en root ? »*
6. *« Où doivent aller les logs de ton application : dans un fichier ou sur stdout ? Pourquoi ? »*
7. *« `Type=simple` vs `Type=forking` : que se passe-t-il si tu te trompes ? »*
8. *« Pourquoi mettre un mot de passe dans un fichier séparé plutôt que dans l'unit ? »*
9. *« À quoi sert `ProtectSystem=strict`, et quel problème ça peut créer ? »*
10. *« Comment gères-tu les répertoires de données d'un service sous systemd ? »*

---

## ✅ Auto-évaluation

- [ ] J'écris une unit complète de mémoire, avec ses trois sections
- [ ] J'explique `After=` vs `Wants=` vs `Requires=` avec un exemple
- [ ] Je sais pourquoi `Restart=always` sans `StartLimit*` est dangereux
- [ ] J'explique la fenêtre glissante de `StartLimitIntervalSec`
- [ ] Je diagnostique un service en échec avec `status` puis `journalctl`
- [ ] Je connais la différence `203/EXEC` / `1/FAILURE` / `217/USER`
- [ ] J'explique pourquoi `sudo -u` réussit là où systemd échoue
- [ ] Je sais pourquoi `EnvironmentFile` peut appartenir à root en 600
- [ ] J'explique `UMask=` vs `LogsDirectoryMode=`
- [ ] Je n'oublie jamais `daemon-reload`

---

## 🔗 Ce qui se poursuit

| Notion d'aujourd'hui | Où elle revient |
|---|---|
| Compte système sans shell | `USER` non-root dans un Dockerfile (S2), comptes de service GCP (S3) |
| cgroups | Docker (S2), `requests`/`limits` Kubernetes (S10) |
| Logs sur stdout | 12-factor app, logs de conteneurs (S2), Cloud Logging (S5) |
| Sandboxing | Pod Security, Network Policies (S11) |
| Configuration externalisée | variables d'environnement Docker (S2), Secret Manager (S5) |
| Arrêt propre sur SIGTERM | `terminationGracePeriod` Kubernetes (S11) |
| Runbook, MTTR | culture SRE, post-mortems (S12-S13) |