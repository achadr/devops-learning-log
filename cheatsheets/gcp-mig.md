# GCP — Groupes d'instances gérés, autoscaling, autohealing, VM Spot

> Fiche du 29/10 (semaine 3, jour 5), écrite après le QCM du 30/10 (19/20).
> Lab **GSP087** « Autoscaling Managed Instance Groups with Custom Metrics » : 100/100.
> ⚠ = raté réel (oral du 29/10 ou QCM du 30/10).

---

## Les paires à ne pas inverser

⚠ **Ce que constate une vérification de l'état** (QCM Q5 : « une réponse 404 » ; oral du 29/10 : « un 502 ») :

| Réponse obtenue | Ce qu'elle prouve |
|---|---|
| **rien, délai dépassé** | l'application est **figée** ou absente |
| `404` | l'application est **joignable et répond**, sans trouver la route |
| `502` | fabriqué par un **proxy** qui n'a pas obtenu de réponse de l'amont |
| `200` | l'application répond normalement |

⚠ **Autoscaling et autohealing** (oral du 29/10 : « l'autohealing regarde le processeur ») :

| | **Autoscaling** | **Autohealing** |
|---|---|---|
| Réagit à | la **charge** : processeur, métrique, file… | une VM qui **échoue à la vérification de l'état** |
| Action | **ajoute ou retire** des VM | **supprime et recrée** la VM défaillante |
| VM figée à 0 % | ne la remplace pas | ✅ la remplace — **si elle est configurée** |
| Dans mon groupe du lab | **On** (min 1, max 3) | ⚠ **Off** : « *Instance by health : Not configured* » |

> Une VM qui **tourne** n'est pas une VM qui **répond** : la paire du jour 6 (« `Up` ≠ le service répond »).

| | **Modèle d'instance** | **Groupe d'instances géré** |
|---|---|---|
| Ce que c'est | la **recette** : type de machine, image, métadonnées, compte de service | l'**ensemble** des VM créées depuis la recette, géré comme un tout |
| Dans le lab | `autoscaling-instance01` | `autoscaling-instance-group-1` |

| | **Zonal** (*Single zone*) | **Régional** |
|---|---|---|
| Les VM | dans une seule zone | réparties sur plusieurs zones |
| Survit à la perte de la zone | ✗ | ✅ |

| | **VM standard** | **VM Spot** |
|---|---|---|
| Prix | normal | jusqu'à **−91 %** (doc officielle) |
| Interruption | non | **préemptible à tout moment** |
| Pour | mon backend en production | charges **tolérantes aux pannes** : traitement de nuit, lots |

| | **Ajouter** une VM | **Retirer** une VM |
|---|---|---|
| Vitesse | **vite** | **lentement** : ~10 min de baisse stable (manuel du lab) |
| Pourquoi | ajouter trop tard = perdre des utilisateurs | retirer trop vite = faire osciller le groupe |

---

## 1. Les quatre services d'un groupe géré (documentation, lue par moi)

| Événement | Service |
|---|---|
| une VM plante | **autohealing** |
| le trafic triple | **autoscaling** — horizontal : plus de VM, pas plus de bande passante |
| une nouvelle version sort | **mise à jour progressive** |
| une zone tombe | **groupe régional** |

Un groupe ne coûte rien en lui-même : on paie les VM qu'il fait tourner.

## 2. Le lab GSP087 — mesuré

| Observé | Ce que ça montre |
|---|---|
| `gcloud compute instance-groups managed list` → `us-east1-c` | trouver la zone **en interrogeant le projet** |
| `startup.sh` = **3 230 octets** via `startup-script-url` → `nodeapp: available` | un petit script dans Cloud Storage **fonctionne** (question du 27/10 fermée) |
| console série : `google-startup-scripts.service`, démarrage **2 min 49 s** | un service systemd ; une VM met des minutes à être prête |
| utilisateur dédié `nodeapp` | moindre privilège, comme `velocite` et `USER node` |
| 7 lignes « Error » = **`set -v`** (ligne 16 du script) | **la gravité est une étiquette, pas un diagnostic** |
| Logs Explorer : 0 résultat → plage horaire **figée** → « Last 1 hour » | frais ou mémorisé |
| mon groupe passé **seul** de 1 à 2 VM : `…-81vr` | c'est le groupe qui crée et nomme ses VM |
| `builtin-igm` : capacité **300 = 150 × 2**, max 2, creux à ~100 **sans réduction** | la capacité suit le nombre de VM · le délai de réduction |
| modèle : **compte par défaut** attaché, `enable-oslogin: true`, scope `monitoring.write` | chaque VM hérite du compte par défaut (`Éditeur`) — jusqu'à **3** dans mon groupe |

```bash
gcloud compute instance-groups managed list
gcloud compute instances get-serial-port-output <VM> --zone=$ZONE | grep -i startup | tail -n 15
gcloud storage cat gs://$BUCKET/startup.sh | grep -n "set -"
gcloud compute instance-templates describe <modèle> --format="yaml(properties.machineType,properties.metadata,properties.serviceAccounts)"
```

## 3. La règle des labs

⚠⚠ **Aucune ressource hors manuel** : sinon le lab s'arrête et le compte peut être bloqué (aide de
Google Skills). Les commandes de **lecture** restent sûres.

---

Sources : [Instance groups — Compute Engine](https://docs.cloud.google.com/compute/docs/instance-groups) ·
[Create and use Spot VMs](https://docs.cloud.google.com/compute/docs/instances/create-use-spot)
