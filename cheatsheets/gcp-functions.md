# GCP — Cloud Run functions et Eventarc

> Fiche du 13/11 (semaine 5, jour 4), écrite après le QCM du 16/11 (13/13).
> Lab **GSP092** *Monitoring and Logging for Cloud Run Functions* : 100/100.
> ⚠ = raté réel à l'oral.

---

## 1. Le besoin

Pour le convertisseur de GSP644, il a fallu un Dockerfile, `npm install`, Cloud Build, Artifact Registry,
un `gcloud run deploy`, puis toute la tuyauterie Pub/Sub. Pour un **petit traitement**, c'est beaucoup.

## 2. Les défis

| Défi | Pourquoi |
|---|---|
| Conteneurisation | Dockerfile, construction et dépôt de l'image : du travail sans rapport avec le traitement |
| Branchement | relier soi-même la source de l'événement au service (notification, topic, subscription push) |

## 3. Le principe

Je ne donne **que le code source** et **ce qui doit le déclencher**. Google construit, déploie et branche.

## 4. La solution : Cloud Run functions

- « lightweight functions that **run in Cloud Run** » : mise à zéro et facturation à l'usage comprises
- « Cloud Build then **automatically builds your code into a container image** » ; l'image est rangée dans
  **Artifact Registry**

### HTTP ou événementielle

| | **HTTP** | **Événementielle** |
|---|---|---|
| Déclenchée par | une requête HTTP(S) sur son URL | un événement du projet |
| Quelqu'un attend une réponse ? | **oui** | **non** |
| Exemples | formulaire de contact, webhook de paiement, `helloworld` du lab | facture déposée → PDF ; document Firestore créé → notification |

> ⚠ **Toute fonction « se déclenche »** : ce n'est pas le critère. Le critère : *quelqu'un attend-il une réponse ?*
> (j'avais dit « helloworld est événementielle, parce qu'elle se déclenche »).
> ⚠ Ne pas dire « job » pour un traitement : un **job** est une ressource Cloud Run (une tâche qui se termine).

### Eventarc

- « Google's implementation of the **CloudEvents** spec » : un format unique d'événement, quelle que soit la source
- toutes les fonctions événementielles reçoivent leurs événements par Eventarc
- sources vues : **Pub/Sub**, **Cloud Storage**, **Firestore**

```
fichier déposé ─┐
message publié ─┼─▶ Eventarc (CloudEvents) ─▶ fonction événementielle (sur Cloud Run)
document créé  ─┘

client (navigateur, vegeta) ── GET / POST ──▶ fonction HTTP ── réponse 200 ──▶ client
```

## Lab GSP092 — ce qui a été mesuré

| Mesuré | Ce que ça montre |
|---|---|
| éditeur intégré : aucun Dockerfile, aucune image construite par moi | Google conteneurise le code |
| ⚠ **5 mis au minimum** d'instances, corrigé en **maximum** | minimum 5 = 5 instances payées en permanence ; minimum 0 = mise à zéro |
| facturation *Request-based* | on ne paie que pendant le traitement des requêtes |
| `vegeta attack -rate=200` → graphique à **200/s** | `-rate` = débit par seconde, `-duration` = durée |
| métrique `CloudRunFunctionLatency-Logs`, type **distribution**, champ `httpRequest.latency` | une distribution garde la répartition des latences |
| ⚠ données seulement **après la création** de la métrique (j'avais dit « délai d'ingestion ») | une métrique **n'est pas rétroactive**, comme un sink |
| `logging/user/…` dans le nom | métrique **définie par l'utilisateur** |
| *Request_latency* = 6 métriques dans la console actuelle | le manuel était en retard sur l'interface |

### Métriques basées sur les journaux : deux axes à ne pas confondre

| Qui la définit | Types de valeur possibles |
|---|---|
| **Système** (Google) | compteur, parfois booléen |
| **Utilisateur** (moi) | compteur ou **distribution** |

> ⚠ J'avais répondu « compteur et distribution » à la question « les deux types » : c'est l'axe de la valeur.
> Le manuel demandait l'axe de **qui définit** : système / utilisateur.

```bash
curl -LO 'https://github.com/tsenart/vegeta/releases/download/v12.12.0/vegeta_12.12.0_linux_386.tar.gz'
tar -xvzf vegeta_12.12.0_linux_386.tar.gz
CLOUD_RUN_URL=$(gcloud run services describe helloworld --region=europe-west4 --format='value(status.url)')
echo "GET $CLOUD_RUN_URL" | ./vegeta attack -duration=300s -rate=200 > results.bin
```

---

Sources : [Write Cloud Run functions](https://docs.cloud.google.com/run/docs/write-functions) ·
[Function triggers](https://docs.cloud.google.com/functions/docs/calling) ·
[Build process overview](https://docs.cloud.google.com/functions/docs/building) ·
[Log-based metrics](https://docs.cloud.google.com/logging/docs/logs-based-metrics)
