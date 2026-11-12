# GCP — Pub/Sub

> Fiche du 11/11 (semaine 5, jour 2), écrite après le QCM du 12/11 (15/15).
> Lab **GSP644** *Build a Serverless App with Cloud Run that Creates PDF Files* : 100/100.
> ⚠ = raté réel à l'oral.

---

## 1. Le besoin

Quand une tâche est créée, il faut aussi envoyer un e-mail, générer une miniature, mettre à jour des stats.
L'API faisait tout elle-même, dans l'ordre, **avant de répondre**.

## 2. Les défis : le couplage

| Défi | Conséquence |
|---|---|
| Pannes liées | l'e-mail tombe → la **création de la tâche** échoue |
| Lenteur cumulée | l'utilisateur attend **tous** les traitements |
| Évolution coûteuse | un nouveau traitement = **modifier l'API** |

## 3. Le principe

L'API **enregistre** la tâche, **dépose un message** dans une boîte et **répond tout de suite**.
Chaque traitement reçoit **sa copie** et la traite quand il peut, puis **confirme**.
Tant qu'il n'a pas confirmé, sa copie **attend**. Un nouveau traitement = un nouveau lecteur, sans toucher à l'API.

## 4. La solution : Pub/Sub

« senders of messages are **decoupled** from the receivers of messages »

| Terme | Rôle | Exemple |
|---|---|---|
| Publisher | publie dans un topic | l'API |
| **Topic** | le flux de messages : **l'événement** | `task-created` |
| **Subscription** | un abonnement à un topic : **un par traitement** | `email`, `miniature`, `stats` |
| Subscriber | reçoit les messages d'une subscription | le service d'e-mail |
| Acquittement | « j'ai traité ce message » | supprimé quand **toutes** les subscriptions ont acquitté |

```
                               ┌─ subscription email      ──▶ service d'e-mail
API ──▶ topic « task-created » ├─ subscription miniature  ──▶ service de miniatures
                               └─ subscription stats      ──▶ service de stats
```

> ⚠ **Un topic décrit ce qui s'est passé, pas qui doit réagir** (j'avais dit « 3 topics »).
> Fan-out : un topic, plusieurs subscriptions, chacune reçoit **les mêmes** messages.

### Livraison en double → idempotence

Si l'acquittement se perd, Pub/Sub considère le message **non traité** et le **renvoie** :
« might be delivered more than once ». Un abonné doit donc être **idempotent**
(traiter deux fois = même résultat ; le contraire de `echo >>`, semaine 1).

### Pull ou push

| | Pull | Push |
|---|---|---|
| Qui lance l'échange | l'**abonné** vient demander | **Pub/Sub** appelle une URL |
| Service Cloud Run à zéro instance | ❌ personne pour demander | ✅ l'appel le **réveille** |

## Lab GSP644 — la chaîne mesurée

```
facture.docx ─▶ bucket -upload ─notification─▶ topic new-doc ─▶ subscription pdf-conv-sub
                                                                     │ push (POST, « APIs-Google »)
                                                                     ▼
                                     Cloud Run pdf-converter (LibreOffice, 2 Gio) ─▶ bucket -processed : PDF
```

| Mesuré | Ce que ça montre |
|---|---|
| `notifications create -t new-doc … -e OBJECT_FINALIZE` a **créé le topic** | un fichier fini d'envoyer publie un événement |
| ligne `file:` : `name`, `bucket`, `generation`, `storageClass` | le message dit **quel fichier** traiter |
| `POST 200` depuis `APIs-Google` | c'est **Pub/Sub** qui appelle, en push |
| curl anonyme **403**, curl avec jeton **OK** | `--no-allow-unauthenticated` : **IAM** bloque, pas le pare-feu |
| `roles/run.invoker` sur **le service seul** | moindre privilège pour le compte invoker |
| révisions `00001` (par le lab), `00002`, `00003` · **même URL** | un service garde une adresse stable |
| Cloud Build 1 min 01, puis 5 min 34 avec LibreOffice | image construite dans le cloud, rangée dans Artifact Registry |
| `/tmp` = « an in-memory filesystem » | les fichiers consomment la mémoire → 2 Gio |
| l'original n'est supprimé **qu'après** le dépôt du PDF | une conversion ratée ne perd pas le fichier |

### IAM de la chaîne

- compte **`pubsub-cloud-run-invoker`** : `roles/run.invoker` sur le service ; Pub/Sub appelle **en son nom**
- **agent de service** Pub/Sub `service-<NUM>@gcp-sa-pubsub…` : selon la doc, il « needs to have »
  `iam.serviceAccountTokenCreator`
- ❓ **Question ouverte** : ce rôle n'apparaissait ni sur le projet ni sur le compte invoker ; les dossiers et
  l'organisation au-dessus étaient illisibles. Héritage = hypothèse, **non vérifiée**.

```bash
gcloud builds submit --tag gcr.io/$GOOGLE_CLOUD_PROJECT/pdf-converter
gcloud run deploy pdf-converter --image gcr.io/$GOOGLE_CLOUD_PROJECT/pdf-converter --region us-central1 \
  --memory=2Gi --no-allow-unauthenticated --max-instances=1 --set-env-vars PDF_BUCKET=<bucket>
gcloud storage buckets notifications create -t new-doc -f json -e OBJECT_FINALIZE gs://<bucket>
gcloud pubsub subscriptions create pdf-conv-sub --topic new-doc \
  --push-endpoint=$SERVICE_URL --push-auth-service-account=<compte invoker>
gcloud run revisions list --service pdf-converter --region us-central1
curl -X POST -H "Authorization: Bearer $(gcloud auth print-identity-token)" $SERVICE_URL
```

---

Sources : [Overview of the Pub/Sub service](https://docs.cloud.google.com/pubsub/docs/pubsub-basics) ·
[Subscription overview](https://docs.cloud.google.com/pubsub/docs/subscription-overview) ·
[Authentication for push subscriptions](https://docs.cloud.google.com/pubsub/docs/authenticate-push-subscriptions)
