# GCP — Accès d'une VM : scopes, OS Login, comptes de service

> Fiche du 30/10 (semaine 3, jour 6), écrite après le QCM du 02/11 (19/20, aucun raté sur ce sujet).
> ⚠ = raté réel (oral du 30/10 ou du 02/11).

---

## Les paires à ne pas inverser

⚠⚠ **Agent de service et compte par défaut** — raté 3 fois (QCM 27/10, QCM 29/10, oral 02/11).
**Règle de l'adresse (formulée par moi le 02/11) : le préfixe `service-` + `@compute-system` = agent de service.**

| Adresse | Type | À qui | Que faire |
|---|---|---|---|
| `NUMÉRO-compute@developer.gserviceaccount.com` | **compte par défaut** | **à moi** | le surveiller : peut avoir `Éditeur` · ne pas l'attacher aux VM |
| `service-NUMÉRO@compute-system.iam.gserviceaccount.com` | **agent de service** | **à Google** | **ne pas y toucher** : ni rôle ajouté, ni rôle retiré |

> Mesuré : au lab du 28/10, `describe` montrait le **compte par défaut** attaché à mes VM, avec `roles/editor`.
> Le 27/10, `get-iam-policy` montrait l'**agent de service** avec `roles/compute.serviceAgent`.

⚠ **Le rôle IAM et le *scope*** (oral du 30/10 : « oui, Éditeur permet de supprimer ») :

| | Rôle IAM du compte de service | *Scope* de la VM |
|---|---|---|
| Où ça se règle | sur la **ressource** : projet, secret, bucket | sur l'**instance** |
| Ce que ça fixe | ce que le **compte** a le droit de faire | ce que la **VM** peut demander avec ce compte |
| Règle | **les deux doivent autoriser** l'accès | |

> Lab du 28/10 : `roles/editor` **et** `devstorage.read_only` → **suppression refusée**, malgré Éditeur.
> **Bonne pratique** : scope **`cloud-platform`**, et le moindre privilège par les **rôles IAM**.

| | Clés SSH dans les métadonnées | **OS Login** |
|---|---|---|
| L'accès repose sur | un fichier `authorized_keys` sur chaque VM | un **rôle IAM** |
| Un collègue part | nettoyer chaque VM, avec le risque d'en oublier une | **retirer un rôle**, une fois |
| `authorized_keys` | utilisé | **supprimé** par Compute Engine |

---

## 1. Ma VM backend

| | |
|---|---|
| Compte | un compte de service **géré par moi**, pas le compte par défaut |
| Rôle | `roles/secretmanager.secretAccessor` |
| Sur quoi | **ce seul secret** |
| *Scope* | `cloud-platform` |

Un autre secret demandé par l'application → **refusé** : le rôle ne le couvre pas.

## 2. OS Login (page « Configurer OS Login », lue par moi le 30/10)

- s'active par la métadonnée **`enable-oslogin`** (vue dans le modèle d'instance du lab GSP087)
- rôles : **`roles/compute.osLogin`** ou **`roles/compute.osAdminLogin`**
  ⚠ (oral du 30/10 : « osAdminLogin et osLoginExternalUser » — ce dernier sert aux utilisateurs **d'une autre
  organisation**)
- différence `osLogin` / `osAdminLogin` : **d'après le nom seulement** (sans / avec droits d'administration) —
  **non lu dans la doc**
- projet `TRUE`, VM `FALSE` → **désactivé sur cette VM** : le réglage le plus précis l'emporte,
  comme le script de démarrage

---

Sources : [Compute Engine — service accounts](https://docs.cloud.google.com/compute/docs/access/service-accounts) ·
[gcloud compute instances set-service-account](https://docs.cloud.google.com/sdk/gcloud/reference/compute/instances/set-service-account) ·
[Configurer OS Login](https://docs.cloud.google.com/compute/docs/access/user-accounts?hl=fr)
