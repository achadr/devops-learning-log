# GCP — Cloud Storage

> Fiche du 05/11 (semaine 4, jour 4), écrite après le QCM du 10/11 (80 %, ratés vérifiés à l'oral).
> Lab **GSP074** *Manage Cloud Storage with the Google Cloud CLI* : 100/100.
> ⚠ = raté réel.

---

## Pourquoi

Un groupe géré **remplace** ses VM et chaque VM a **son propre disque** : un fichier rangé sur VM-A est
invisible pour VM-B et perdu quand VM-A est recréée depuis le modèle.
→ un stockage **hors des VM**, partagé : Cloud Storage.

## Bucket et objet

| | |
|---|---|
| **Bucket** | conteneur d'objets · nom **global et public** → aucune info sensible dans le nom |
| **Objet** | fichier de **tout format**, **immuable** : ni ajout, ni troncature |
| Remplacer | même nom → **remplacement atomique**, nouvelle **génération** (⚠ pas « supprimer puis recréer ») |
| Contenu | Cloud Storage ne regarde **pas** les octets : `.jpg` n'est qu'un nom (lab : une page HTML) |

## Les 4 classes

| | Standard | Nearline | Coldline | Archive |
|---|---|---|---|---|
| Accès prévu | fréquent | ≤ 1 fois/mois | ≤ 1 fois/trimestre | < 1 fois/an |
| Durée minimale | aucune | 30 j | 90 j | 365 j |
| Stockage au repos | le plus cher | ↓ | ↓ | le moins cher |
| Coût d'accès | aucun | ↑ | ↑ | le plus cher |

- **Identique** pour toutes : la **durabilité** · ⚠ le **temps d'accès** : millisecondes, même pour Archive
  (pas comme les archives d'AWS) · les mêmes API
- **Différent** : coût d'accès, durée minimale, **disponibilité** (SLA régional : Standard 99,9 %, autres 99,0 %)
- **Supprimé, remplacé ou déplacé avant la durée minimale → facturé comme si l'objet était resté**
  → un fichier **modifié souvent** va en **Standard**, même s'il est rarement lu

| Cas `task-manager` | Classe |
|---|---|
| avatars, à chaque connexion | Standard |
| pièces jointes des tâches terminées, rapport mensuel | Nearline |
| sauvegardes de la base, gardées un an | Archive |
| PDF corrigé tous les 5 jours | Standard |

## Accès : IAM, ACL, accès uniforme

| | IAM | ACL |
|---|---|---|
| Où | stratégie du projet ou du bucket | **sur chaque objet** |
| Audit | un `get-iam-policy` | objet par objet |

- les deux sont **indépendants** : **un seul suffit** à donner l'accès
- un audit IAM **ne voit pas** une ACL `allUsers`
- **accès uniforme au niveau du bucket** = ACL désactivées, IAM seul décide → **recommandé**

## Lab GSP074 — mesuré

```bash
gcloud storage buckets create gs://<nom> --location=europe-west1   # ⚠ sans --location : US multirégion
gcloud storage buckets describe gs://<nom>          # location, default_storage_class, uniform_bucket_level_access
gcloud storage cp ada.jpg gs://<nom>/image-folder/
gcloud storage ls -r gs://<nom>
gcloud storage objects update gs://<nom>/ada.jpg --add-acl-grant=entity=allUsers,role=READER
gcloud storage objects update gs://<nom>/ada.jpg --remove-acl-grant=allUsers
gcloud storage rm gs://<nom>/ada.jpg
file ada.jpg                                         # le vrai type, quelle que soit l'extension
```

> ⚠ `gcloud config set compute/region` ne concerne **que Compute Engine**.

---

Sources : [Cloud Storage overview](https://docs.cloud.google.com/storage/docs/introduction) ·
[About objects](https://docs.cloud.google.com/storage/docs/objects) ·
[Storage classes](https://docs.cloud.google.com/storage/docs/storage-classes) ·
[Pricing](https://cloud.google.com/storage/pricing) ·
[Uniform bucket-level access](https://docs.cloud.google.com/storage/docs/uniform-bucket-level-access) ·
[Archive storage class (blog Google Cloud)](https://cloud.google.com/blog/products/storage-data-transfer/archive-storage-class-for-coldest-data-now-available)
