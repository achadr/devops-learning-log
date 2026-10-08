# Runbook — Service velocite

**Service :** boutique Vélocité, serveur de rendu Node.js
**Dernière mise à jour :** 8 octobre 2026
**Auteur :** Achraf

---

## 1. Contexte et incident

### L'incident du 6 octobre 2026

| Heure | Événement |
|---|---|
| 23h14 | Un visiteur atteint une page produit défaillante. L'application sort avec le code 1. |
| 23h14 → 08h30 | Site inaccessible. Page blanche. Aucune alerte. |
| 08h30 | La responsable e-commerce constate la panne. |
| 08h47 | Relance manuelle en SSH. Le site revient. |

**Durée totale : 9 h 33.** Sur un créneau représentant environ 12 % du chiffre d'affaires quotidien.

`/tmp/out.log` a été écrasé au redémarrage : aucune trace exploitable de la cause.

### Constat sur le déploiement existant

L'application était lancée ainsi :

```bash
cd /opt/velocite
nohup npm start > /tmp/out.log 2>&1 &
```

Six faiblesses identifiées et vérifiées :

| # | Constat | Vérifié par |
|---|---|---|
| 1 | Tourne sous un compte **humain**, avec tous ses droits | `ps -eo user,pid,cmd` → `achraf` |
| 2 | Une page défaillante visitée par n'importe qui tue le site entier | `curl /produit/404-fantome` → `Exit 1` |
| 3 | Aucun redémarrage automatique | le site reste mort indéfiniment |
| 4 | Le processus dépend du shell qui l'a lancé | — |
| 5 | Ne repart pas au redémarrage du serveur | aucun mécanisme de boot |
| 6 | Les logs sont **écrasés** à chaque relance | la redirection `>` tronque le fichier |

Le point 6 est le plus grave sur le plan opérationnel : il rend tout incident inanalysable *a posteriori*.

---

## 2. Ce qui a été mis en place

### 2.1 Compte de service

```bash
sudo useradd --system --no-create-home --shell /usr/sbin/nologin velocite
```

| Propriété | Valeur | Raison |
|---|---|---|
| UID | 997 (< 1000) | compte système, pas humain |
| Shell | `/usr/sbin/nologin` | **aucune session interactive possible**, même après compromission |
| Répertoire personnel | absent | un service n'en a pas besoin |

### 2.2 Permissions des répertoires

Trois natures de données, trois politiques distinctes.

| Répertoire | Propriétaire | Mode | Justification |
|---|---|---|---|
| `/opt/velocite` | `root:velocite` | `750` | Le service **lit** le code sans pouvoir le modifier. Un attaquant ne peut pas installer de porte dérobée persistante. |
| `/etc/velocite` | `root:root` | `700` | Contient le mot de passe de production. **Même `velocite` n'y a pas accès.** |
| `/var/log/velocite` | `velocite:velocite` | `750` | Seul emplacement où le service écrit. Créé automatiquement par `LogsDirectory=`. |

```bash
sudo chown root:velocite /opt/velocite && sudo chmod 750 /opt/velocite
sudo chown root:velocite /opt/velocite/server.js && sudo chmod 640 /opt/velocite/server.js
sudo chown root:root /etc/velocite && sudo chmod 700 /etc/velocite
```

> **Note :** `server.js` est en `640`, sans bit d'exécution. Node **lit** le fichier, il ne l'exécute pas directement.

### 2.3 Configuration et secret

`/etc/velocite/velocite.env`, en `600` root :

```
PORT=3000
APP_NAME=velocite-storefront
LOG_LEVEL=info
LOG_DIR=/var/log/velocite
DB_PASSWORD=<secret>
```

**Pourquoi un fichier séparé plutôt que dans l'unit :** les fichiers d'unit vivent dans `/etc/systemd/system/`, répertoire en `755` lisible par tous. Un `systemctl cat velocite` exposerait le mot de passe à n'importe quel utilisateur de la machine.

**Pourquoi propriétaire root et non velocite :** `EnvironmentFile=` est lu par **systemd**, qui tourne en root, *avant* d'abaisser les privilèges vers `User=velocite`. Le compte de service ne touche jamais ce fichier — il reçoit les variables déjà injectées dans son environnement.

Vérification :
```bash
sudo -u velocite cat /etc/velocite/velocite.env   # → Permission denied
sudo -u nobody  cat /etc/velocite/velocite.env    # → Permission denied
```

Et pourtant l'application démarre avec `"dbPassConfigured":true`.

### 2.4 L'unit systemd

`/etc/systemd/system/velocite.service` :

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

#### Justification directive par directive

| Directive | Exigence traitée |
|---|---|
| `After=` / `Wants=network-online.target` | Le service attend que le réseau soit **réellement utilisable**, pas seulement configuré (`network.target` ne suffirait pas). |
| `StartLimitBurst=4` + `StartLimitIntervalSec=120` | Empêche la boucle infinie : 4 démarrages maximum par fenêtre glissante de 120 s. |
| `Type=simple` | Node reste au premier plan. `forking` provoquerait un timeout de 90 s puis un échec, alors que le service fonctionne. |
| `User=` / `Group=velocite` | Sans ces lignes, le service tournerait **en root**. |
| `EnvironmentFile=` | Secret hors de l'unit, voir 2.3. |
| `ExecStart=/usr/bin/node` | Chemin **absolu** obligatoire : systemd n'utilise pas le `PATH`. |
| `Restart=on-failure` | Redémarre après un crash, mais **respecte** un arrêt propre (code 0). `always` relancerait même un arrêt volontaire. |
| `RestartSec=5` | Sans délai (défaut 100 ms), un service qui échoue au démarrage saturerait le CPU. |
| `TimeoutStopSec=15` | L'application s'accorde 10 s pour finir ses requêtes. Une valeur inférieure la ferait tuer par `SIGKILL` avant la fin. |
| `UMask=0027` | Les fichiers créés par l'application arrivent en `640` (666 − 027). |
| `NoNewPrivileges=true` | Le processus ne peut **jamais** gagner de privilèges, même via un binaire SUID. |
| `PrivateTmp=true` | `/tmp` isolé des autres services. |
| `ProtectSystem=strict` | Tout le système de fichiers en **lecture seule**. |
| `ProtectHome=true` | `/home` et `/root` inaccessibles. |
| `LogsDirectory=velocite` | Crée `/var/log/velocite`, lui donne le bon propriétaire, et l'autorise en écriture **malgré** `ProtectSystem=strict`. Remplace 3 commandes manuelles + `ReadWritePaths=`. |
| `LogsDirectoryMode=0750` | Le mode par défaut serait `0755`. |
| `WantedBy=multi-user.target` | Sans cette section, `systemctl enable` échoue et le service ne repart pas au boot. |

> **`UMask=` vs `LogsDirectoryMode=` :** deux acteurs, deux moments. systemd crée le **répertoire** avant que le processus existe → `LogsDirectoryMode`. L'application crée le **fichier** pendant son exécution → `UMask`.

---

## 3. Preuves

### Avant / après

| Indicateur | Avant | Après |
|---|---|---|
| **Temps de reprise après crash** | 9 h 33 | **5,5 s** |
| Intervention humaine | nécessaire | aucune |
| Survie au redémarrage serveur | non | **oui** |
| Logs disponibles après incident | non (écrasés) | **oui** (journald, horodatés) |
| Identité du processus | `achraf` (humain) | `velocite` (système, sans shell) |
| Secret en clair accessible | oui | non |
| Requête coupée à l'arrêt | oui | non |

### Test 1 — Reprise après crash

```
19:58:55       produit introuvable, crash non gere
19:58:55       Main process exited, code=exited, status=1/FAILURE
19:59:00       Scheduled restart job, restart counter is at 1
19:59:00.521   storefront demarre
```

**MTTR mesuré : 5,5 s.** Soit `RestartSec=5` plus le temps de démarrage de Node.

### Test 2 — Protection anti-boucle

Cinq crashs successifs. Le compteur monte, puis :

```
20:01:19  Scheduled restart job, restart counter is at 6.
20:01:19  Start request repeated too quickly.
20:01:19  Failed to start velocite.service
```

**Comportement constaté : la limite s'applique à une fenêtre glissante, pas à un compteur absolu.**

```
19:59:00  ← hors fenêtre au moment du refus
20:00:57  ┐
20:01:03  │ 4 démarrages dans les
20:01:09  │ 120 dernières secondes
20:01:15  ┘
20:01:19  ← le 5e dans la fenêtre : REFUSÉ
```

Conséquence pratique : un service qui crashe une fois par heure ne sera jamais bloqué ; un service qui crashe en rafale l'est immédiatement.

### Test 3 — Arrêt propre

Requête sur `/lent` (8 s de traitement), redémarrage du service après 2 s.

**Résultat : `200`.** La requête s'est terminée normalement.

```
Stopping velocite.service...
"SIGTERM recu, arret en cours"
"arret termine"
Deactivated successfully.
```

Pas de `SIGKILL`, pas de connexion coupée.

### Test 4 — Redémarrage serveur

Arrêt complet (`wsl --shutdown`), puis redémarrage.

```bash
systemctl is-active velocite   # → active
systemctl is-enabled velocite  # → enabled
curl localhost:3000            # → le site répond
```

**Aucune commande de démarrage manuelle.**

### Test 5 — Confinement

```
systemd-analyze security velocite
→ Overall exposure level: 8.3 EXPOSED
```

Protections actives confirmées :
```
✓ User=/DynamicUser=      compte statique non-root
✓ NoNewPrivileges=        pas d'acquisition de privilèges
✓ AmbientCapabilities=    aucune capacité héritée
✓ ProtectSystem=          accès strictement en lecture seule
```

---

## 4. Exploitation courante

```bash
# État
systemctl status velocite            # vue complète
systemctl is-active velocite         # tourne-t-il maintenant ?
systemctl is-enabled velocite        # démarre-t-il au boot ?

# Cycle de vie
sudo systemctl start velocite
sudo systemctl stop velocite
sudo systemctl restart velocite

# Logs
journalctl -u velocite -n 50         # les 50 dernières lignes
journalctl -u velocite -f            # suivi en direct
journalctl -u velocite --since "10 min ago"
journalctl -u velocite -p err        # erreurs seulement

# Débloquer un service en échec
sudo systemctl reset-failed velocite
sudo systemctl start velocite

# Après TOUTE modification de l'unit
sudo systemctl daemon-reload
sudo systemctl restart velocite

# Journal d'audit applicatif
sudo tail -20 /var/log/velocite/audit.log
```

> ⚠️ **`daemon-reload` est obligatoire** après modification du fichier d'unit. systemd garde les units en mémoire : sans cette commande, il continue d'utiliser l'ancienne version et le débogage tourne à vide.

> ⚠️ **`reset-failed`** est nécessaire après un dépassement de `StartLimitBurst`. Passé 120 s, un simple `start` suffit — mais en astreinte, faire `reset-failed` systématiquement évite de se poser la question.

---

## 5. Diagnostic

### Méthode, dans l'ordre

| # | Étape | Commande |
|---|---|---|
| 1 | Lire le message exact | `systemctl status velocite` |
| 2 | **Lire les logs complets** | `journalctl -u velocite -n 50 --no-pager` |
| 3 | Vérifier la syntaxe de l'unit | `systemd-analyze verify /etc/systemd/system/velocite.service` |
| 4 | Vérifier que le binaire existe et est accessible | `ls -l /usr/bin/node` |
| 5 | Vérifier l'identité réelle du processus | `ps -eo user,pid,cmd \| grep server.js` |
| 6 | Vérifier les droits sur le chemin complet | `namei -l /chemin/fichier` |
| 7 | **Vérifier le sandboxing** | relire `ProtectSystem=`, `ProtectHome=`, `LogsDirectory=` |
| 8 | Vérifier qu'un `daemon-reload` a été fait | `systemctl status` signale le décalage |

> Le `status` donne l'**état**. Le `journalctl` donne la **cause**. Ne jamais s'arrêter au premier.

### Codes de sortie rencontrés

| Code | Signification | Cause réelle rencontrée |
|---|---|---|
| `203/EXEC` | systemd n'a pas pu exécuter le binaire | **`ProtectHome=true` masquait `/home`**, où se trouvait le node installé via nvm |
| `1/FAILURE` | l'application s'est arrêtée en erreur | faute de frappe dans le chemin : `server.j` au lieu de `server.js` |
| `217/USER` | l'utilisateur de `User=` n'existe pas | — |
| `200/CHDIR` | `WorkingDirectory=` inexistant | — |
| `127` | commande introuvable | chemin faux dans `ExecStart` |

### Le piège du `203/EXEC` — à retenir

Le binaire était accessible en permissions (`sudo -u velocite /home/achraf/.nvm/.../node --version` fonctionnait), mais le service échouait quand même.

**Cause : `ProtectHome=true` masque `/home` par un mécanisme de montage, indépendamment des permissions.** `sudo` n'applique aucun confinement ; systemd si.

**Solution retenue :** installer Node à un emplacement système (`/usr/bin/node`) plutôt que de retirer la protection.

**Pourquoi cette solution et pas l'autre :** un binaire applicatif dans le répertoire personnel d'un développeur crée une dépendance fragile. Si ce compte est supprimé — départ de l'entreprise — le service meurt. Si le développeur change de version Node pour un autre projet, la production casse sans prévenir.

---

## 6. Ce qui reste à faire

Cette solution corrige la **conséquence** de l'incident, pas sa cause. Limites connues :

| # | Limite | Impact |
|---|---|---|
| 1 | **Le bug applicatif n'est pas corrigé.** La route `/produit/404-fantome` fait toujours `process.exit(1)`. | Le site redémarre en 5 s au lieu de rester mort 9 h, mais il tombe toujours. Un visiteur qui rafraîchit en boucle peut déclencher la limite anti-boucle et mettre le service en `failed`. |
| 2 | **Aucune alerte.** Personne n'est prévenu quand le service tombe ou passe en `failed`. | Un `failed` à 3 h du matin reste invisible jusqu'au lendemain. |
| 3 | **Aucune supervision.** Pas de métriques, pas de dashboard, pas de SLO. | Impossible de savoir si le service a crashé 2 ou 50 fois cette semaine. |
| 4 | **Un seul serveur.** Pas de redondance. | Une panne matérielle ou une maintenance système = site indisponible. |
| 5 | **Node 18.19.1** (version Ubuntu) au lieu d'une version maîtrisée. | Écart de 6 versions majeures avec la version de développement (24.21.0). Risque de divergence de comportement. À remplacer par le dépôt NodeSource. |
| 6 | **Confinement perfectible** (8.3 EXPOSED). | `PrivateDevices=true`, `RestrictSUIDSGID=true` et `LockPersonality=true` feraient baisser le score sans rien casser. |
| 7 | **Pas de rotation des logs applicatifs.** `audit.log` grossit indéfiniment. | Risque de saturation disque à long terme. À traiter avec logrotate ou en écrivant sur stdout. |
| 8 | **Déploiement manuel.** Aucun pipeline. | Chaque mise à jour du code se fait à la main, avec le risque d'erreur que ça implique. |

**Priorité recommandée :** 1 (corriger le bug), puis 2 (alerter), puis 8 (automatiser le déploiement).

---

## Annexe — Vérification complète

```bash
# Identité
ps -eo user,pid,cmd | grep server.js        # → velocite

# Permissions
sudo ls -ld /opt/velocite /etc/velocite /var/log/velocite
sudo ls -l /etc/velocite/velocite.env       # → -rw------- root root

# Secret inaccessible
sudo -u velocite cat /etc/velocite/velocite.env   # → Permission denied

# Service
systemctl is-active velocite                # → active
systemctl is-enabled velocite               # → enabled
curl localhost:3000/health                  # → JSON uptime + requests

# Journal d'audit
sudo tail -5 /var/log/velocite/audit.log

# Durcissement
systemd-analyze security velocite | tail -3
```