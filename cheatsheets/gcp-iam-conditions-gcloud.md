# GCP — conditions IAM, `gcloud` et types de comptes de service

> Fiche du 27/10 (semaine 3, jour 3). QCM : 15/20.
> ⚠ = raté réel du jour. Constats mesurés dans Cloud Shell sur `week3-sandbox` et `pfe-hti-2018`.

---

## Les paires à ne pas inverser

⚠ **Le compte par défaut et l'agent de service** (QCM Q14 : « géré par Google, exclusivement ») :

| | **Compte de service par défaut** | **Agent de service** |
|---|---|---|
| Exemple chez moi | `702970088800-compute@developer.gserviceaccount.com` | `service-702970088800@compute-system.iam.gserviceaccount.com` |
| Créé par | Google, à l'activation de l'API Compute Engine | Google |
| **Géré par** | **moi : contrôle total** | **Google**, pour agir sur mon projet |
| Dans la page IAM | visible s'il a un rôle | **masqué**, sauf « Inclure les attributions de rôles fournies par Google » |
| Mesuré dans `pfe-hti-2018` | **aucun rôle** | `roles/compute.serviceAgent` |

⚠⚠ **Le rôle que peut recevoir le compte par défaut** (QCM Q15 : « Propriétaire ») :
selon la configuration de l'organisation, il peut recevoir **automatiquement le rôle `Éditeur`**.
La documentation recommande de bloquer ce comportement avec la contrainte
`iam.automaticIamGrantsForDefaultServiceAccounts`, appliquée par défaut aux organisations créées
après le 3 mai 2024. → **ne pas l'utiliser, et vérifier qu'il n'a pas `Éditeur`.**

| | **`gcloud config set project`** | **`--project=`** |
|---|---|---|
| Modifie la configuration | **oui** : état mémorisé, qui survit au script | **non** |
| Après le script | les commandes suivantes visent le dernier projet configuré | rien n'a changé |
| Pour un script | ✗ | ✅ |

> Mesuré : après `config set project pfe-hti-2018`, une commande sans `--project` a listé les
> comptes du **mauvais projet**, sans avertissement. Seule l'invite `(pfe-hti-2018)` le signalait.

| Les identifiants d'un projet | Exemple | Choisi par | Modifiable |
|---|---|---|---|
| **ID** | `musicshop-fa81f` | moi | **non** |
| **Nom** | `music-shop` | moi | oui |
| **Numéro** | `446176716098` | ⚠ **Google** (QCM Q11) | non |

`gcloud` utilise l'**ID**.

---

## 1. Les conditions IAM

Une **attribution de rôle** = un **membre** (QUI) + un **rôle** (QUOI), posée sur une ressource (OÙ),
avec une **condition** facultative (QUAND, ou SUR QUOI exactement).

```
request.time < timestamp("2026-12-01T00:00:00Z")                       expiration
resource.name.startsWith("projects/_/buckets/mon-bucket/objects/factures/")   objets précis
```

> **Le rôle reste écrit dans la stratégie ; il ne s'applique plus quand la condition est fausse.**
> Un droit qu'on doit penser à retirer finit par ne pas être retiré : la condition, elle, n'oublie pas.

Combinable avec un **compte géré par l'entreprise** (Workspace, Cloud Identity) pour les prestataires :
authentification forte imposée, compte désactivable à la fin de la mission.

## 2. Vérifier une condition — ce que j'ai mesuré

⚠ Dans la console (QCM Q3 : « la condition est mal écrite ») :

```
outil de dépannage, condition sur request.time   → « Inconnu », avant comme après l'expiration
détail                                            → « accordé sous certaines conditions »
```

D'après la documentation, l'état `UNKNOWN_CONDITIONAL` signifie que l'outil n'a pas reçu le contexte
nécessaire pour évaluer la condition. Pour une condition temporelle, il lui faut **l'heure de la requête** :
depuis un **journal d'audit**, ou en ligne de commande avec **`--request-time`**.

```bash
gcloud policy-intelligence troubleshoot-policy iam \
  //cloudresourcemanager.googleapis.com/projects/week3-sandbox \
  --principal-email=logs-reader@week3-sandbox.iam.gserviceaccount.com \
  --permission=logging.logEntries.list \
  --request-time=2026-10-27T15:45:00Z
```

| `--request-time` | Membre | Rôle | Condition | Verdict |
|---|---|---|---|---|
| 15:45Z (avant 15:52Z) | `MATCHED` | `INCLUDED` | `true` | **`CAN_ACCESS`** |
| 16:00Z (après) | `MATCHED` | `INCLUDED` | `false` | **`CANNOT_ACCESS`** |

> **Un outil qui analyse les règles ne remplace pas le contexte d'une vraie requête.**

## 3. `gcloud` et Cloud Shell

- **Cloud Shell s'ouvre sans compte de facturation** (mesuré), avec `gcloud` configuré sur le projet.
- **Chaque service est une API** : la commande a demandé d'activer `policytroubleshooter.googleapis.com`,
  ce qui a réussi **sans** facturation.

```bash
gcloud config list                                   # [core] account = QUI agit · project = SUR QUOI
gcloud projects list                                 # mes 5 projets
gcloud iam service-accounts list --project=<ID>
gcloud projects get-iam-policy <ID> --format=yaml    # qui a quel rôle, agents de service compris
```

> **Une sortie filtrée vide est ambiguë** : aucun résultat, ou filtre faux ? Afficher la sortie complète.

## 4. Rappel de la reprise (HTTP)

⚠ La ligne après la ligne vide (QCM Q18 et oral : « le corps ») :

| | Le serveur lit la suite comme… |
|---|---|
| avec `Content-Length: N` | les N octets du **corps** |
| **sans** `Content-Length` | le **début de la requête suivante** |

Sources : [Troubleshoot IAM permissions](https://docs.cloud.google.com/policy-intelligence/docs/troubleshoot-access) ·
[iam.troubleshoot (AccessState)](https://docs.cloud.google.com/policy-intelligence/docs/reference/policytroubleshooter/rest/v3beta/iam/troubleshoot) ·
[gcloud policy-intelligence troubleshoot-policy iam](https://cloud.google.com/sdk/gcloud/reference/policy-intelligence/troubleshoot-policy/iam) ·
[Compute Engine service accounts](https://docs.cloud.google.com/compute/docs/access/service-accounts) ·
[Service account types](https://docs.cloud.google.com/iam/docs/service-account-types?hl=es)
