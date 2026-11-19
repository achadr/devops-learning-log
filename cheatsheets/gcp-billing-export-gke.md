# GCP — Export de facturation vers BigQuery, GKE (principe)

> Fiche du 18/11 (semaine 6, jour 1), écrite après le QCM du 19/11 : **19/19 (100 %)**, confirmé par 3 questions ouvertes (3/3).
> ⚠ = raté réel (à l'oral le 18/11) · ⚠⚠ = erreur qui coûte de l'argent ou des données.
> Faits lus par moi dans la doc officielle, sauf mention « lu par moi seulement » (à relire avant de s'en servir).

---

## Les paires à ne pas inverser

| | | |
|---|---|---|
| **Budget** : prévient quand un seuil est atteint | ↔ | **Export** : sert à trouver d'où vient la dépense (service, projet, date) |
| ⚠ **Sink, métrique de journaux, subscription** : jamais rétroactifs | ↔ | **Export de facturation** : rétroactif **selon l'emplacement** du dataset |
| Dataset **multirégion** (`EU`, `US`) : mois courant **et** précédent ajoutés | ↔ | Dataset **régional** (`europe-west1`) : « not added retroactively » |
| **Coût standard** : par service et par projet | ↔ | **Coût détaillé** : par **ressource** (une VM précise) |
| **Coûts** (multirégion) : rattrapés | ↔ | **Prix** : jamais rétroactifs |
| **Chargement** des données par Google : gratuit | ↔ | **Requêtes** sur le dataset : facturées |
| **Autopilot** : Google gère le plan de contrôle **et les nœuds** (recommandé) | ↔ | **Standard** : Google gère le plan de contrôle, **moi les nœuds** |
| **Nœud** = une VM Compute Engine | ↔ | **Pod** = là où tournent les conteneurs, placé sur un nœud |
| **Autohealing d'un MIG** : recrée une **VM** | ↔ | **Orchestrateur** (GKE) : relance un **conteneur** (principe ; mécanisme lu en S6 J2) |

---

## 1. Export de facturation vers BigQuery

**Besoin** : savoir **quel service**, **dans quel projet**, et **depuis quand** une dépense monte.
> ⚠ J'ai d'abord donné le besoin sans le **temps** (« détail par service et par projet »). Une ligne de l'export =
> service, projet, **date**, coût.

**Défis** : le budget dit « 90 % atteint », pas **pourquoi** · la facture arrive après coup · il faut pouvoir **interroger** la dépense.

**Principe** (trouvé par moi) : « une base de données remplie automatiquement par Google ».

**Solution : l'export Cloud Billing vers BigQuery** (*Export Cloud Billing data to BigQuery*)
- Rempli « automatically throughout the day » dans un **dataset BigQuery**.
- Trois types, **chacun s'active séparément** : coût standard · coût détaillé (niveau ressource) · prix.
  (FOCUS et engagements d'utilisation en préversion : lu par moi seulement.)
- ⚠⚠ **Rétroactivité selon l'emplacement du dataset** :
  - multirégion (`EU`, `US`) → mois courant **et** précédent ajoutés (rattrapage jusqu'à 5 jours : lu par moi seulement) ;
  - régional → rien d'avant l'activation.
  - → **choisir l'emplacement AVANT d'activer** : il ne se rattrape pas.
- Les **prix** ne sont jamais rétroactifs.
- Chargement « is free » ; les **requêtes** BigQuery sont facturées.

> ⚠ J'avais prédit « non, l'export n'est pas rétroactif » : j'avais recyclé la règle du sink, de la métrique de journaux et
> de la subscription (tous trois : rien avant leur création). L'export est une exception **partielle**.

Non lu : la page *Set up Cloud Billing data export*.

### Cas appliqués (QCM et contrôle du 19/11)

| Cas | Ce qu'on trouve |
|---|---|
| Dataset `europe-west1` activé aujourd'hui, pic d'il y a 10 jours | **rien** |
| Dataset `EU` activé aujourd'hui, pic du mois dernier | **le pic** |
| Chef : « coût de `vm-batch-3` » | export **coût détaillé** |
| Seul le coût standard activé, on cherche un prix catalogue | **rien** : les prix s'activent à part |
| Collègue en `europe-west1`, chef veut depuis le 1ᵉʳ du mois | depuis l'activation seulement → il fallait un dataset multirégion **avant** d'activer |

---

## 2. GKE — le principe

**Les mots** (définis sur ma pile compose) :
- **Orchestrateur** : programme qui place des conteneurs sur des machines, les relance et en ajoute. Compose lance mes 4 services
  **une fois**, sur **une** machine ; il ne les déplace pas.
- **Kubernetes** : l'orchestrateur open source. **GKE** = Kubernetes **géré** par Google (« a managed implementation of the Kubernetes
  open source container orchestration platform »). Ce qui est propre à Google, c'est la gestion, pas Kubernetes.
- **Nœud** : une VM Compute Engine qui fait tourner des conteneurs. **Cluster** : l'ensemble des nœuds.
- **Pod** : l'unité où tournent les conteneurs, placée sur un nœud.
- **Plan de contrôle** : la partie qui décide (où placer, quoi relancer). Géré par Google dans les deux modes.

**Défis** (sur 50 conteneurs et 5 VM) : **qui place** chaque conteneur · **qui le relance** s'il meurt · ⚠ **qui ajoute des copies**
d'un seul service quand la charge monte (trouvé seulement avec le cas « lundi matin »).

**Principe** (trouvé par moi) : « on lui décrit l'état voulu, il place, relance et ajoute ».

**Autopilot ↔ Standard** (*GKE overview*, lu par moi)
- Autopilot : Google gère aussi les nœuds. **Mode recommandé.**
- Standard : quand on a un « specific need to manually manage the node pools ».
- Équipe sans besoin particulier sur ses machines → **Autopilot**.

Non lu, ne pas affirmer : ce qu'est un *node pool* · GKE ou Cloud Run (aucune comparaison sur la page) · Deployment, Service, passage
à l'échelle (S6 J2) · ma question ouverte « load balancer ? » (répartir entre plusieurs copies) : réponse par la lecture du Service (S6 J2).

---

## 3. Labs GKE choisis (18/11)

| Lab | Coût | Quand |
|---|---|---|
| 164380 *Deploy, Scale, and Expose Applications on GKE* | 1 crédit, 10 min, Introductory | S6 J2 |
| 72688 *Deploying GKE Autopilot Clusters from Cloud Shell* | 1 crédit, 1 h, Introductory | S6 J3 |
| GSP1077 *GKE Pipeline using Cloud Build* | 5 crédits, 40 min, Intermediate | phase 3 (CI/CD) |

Les liens directs `skills.google/focuses/<id>` me donnent « access denied » → passer par la **recherche du catalogue**.
Avant un lab, la question : « J2 peut-il me l'apprendre ? ». Pour GKE, non : J2 n'a ni cluster ni nœuds.
