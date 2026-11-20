# Docker Compose — émulateur Pub/Sub dans la pile task-manager-api (jalon J2, bloc 2)

> Fiche du 19/11 (semaine 6, jour 2), écrite après le QCM du 20/11 : **19/20 (95 %)**, raté = clic confirmé, contrôle ouvert **3/3**.
> Items 46 et 47 justes au QCM en cas nouveaux (J+1).
> ⚠ = raté réel du 19/11 · ⚠⚠ = erreur qui casse la pile sans message clair.
> Chiffres : mes sorties du 19/11. Livré : PR n° 11 fusionnée (`main` = `994072a`).
> Sources : *Testing apps locally with the emulator* (docs.cloud.google.com/pubsub/docs/emulator) · README de
> GoogleCloudPlatform/cloud-sdk-docker — lues par Claude, résumées sur la page Fil S6.

---

## Les paires à ne pas inverser

| | | |
|---|---|---|
| **`ports:`** : ouvre un conteneur vers **ma machine** | ↔ | **Adresse d'écoute** (`0.0.0.0`, pas `127.0.0.1` ni `::1`) : ce qui compte **entre conteneurs** |
| **`docker compose down`** : conteneurs et réseau supprimés, **volume nommé gardé** | ↔ | **`down -v`** : volumes supprimés, données perdues |
| **`.env` à la racine** : interpolation de `compose.yaml` | ↔ | **`environment:`** d'un service : ce que **ce** conteneur reçoit, et lui seul |
| **`docker compose config` passe** : le fichier est **valide** | ↔ | **`printenv` dans le conteneur** : la config est **juste** |
| **1 topic** = l'événement (`task.created`) | ↔ | **1 subscription par traitement** (`notif`, demain `analytics`) |

---

## 1. Le service pubsub, tel que livré

```yaml
pubsub:
  image: gcr.io/google.com/cloudsdktool/google-cloud-cli:594.0.0-emulators
  command: gcloud beta emulators pubsub start --project=task-manager-local --host-port=0.0.0.0:8085

backend:
  environment:
    PUBSUB_EMULATOR_HOST: pubsub:8085
    PUBSUB_PROJECT_ID: task-manager-local
```

- Version **mesurée avant d'être fixée** : `gcloud version` → **594.0.0**, `pubsub-emulator 0.8.38`.
- Image lourde : **1,69 Go** sur disque / 444 Mo.
- Le projet peut être un nom inventé : il « doesn't need to represent a real Google Cloud project ».
- `PUBSUB_EMULATOR_HOST` définie → la bibliothèque client Node appelle l'émulateur, sans changer le code.

## 2. Ce que j'ai mesuré

| Réglage | Log / résultat | Conclusion |
|---|---|---|
| sans `--host-port` | `--host=localhost --port=8085` · test TCP depuis le backend → **`ECONNREFUSED`** | n'écoute que pour son propre conteneur |
| `--host-port=0.0.0.0:8085` | `--host=0.0.0.0` → **`connecté`** | joignable par le nom `pubsub` depuis le backend |
| variables dans le service **postgres** | `docker compose config` OK | ⚠ valide ≠ juste : postgres les reçoit, le backend non |
| variables dans le backend | `printenv PUBSUB_EMULATOR_HOST` → `pubsub:8085` | vérifié dans le conteneur |
| smoke test (`scripts/pubsub-smoke-test.js`, `node:24-slim` jetable sur `task-manager-api_default`) | topic `task.created` + subscription `notif` · messageId **2** reçu | publié puis reçu, de bout en bout |
| log de l'émulateur | « IAM integration is disabled » | les droits ne se testent pas ici |

- ⚠ **47** : « ça marche, 8085 est publié automatiquement » → non. Sans `ports:`, rien n'est publié vers ma machine, et ce n'est pas
  le sujet : entre conteneurs, il faut que l'émulateur **écoute** sur `0.0.0.0`.
- ⚠ **46** : « `down` supprime toujours les volumes nommés » → non (mesuré le 18/11 : même id après `down` / `up`). Seul `down -v`
  les supprime. La perte de données du module PostgreSQL venait du **chemin** en `postgres:17` (`/var/lib/postgresql/data`).
- ⚠ Variables placées dans `postgres` → trouvé seul : « postgres les reçoit, le backend ne trouvera pas l'émulateur ».

## 3. Commandes utiles

```bash
cd ~/projects/task-manager-api
docker run --rm gcr.io/google.com/cloudsdktool/google-cloud-cli:emulators gcloud version   # mesurer avant de fixer
docker compose logs pubsub | grep Executing                                                # adresse d'écoute réelle
docker compose exec backend printenv PUBSUB_EMULATOR_HOST                                  # ce que le conteneur reçoit
```

## 4. Limites de l'émulateur (lues)

- Pas d'IAM (« IAM operations are not supported »).
- Pas de console ni de `gcloud pubsub` : topics et subscriptions se créent avec la **bibliothèque client**.
- Messages gardés indéfiniment, subscriptions sans expiration : différent de la production.
- Écoute par défaut sur le port 8085 du **localhost IPv6 (`::1`)**.

## 5. Dette notée, non corrigée

- Pas de healthcheck sur `pubsub` (`service_started` seulement).
- `MetadataLookupWarning` de la bibliothèque hors GCP : cause **déduite**, non lue.
- L'émulateur garde-t-il ses topics après un redémarrage du conteneur ? **Non lu** → à mesurer au bloc 3.
- Branches `feat/postgres` et `feat/pubsub-emulator` fusionnées, non supprimées.
