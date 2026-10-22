# Docker — conteneuriser une application

> Fiche du 22/10 (semaine 2, jour 6). Projet : `task-manager-api`.
> Tous les chiffres viennent de tes captures. ⚠ = raté réel du jour · ⚠⚠ = erreur à coût réel.

---

## Les paires à ne pas inverser

| | | |
|---|---|---|
| **Machine virtuelle** | son propre noyau, complet | isolation par hyperviseur, démarrage en dizaines de secondes |
| **Conteneur** | ⚠ **le noyau de l'hôte**, partagé | un processus ordinaire + espaces de noms + cgroups |

| | | |
|---|---|---|
| **Image** | le modèle figé, produit par `docker build` | ce qu'on pousse sur un registre |
| **Conteneur** | le processus qui tourne à partir de l'image | ce qui a une adresse IP et un `localhost` à lui |

| | Quand ? | Résultat |
|---|---|---|
| **`RUN`** | au `docker build`, une fois | une couche figée dans l'image |
| **`CMD`** | à chaque `docker run` | un processus qui tourne · une seule par image |

| | Espace de noms | Conflit avec `velocite` sur 3000 ? |
|---|---|---|
| **Port du conteneur** | celui du conteneur, à lui seul | **non** · chaque conteneur a son propre 3000 |
| **Port publié** `-p hôte:conteneur` | celui de l'hôte | **oui** · `failed to bind host port 0.0.0.0:3000` |

> Ton réflexe du 3001 était juste, mais il appartient à `-p 3001:3000`, pas à `EXPOSE`.

| `.dockerignore` | Exemples | Conséquence |
|---|---|---|
| **Taille** | `node_modules`, `dist`, `coverage` | image lourde, builds lents, binaires de la mauvaise plateforme |
| **Fuite** | **`.env`, `data/`** | secrets et données lisibles par quiconque récupère l'image |

| | La question | Ton `/health` |
|---|---|---|
| **Vivacité** (*liveness*) | « le processus tourne-t-il ? » | ✅ c'est ce qu'il fait |
| **Préparation** (*readiness*) | « peut-il **servir** ? » (dépendances joignables) | ❌ renvoie 200 même base tombée · `/tasks` renvoie 503 |

⚠ **Les deux chemins** (inversés ce jour) :

| | Chemin |
|---|---|
| Ce que le **navigateur** envoie | `/api/tasks` |
| Ce que le **backend** connaît | `/tasks` |
| Sans barre finale dans `proxy_pass` | le backend reçoit `/api/tasks` → **404** |

⚠ **Les trois états de `trust proxy`** (Q19 ratée) :

| Réglage | `req.ip` derrière un nginx | Conséquence |
|---|---|---|
| **non réglé** (défaut) | l'IP de nginx (`172.18.0.3`) | Express **ignore** `X-Forwarded-For` · tout le monde a la même IP |
| **`true`** | la valeur **la plus à gauche** de `X-Forwarded-For` | ⚠⚠ écrite par le client → il la change à chaque requête et contourne le limiteur |
| **`1`** | l'adresse vue par nginx (`172.18.0.1` chez toi) | ✅ un intermédiaire sauté, ni plus ni moins |

> Règle : **le nombre exact de proxys de confiance.** Équilibreur GCP + nginx → `2`.

| Message côté client | Qui l'émet | Ce que ça prouve |
|---|---|---|
| **`Connection refused`** (111) | ⚠ **le noyau** de la machine visée, par un `RST` | aucun processus n'écoute sur ce port |
| **`Connection timed out`** | personne · le paquet a été jeté (`DROP`) | un filtrage sur le trajet |

> ⚠ nginx **reçoit** le `RST`, il ne l'émet pas : il est le client de cette connexion.

---

## 1. Un conteneur n'est pas une machine

Une image embarque **tout sauf le noyau** : système de fichiers, bibliothèques, binaire Node, dépendances, disposition des répertoires.

```bash
uname -r                                   # 6.6.87.2-microsoft-standard-WSL2
docker run --rm node:24-slim uname -r      # 6.6.87.2-microsoft-standard-WSL2  ← le même
```

Ce que l'image règle, et que « ça marche sur ma machine » ne règle pas :

```
1  disposition des répertoires   ../../../data depuis dist/infrastructure/database
2  version de Node               v24.21.0 chez toi
3  variables d'environnement     .env
4  fichier SQLite                data/tasks.sqlite
5  bibliothèques du système      @libsql/linux-x64-gnu → glibc → node:24-slim, PAS alpine
```

Tu connaissais déjà la technologie : `ProtectHome=true` dans `velocite` donnait au service un espace de noms où `/home` était vide. Docker fait la même chose pour tout, réseau compris.

---

## 2. Les couches et le cache

Chaque instruction produit une **couche**. Docker réutilise les couches jusqu'à **la première qui a changé**, et **invalide toutes celles qui suivent**.

> **Règle unique : de la moins changeante à la plus changeante.** `package.json` → `npm ci` → le code.

Ta mesure, après une ligne modifiée dans `app.ts` :

| | `RUN npm ci` | Total |
|---|---|---|
| A · `COPY . .` puis `npm ci` | refait : 13,1 s | **35,6 s** |
| B · `COPY package*.json`, `npm ci`, puis `COPY . .` | `CACHED` | **14,4 s** |

Le contexte de build envoyé au démon :

```
322,52 Mo   premier build, sans .dockerignore (node_modules de l'hôte compris)
  2,44 ko   build multi-étapes avec COPY ciblés
 11,52 ko   COPY . . avec .dockerignore
```

---

## 3. L'image du backend — construction en plusieurs étapes

**Seul ce qui est copié par `COPY --from=` arrive dans l'image finale.** Le reste de l'étape `builder` (compilateur, sources, `devDependencies`) est jeté.

```dockerfile
# ---------- étape 1 : construction ----------
FROM node:24-slim AS builder
WORKDIR /app
# NON VÉRIFIÉ : utile à la CLI Prisma ? (voir « Non vérifié »)
RUN apt-get update && apt-get install -y --no-install-recommends openssl \
    && rm -rf /var/lib/apt/lists/*
COPY package*.json ./
RUN npm ci
COPY prisma ./prisma
COPY prisma.config.ts ./
RUN npx prisma generate          # AVANT tsc : le code importe le client généré
COPY tsconfig.json ./
COPY src ./src
RUN npx tsc
RUN mkdir -p /app/data && chown -R node:node /app/data   # pour le service migrate

# ---------- étape 2 : exécution ----------
FROM node:24-slim AS runtime
WORKDIR /app
ENV NODE_ENV=production
COPY package*.json ./
RUN npm ci --omit=dev
COPY --from=builder /app/node_modules/.prisma ./node_modules/.prisma
COPY --from=builder /app/dist ./dist
RUN mkdir -p /app/data && chown -R node:node /app/data
USER node
EXPOSE 3000
CMD ["node", "dist/index.js"]
```

| | Disk usage | Content size |
|---|---|---|
| une seule étape | 1,6 GB | 376 MB |
| **plusieurs étapes** | **985 MB** | **252 MB** |

Ce qui sert en production : `node` et les `dependencies`. **Aucune des dix `devDependencies`.** ⚠ `@types/*` non plus : `dist/app.js` ne contient que des `require("express")`, `require("helmet")`… et aucun type.

`prisma` est dans `dependencies` → la CLI survit à `--omit=dev`. Ce qui manque à l'étape `runtime` pour migrer : `prisma/` et `prisma.config.ts`.

### Par défaut, un conteneur tourne en root

```bash
docker run --rm task-manager-backend ls -ld /app
# drwxr-xr-x 1 root root /app   → node n'a que r-x : il ne peut pas créer data/
```

D'où le `mkdir` + `chown` **en root, avant** `USER node`. Même réflexe que `User=velocite` en semaine 1.

### `.dockerignore`

```
node_modules
dist
.env
.env.*
data
.git
coverage
*.log
```

> ⚠⚠ **Le `.dockerignore` est une protection de secret.** `.env` est ignoré par git, **pas par Docker** : chaque outil a sa propre liste.

---

## 4. Le frontend et le relais nginx

`API_BASE = '/api'` est une **URL relative** : le navigateur l'envoie au serveur qui a servi la page. Le `proxy` de `vite.config.ts` n'existe qu'en développement. En production, sans relais : **404**.

```nginx
location /api/ {
    proxy_pass http://backend:3000/;   # la barre finale remplace /api/ par / → /tasks
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    # + Host, X-Real-IP, X-Forwarded-Proto
}
location / {
    root /usr/share/nginx/html;
    try_files $uri $uri/ /index.html;
}
```

Preuve dans ton journal nginx : `upstream: "http://127.0.0.1:3000/tasks"` → le `/api` a bien été retiré.

Image : `nginx:alpine` (aucun module natif) → **93,9 MB / 26,4 MB**.

---

## 5. `compose`

### Le DNS entre conteneurs

**Le nom du service est un nom de machine.** `http://backend:3000` fonctionne, `http://localhost:3000` non.

Trajet avec `localhost` (⚠ déroulé raté au QCM du 21/10, réussi aujourd'hui) :

```
nginx → 127.0.0.1:3000, dans SON espace de noms réseau
      → aucun processus n'y écoute (velocite est dans l'espace de l'hôte)
      → le noyau répond par un RST
      → nginx : connect() failed (111: Connection refused) → 502
```

### Les migrations : un service qui s'exécute et sort

| Où ? | Problème |
|---|---|
| A · dans le `Dockerfile` | la base serait figée dans l'image, puis **masquée** par le volume |
| B · au démarrage du backend | l'étape `runtime` n'a ni `prisma/` ni `prisma.config.ts` (TypeScript) |
| **C · service `migrate`** | ✅ étape `builder`, s'exécute, sort en `Exited (0)` · en Kubernetes : un `Job` |

`migrate deploy` ne réapplique pas une migration déjà appliquée : on peut le relancer à chaque `up`.

### `depends_on`

| | Garantit |
|---|---|
| `depends_on: - backend` | que le conteneur est **lancé** · pendant le démarrage de Node : **502** |
| `condition: service_healthy` | que la sonde a répondu (5,7 s chez toi avec `start_interval`) |
| `condition: service_completed_successfully` | que `migrate` est sorti en 0 |

### La sonde de santé

```yaml
healthcheck:
  test: ["CMD", "node", "-e", "fetch('http://127.0.0.1:3000/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"]
  interval: 30s        # /health est APRÈS le limiteur (100 req / 15 min, par IP)
  timeout: 3s
  retries: 3
  start_period: 15s
  start_interval: 3s   # Docker Engine 25+ (tu as 29.8.2)
```

`node:24-slim` n'a ni `curl` ni `wget`. Sous **9 s** d'intervalle, la sonde dépasse seule ses 100 requêtes → `429` → backend `unhealthy` → **le frontend ne démarre jamais**.

---

## 6. Vérifier le résultat, pas le message

Le test de migration, avant d'écrire le `compose` :

```bash
docker volume rm -f testvol                      # EN PREMIER : un échec au milieu sauterait la dernière ligne
docker build --target builder -t tmb ./backend
docker run --rm --user node -v testvol:/app/data tmb npx prisma migrate deploy
docker run --rm -v testvol:/app/data tmb ls -la /app/data   # → tasks.sqlite, 40960 octets, node
docker volume rm -f testvol
```

`All migrations have been successfully applied` ne dit **pas** où le fichier a atterri. Le `ls`, si.

> **Un message de réussite dit ce que l'outil croit avoir fait. Seule l'observation de l'effet, là où il compte, dit ce qui s'est passé.** *(formulé par toi)*

---

## 7. Frais, ou mémorisé ?

> *« À quel moment cet état a-t-il été capturé, et est-ce toujours le reflet de la réalité ? »* *(formulé par toi)*

| Instantané | Invalidation |
|---|---|
| `origin/main` · `up to date with 'origin/main'` | `git fetch` |
| cache DNS négatif | attendre le TTL du SOA |
| **volume nommé**, initialisé au premier montage seulement | `docker compose down -v` |
| le volume d'un **test** | `rm -f` en **première** ligne |
| **nginx** résout `backend` une seule fois, à son démarrage | relancer le frontend si le backend est recréé |
| ⚠ un **conteneur non recréé** après un build raté : le `curl` vert vient de l'ancienne pile | regarder `CREATED` dans `ps -a` · `--force-recreate` |
| `origin/<branche>` supprimée sur GitHub | `git fetch --prune` |

---

## 8. Le lockfile et `npm ci`

```
npm ci  can only install packages when your package.json and package-lock.json are in sync
Missing: @esbuild/linux-x64@0.25.12 from lock file   (+ toutes les plateformes esbuild / rollup)
```

Le lockfile commité du frontend omettait les variantes de plateforme. Correction sans changer de version :

```bash
(cd frontend && npm install --package-lock-only)
git diff --stat frontend/package-lock.json        # 753 ajouts, 0 retrait → aucune version modifiée
```

Lire un `--stat` : **ajouts sans retraits = des entrées manquantes**, pas une montée de version.

---

## 9. Le jalon

```bash
docker compose up -d --build
docker compose ps -a                 # migrate Exited (0) · backend (healthy) · frontend Up
curl -s localhost:8080/api/tasks
docker compose down && docker compose up -d
curl -s localhost:8080/api/tasks     # la tâche créée avant le down est toujours là
```

`down` supprime conteneurs et réseau, **pas le volume**. Livré par la PR n° 9 (`fd45c8b`), 9 fichiers, +888 lignes.

---

## ⚠ Les ratés de la reprise, à revoir

**Item 9 · entrée `DROP`, sortie `ACCEPT`** — raté pour la 2ᵉ fois, avec la même réponse.

```
SYN sortant            → ACCEPT (sortie)
SYN-ACK entrant        → vers un port éphémère, aucune règle ne l'autorise → DROP
curl                   → attend jusqu'au timeout
Correction             → règle à état en entrée : ESTABLISHED,RELATED → ACCEPT
```

⚠ Une **étiquette réseau GCP** ne bloque aucun port : elle **sélectionne les VM** auxquelles une règle de pare-feu s'applique. Elle n'a rien à voir avec ce cas. *(3ᵉ apparition de ce mot hors contexte.)*

**Item 2 · `502` et journaux vides** — l'ordre suit le trajet de la requête :

```
1  /var/log/nginx/error.log           qui a fabriqué le 502, et pourquoi
2  systemctl status · journalctl -k   le processus est-il vivant ? (OOM killer)
3  journalctl -u <service>            ce que l'application a écrit
```

---

## Dette notée, non corrigée

```
1   SQLite → PostgreSQL
2   DATABASE_URL       validé par Zod, ignoré par connection.ts
3   CORS_ORIGIN        lu directement dans process.env, contourne Zod
4   RATE_LIMIT_*       validés, et recodés en dur dans app.ts
5   PORT dans .env     le .env n'est lu par RIEN (ni dotenv ni --env-file) → tout le fichier est mort
6   /health            vivacité seulement · placé après le limiteur
7   origin:"*" + credentials:true   combinaison interdite par CORS
8   SQLiteTaskRepository           un nom qui mentira après la migration
9   pas de "engines" ni .nvmrc
10  nginx              résout backend une fois → relancer le frontend si le backend est recréé
11  arrêt du conteneur 3 Ctrl+C nécessaires : Node en PID 1 ne gère pas SIGINT
```

## Non vérifié

```
openssl dans l'étape builder   la migration réussit AVEC ; rien ne dit qu'elle échouerait SANS
tsx watch --env-file=.env      proposé pour le développement, non testé
colonnes DISK USAGE / CONTENT SIZE   interprétation déduite, non vérifiée
transfert de contexte réduit   déduit : BuildKit n'enverrait que les fichiers cités par COPY
```
