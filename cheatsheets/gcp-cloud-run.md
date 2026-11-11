# GCP — Cloud Run

> Fiche du 10/11 (semaine 5, jour 1), écrite après le QCM du 11/11 (16/16).
> Pas encore de lab : pratique prévue avec GSP644.

---

## 1. Le besoin

J'ai une API déjà empaquetée dans une **image Docker**. Je veux :
- une **adresse stable** qui répond aux requêtes HTTP ;
- qu'elle **tienne la charge** ;
- qu'elle ne coûte **rien au repos** ;
- **développer**, pas entretenir des serveurs.

## 2. Les défis, avec un groupe de VM

| Défi | Pourquoi |
|---|---|
| Entretien | VM = IaaS : correctifs du système, image, script de démarrage, tout est pour moi |
| Coût au repos | un groupe géré garde au moins 1 VM allumée, payée même sans requête |
| Assemblage | modèle, groupe, vérification de l'état, équilibreur, pare-feu, pour un seul conteneur |

## 3. Le principe

Un conteneur a **toujours** besoin d'une machine. Ce qui change, c'est **qui la gère** :
Google garde ses propres machines, je lui donne **mon image**, et il lance, multiplie et arrête
mon conteneur selon la demande. Je paie **l'usage**, pas les machines.

## 4. La solution : Cloud Run

- plateforme **entièrement gérée** pour faire tourner une image de conteneur
- pas de cluster ni d'infrastructure à gérer
- **mise à zéro** : sans requête, même la dernière instance est retirée

| | Groupe de VM + équilibreur | Cloud Run |
|---|---|---|
| Ce que je fournis | image système, script, modèle, groupe, équilibreur | **mon image Docker** |
| Correctifs des machines | moi | Google |
| La nuit, sans trafic | au moins 1 VM payée | **0 instance** |
| Montée en charge | autoscaling à régler | automatique |

### Service ou job

| | **Service** | **Job** |
|---|---|---|
| Rôle | attend des appels à une **URL stable** | exécute une tâche qui **se termine** |
| Exigence | écouter sur un port, traiter des requêtes HTTP | aucune URL |
| Exemples | l'API, un webhook de paiement, une page de statut | `migrate`, une sauvegarde nocturne, les factures du mois |

> Une URL à appeler → service. Une tâche qui a une fin → job.

### Facturation

| Mode | Je paie |
|---|---|
| par requête | seulement quand l'instance traite des requêtes |
| par instance | toute la durée de vie de l'instance |

### Sans état

Les instances sont **créées et supprimées à tout moment** : leur disque disparaît avec elles.
Tout ce qui doit durer vit **hors de Cloud Run**.

```
Utilisateurs ──▶ Cloud Run : task-manager-api   (sans état, 0 à N instances)
                     │                     │
                     ▼                     ▼
               Cloud SQL (HA)        Cloud Storage
               les tâches            les pièces jointes
```

> `tasks.sqlite` dans l'instance serait perdu chaque nuit.
> La mise à zéro ne concerne **que** Cloud Run : la base Cloud SQL tourne et se paie toujours.

---

Source : [What is Cloud Run](https://docs.cloud.google.com/run/docs/overview/what-is-cloud-run?hl=en)
