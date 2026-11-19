# Docker Compose — PostgreSQL 18 dans la pile task-manager-api (jalon J2, bloc 1)

> Fiche du 18/11 (semaine 6, jour 1), écrite après le QCM du 19/11 : **19/19 (100 %)**, confirmé par 3 questions ouvertes (3/3).
> ⚠ = raté réel du 18/11 · ⚠⚠ = erreur qui coûte des données ou bloque le déploiement.
> Chiffres : mes sorties du 18/11. Livré : PR n° 10 fusionnée (`main` = `f20e500`).

---

## Les paires à ne pas inverser

| | | |
|---|---|---|
| **`.env` à la racine** : sert à **l'interpolation** de `compose.yaml` | ↔ | **`environment:`** : ce que le conteneur **reçoit** vraiment |
| **Init** de postgres : seulement sur un dossier de données **vide** | ↔ | **Redémarrage** avec volume plein : rien n'est refait (mot de passe compris) |
| **postgres 18+** : volume sur `/var/lib/postgresql` | ↔ | **postgres ≤ 17** : volume sur `/var/lib/postgresql/data` |
| **`postgres:18`** (version fixée) : change quand **je** le décide | ↔ | **`postgres:latest`** : change au prochain `pull` |
| **Build** : `DATABASE_URL` absente **tolérée** (`?? ''`) | ↔ | **Démarrage** : absente **refusée** (Zod `min(1)`) |
| **`env("DATABASE_URL")`** : lève une erreur si absente | ↔ | **`process.env.DATABASE_URL ?? ''`** : chaîne vide, pas d'erreur |
| **`127.0.0.1:5432:5432`** : seule ma machine | ↔ | **`5432:5432`** : toutes les interfaces, réseau local compris |
| **`docker compose down`** : conteneurs et réseau supprimés, **volume gardé** | ↔ | **`down -v`** : volume supprimé, **données perdues** |

---

## 1. Le service postgres

```yaml
postgres:
  image: postgres:18
  ports:
    - "127.0.0.1:5432:5432"
  environment:
    POSTGRES_USER: ${POSTGRES_USER:?à définir dans .env}
    POSTGRES_DB: ${POSTGRES_DB:?à définir dans .env}
    POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?à définir dans .env}
  volumes:
    - postgres-data:/var/lib/postgresql
  healthcheck:
    test: ["CMD", "pg_isready", "-U", "${POSTGRES_USER}", "-d", "${POSTGRES_DB}"]
```

- **Version fixée** (`18`) : j'ai dérivé seul que `latest` changerait le chemin. En 18+, les données sont dans
  `/var/lib/postgresql/18/docker`. Une version 19 utiliserait un autre dossier → base vide (**je déduis**, non mesuré).
- ⚠⚠ **Volume** : en 18+, on monte `/var/lib/postgresql`. En ≤ 17, c'est `/var/lib/postgresql/data`, sinon « WILL NOT PERSIST ».
  > ⚠ J'ai d'abord lu la phrase de `POSTGRES_INITDB_WALDIR` au lieu de celle de PGDATA.
- **Init** (utilisateur, base, mot de passe, `/docker-entrypoint-initdb.d`) : « only run if » le dossier de données est vide.
  > ⚠ J'ai appelé ça « idempotence ». C'est le **volume** plus une init **conditionnelle**.
- `POSTGRES_PASSWORD` : seule variable obligatoire, « must not be empty ». Utilisateur par défaut `postgres`, base par défaut = l'utilisateur.
- `pg_isready` : **mesuré** (healthy) ; la page de l'image n'en parle pas.

### Mot de passe changé après le premier démarrage (contrôle du 19/11)

Le volume est plein → la base garde l'**ancien** mot de passe, le backend reçoit le **nouveau** dans `DATABASE_URL` → connexion refusée.

| Option | Perte |
|---|---|
| Remettre l'ancien mot de passe dans `.env` | aucune |
| Changer le mot de passe en SQL dans la base | aucune |
| `docker compose down -v` puis `up` (réinitialisation) | ⚠⚠ **toutes les données** |

---

## 2. Les secrets : `.env` ↔ `environment:`

- `.env` à la racine : « made available for interpolation ». Il **n'entre pas** dans les conteneurs tout seul.
- « A container's environment is not set until there's an explicit entry » → `environment:` (ou `env_file:`, non utilisé ici).
- `${VAR:?message}` : variable absente ou vide → compose « exit with error » avec le message. Un collègue sans `.env` est arrêté net.
- `.env` **non commité** · mot de passe généré, jamais inventé :

```bash
openssl rand -hex 24      # 24 octets → 48 caractères hexadécimaux
chmod 600 .env
```

---

## 3. Prisma 7 avec PostgreSQL

- Adaptateur : `@prisma/adapter-pg` installé d'abord en **7.10.1** → **aligné sur 7.1.0**, comme Prisma (une chose à la fois).
- Changer de fournisseur (SQLite → PostgreSQL) : « You cannot automatically switch database providers » → `git rm` des anciennes
  migrations, puis `migrate dev` sur une base vide → `20261118174910_init`.
- `migrate dev` lancé dans un **sous-shell**, sans mot de passe dans l'historique, via le port `127.0.0.1:5432`.
- ⚠⚠ **`env("DATABASE_URL")` dans `prisma.config.ts`** : lève une erreur si la variable manque, et le Dockerfile lance
  `npx prisma generate` **sans** `DATABASE_URL` → **le build échoue**.
  > ⚠ Je l'avais dérivé moi-même, puis je l'ai quand même réécrit. Correct : `url: process.env.DATABASE_URL ?? ''`.
  > `prisma generate` sans URL : **passe** (mesuré).
- Au démarrage, Zod `z.string().min(1)` refuse la chaîne vide (⚠ double virgule corrigée).
- Prisma 7 « does not load .env files by itself ».

---

## 4. Ce que j'ai mesuré (18/11)

```
postgres         healthy (pg_isready) · 127.0.0.1:5432->5432/tcp
migrate          Exited (0)
psql \dt         tables de la migration présentes
POST puis down / up    même id → données conservées par le volume
tsc --noEmit     sans erreur
```

Commits : `373cf37` feat(db) · `877f3a3` docs(readme) (j'avais prédit « compose s'arrête, POSTGRES_USER à définir ») · PR n° 10 avec description,
fusionnée.

## Dette notée, non corrigée

`SQLiteTaskRepository` : un nom qui ne correspond plus · le Dockerfile crée encore `/app/data` · volume `sqlite-data` orphelin
(le supprimer : ma décision) · branche `feat/postgres` non supprimée · `npm audit` : 41 vulnérabilités (ne pas utiliser `--force`).
