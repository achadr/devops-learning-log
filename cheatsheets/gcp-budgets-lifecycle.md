# GCP — Budgets de facturation, cycle de vie Cloud Storage, lab ARC101

> Fiche du 16/11 (semaine 5, jour 5), écrite après le QCM (17/18, 94 %).
> Lab **ARC101** *Monitor and Manage Google Cloud Resources: Challenge Lab* : 100/100.
> ⚠ = raté réel du jour · ⚠⚠ = erreur qui coûte de l'argent.

---

## Les paires à ne pas inverser

| | | |
|---|---|---|
| **Budget** : prévient, ne coupe rien | ↔ | **Spend cap** : met en pause, mais seulement les services éligibles (API Gemini, projet unique) |
| **Actual** : dépense déjà faite | ↔ | **Forecasted** : dépense prévue à la fin de la période (impossible en période personnalisée) |
| **E-mail** : pour des personnes, sortie par défaut | ↔ | **Pub/Sub** : pour des programmes (couper, Slack) |
| **Règle d'alerte Monitoring** : une métrique (instances, latence) | ↔ | **Budget** : l'argent |
| Dans **une** règle de cycle de vie : **toutes** les conditions (ET) | ↔ | Entre **plusieurs** règles de même action : **une seule** suffit (OU) |
| Changement de classe par **cycle de vie** : le temps passé compte | ↔ | Par **script** (réécriture) : le compte repart, et frais de lecture |
| **Règle de cycle de vie** : objets actuels **et** futurs | ↔ | **Métrique de journaux / sink** : seulement après la création (item 44) |
| **Max instances** : instances **simultanées** | ↔ | Nombre d'**exécutions** : pas limité |
| ⚠ Métrique **système** (Google) : compteur, parfois booléen | ↔ | Métrique **utilisateur** (moi) : compteur ou **distribution** |
| `…-compute@developer` = **compte par défaut** | ↔ | `service-…@gs-project-accounts` = **agent de service** |

---

## 1. Budgets de facturation

**Besoin** : ne pas découvrir une dépense sur la facture.

**Défis** (trouvés par moi) : la dépense se voit **après coup** · il faut que quelqu'un **aille regarder** (les journaux montrent des requêtes, pas des euros) · une alerte **au montant maximal arrive trop tard**.

**Principe** : un montant fixé à l'avance, **plusieurs paliers** où le système prévient, et une **action** pour couper.

**Solution : les budgets Cloud Billing**
- ⚠⚠ « doesn't automatically cap » : un budget **n'arrête rien**.
- Seuils par défaut **50 %, 90 %, 100 %**, sur la dépense réelle (*Actual*). Un seuil peut dépasser 100 % (exemple de la doc : 110 % en prévision).
- Périodes : mensuelle (par défaut), trimestrielle, annuelle, ou personnalisée (non récurrente).
- *Forecasted* : « calculated out to the end of the current calendar budget period ». **Impossible pour une période personnalisée.** La raison n'est pas écrite.
- E-mail par défaut : administrateurs et utilisateurs du compte de facturation (propriétaires du projet pour un budget d'un seul projet). Autres destinataires : via Cloud Monitoring.
- Pub/Sub : « programmatic notifications », exemple de la doc : « disabling Cloud Billing on a project ».

> ⚠ J'avais dit « saturation de mémoire » : sur Cloud Run, la plateforme **ajoute des instances** jusqu'au max. Le problème, c'est le coût.
> ⚠ J'avais proposé **un seul seuil** au montant maximal : l'alerte arrive quand c'est déjà dépensé.

### Couper automatiquement

```
budget ──▶ topic Pub/Sub ──┬─▶ fonction « coupe »  (désactive la facturation du PROJET)
                           └─▶ fonction « Slack »  (2ᵉ abonnement, item 42)
```

- ⚠ L'**e-mail ne passe pas par Pub/Sub** : un seuil sur le budget suffit.
- ⚠ Le topic est relié **au budget**, pas à un seuil : messages « multiple times per day », même à 4 €. C'est le **code** de la fonction qui compare au budget.
- Le rôle exact du compte de service de la fonction : **non lu**.

### Spend caps

- « automatically paused for the remainder of the budget period unless you manually lift the spend cap »
- Services éligibles : **API Gemini** (« In this release ») · budget sur **un seul projet**.
- Une VM Compute Engine **continue** : elle n'est pas éligible.

Sources : [Create, edit, or delete budgets](https://docs.cloud.google.com/billing/docs/how-to/budgets) ·
[Manage spend cap budgets](https://docs.cloud.google.com/billing/docs/how-to/budgets-spend-caps)

---

## 2. Cycle de vie Cloud Storage (Object Lifecycle Management)

**Besoin** : des pièces jointes lues souvent, puis presque jamais après 3 mois, inutiles après 2 ans.

**Défis** : les objets vieillissent **chaque jour** (200 000 à trier en permanence) · les **durées minimales** (Nearline 30 j, Coldline 90 j, Archive 365 j) · ⚠⚠ un **script réécrit** les objets : le compteur repart, et on paie des frais de lecture.

**Principe** (trouvé par moi) : des règles « **quand** (condition) → **alors** (action) » posées **sur le bucket**, que Cloud Storage applique seul.

**Solution**
- Une règle = **une action** + **une ou plusieurs conditions**.
- Actions : `Delete`, `SetStorageClass`, `AbortIncompleteMultipartUpload`.
- Conditions : `age`, `createdBefore`, `isLive`, `numNewerVersions`, `matchesStorageClass`, `matchesPrefix` / `matchesSuffix`, `daysSinceNoncurrentTime`.
- **Delete l'emporte** sur SetStorageClass.
- Objets **actuels et futurs** · effet sous **24 h** au plus.
- SetStorageClass « does not rewrite an object » · pas de frais de lecture ni de suppression anticipée pour le changement lui-même · « time spent set at the original storage class counts » vers la durée minimale de la nouvelle classe.
- ⚠ Un objet courant supprimé passe d'abord en **suppression réversible, 7 jours par défaut** (j'avais dit deux fois « définitivement »).

### Le cas du script (mon raté)

Objet Standard au jour 0, Coldline au jour 30, supprimé au jour 60 :

| Passage en Coldline fait par… | Jours facturés « comme si » |
|---|---|
| une **règle de cycle de vie** | 30 (90 − 60 depuis la création) |
| ⚠ un **script** qui réécrit | 60 (le compte repart au jour 30, d'après l'exemple de la page) |

### Règles de task-manager

| Règle | Condition | Action |
|---|---|---|
| 1 | `age` 90 j | SetStorageClass → **Coldline** |
| 2 | `age` 730 j | Delete |

Coldline sans frais de suppression anticipée : **640 jours** en Coldline, bien plus que 90 (et le temps passé en Standard compte aussi).

> Non vérifié : si une suppression par la règle Delete **avant** la durée minimale paie des frais. La phrase générale existe, mais la section Delete ne la cite pas. Que Coldline facture la lecture plus cher que Nearline : non lu.

Source : [Object Lifecycle Management](https://docs.cloud.google.com/storage/docs/lifecycle)

---

## 3. Lab ARC101 — ce qui a été mesuré

Région `us-east4` · bucket `travel-bucket-qwiklabs-gcp-04-72ad748da18e` · topic `travel-topic-372` ·
fonction `travel-thumbnail-creator` (2ᵉ génération, Node.js 22, point d'entrée `thumbnail`).

| Mesuré | Ce que ça montre |
|---|---|
| bucket en `US-EAST4` grâce à `--location` | item 37 |
| `projects add-iam-policy-binding` **refusé** pour d'autres rôles que celui de la tâche 1 | le lab limite les rôles attribuables (déduit, non vérifié) |
| agent Storage « does not exist » juste après l'activation des API | agent pas encore créé (déduit) |
| erreur Eventarc « may take a few minutes » → réussite au 2ᵉ essai | délai de propagation après activation de l'API |
| `eventType: google.cloud.storage.object.v1.finalized` | « à chaque objet créé » |
| journaux : « lacks {run.routes.invoke} » → aucune miniature | ⚠ le push vers Cloud Run exige **`roles/run.invoker`** (comme le 403 de GSP644) |
| `roles/run.invoker` **sur le service** pour le compte du déclencheur → miniatures créées | corrigé au niveau du service, pas du projet |
| abonnement `eventarc-…-sub` en **push** vers l'URL `run.app` | Eventarc branche topic + abonnement à ma place |
| `travel.jpg`, refusé deux fois, a quand même sa miniature | renvoi du message non acquitté : **hypothèse** (`retryPolicy: RETRY_POLICY_DO_NOT_RETRY` non expliqué) |
| la miniature redéclenche la fonction → « already has a thumbnail » | ⚠⚠ boucle évitée par un seul test sur le nom |
| `maxInstanceCount: 5` | limite les instances simultanées, pas la boucle |
| e-mail reçu : « above threshold of 0 with a value of 0.6 » | preuve par le résultat ; 0,6 = moyenne sur 5 min (ma lecture des réglages) |
| compte par défaut pour la fonction **et** le déclencheur | en production : compte dédié, moindre privilège |
| image de test : **908 993 octets** (887,7 Kio) | un vrai fichier, pas une page d'erreur |

> ⚠ Pour la fonction, j'ai d'abord justifié « événementielle » par « elle s'exécute en réaction à un événement ». Le critère : **personne n'attend de réponse** (item 43, retrouvé en 3 questions).
> ⚠ Condition d'alerte = **métrique + seuil + durée**, pas la métrique seule.
> Point ouvert : aucune ligne `published` dans les journaux. Le topic n'a pas d'abonnement, donc impossible de vérifier : seuls les messages publiés **après** la création d'un abonnement sont disponibles.

```bash
gcloud storage buckets create gs://$BUCKET --location=$REGION
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="user:$USER2" --role="roles/storage.objectViewer" --condition=None
gcloud projects get-iam-policy $PROJECT_ID --flatten="bindings[].members" \
  --filter="bindings.role:roles/storage.objectViewer" --format="table(bindings.role, bindings.members)"
gcloud pubsub topics create $TOPIC
gcloud functions deploy $FUNCTION --gen2 --runtime=nodejs22 --region=$REGION \
  --source=. --entry-point=thumbnail --trigger-bucket=$BUCKET
gcloud run services add-iam-policy-binding $FUNCTION --region=$REGION \
  --member="serviceAccount:<PROJECT_NUMBER>-compute@developer.gserviceaccount.com" --role="roles/run.invoker"
gcloud storage cp ~/travel.jpg gs://$BUCKET/travel2.jpg
gcloud functions logs read $FUNCTION --region=$REGION --limit=40
gcloud pubsub subscriptions list --format="table(name.basename(), topic.basename(), pushConfig.pushEndpoint)"
```

---

## 4. Métriques basées sur les journaux (item 45, relu par moi le 16/11)

> « Most system-defined log-based metrics are counters, but some are of the boolean type. »
> « User-defined log-based metrics can be of the counter or distribution metric types. »

⚠ Q17 : j'ai répondu « système, compteur ou distribution » (même erreur qu'à l'oral le matin).
**Une distribution, c'est toujours moi qui la crée.**

Source : [Log-based metrics](https://docs.cloud.google.com/logging/docs/logs-based-metrics), section *Data types for log-based metrics*
