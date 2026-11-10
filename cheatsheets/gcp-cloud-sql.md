# GCP — Cloud SQL

> Fiche du 05/11 (semaine 4, jour 5), écrite après le QCM du 10/11 (10/11).
> Lab **GSP152** *Cloud SQL for PostgreSQL: Qwik Start* : 5/5.
> ⚠ = raté réel.

---

## Deux façons d'avoir PostgreSQL

| | PostgreSQL **sur ma VM** (`apt install`) | **Cloud SQL** |
|---|---|---|
| Modèle | **IaaS** | service **géré** |
| Correctifs, sauvegardes, HA | ⚠ **moi** — Cloud SQL ignore que ce PostgreSQL existe | Google, en grande partie |
| Panne de zone | point **unique** de panne | HA : bascule vers l'autre zone |

## La haute disponibilité (HA)

- **primaire** + **standby** dans **2 zones d'une même région**
- écriture copiée sur les deux disques **avant** la validation : **réplication synchrone**
- bascule quand la primaire ou sa zone tombe (battements de cœur chaque seconde)
- **IP statique partagée** → le backend se reconnecte **sans rien changer**
- ⚠ « standby » ≠ « réplica de lecture » (autre fonctionnalité, non étudiée)

## HA ou sauvegardes ? Les deux

| | HA | Sauvegardes |
|---|---|---|
| Protège contre | la **panne** d'une zone | l'**erreur** : `DELETE`, corruption, mauvaise migration |
| `DELETE FROM tasks;` | ❌ recopié dans les deux zones | ✅ on restaure une copie antérieure |

> ⚠ Panne de zone = **indisponibilité**. Perte de données = **erreur**. Deux risques, deux protections.
> ⚠ **Lire sa propre sortie** : `backupConfiguration.enabled: true` → il y a des sauvegardes.

## Lab GSP152 — mesuré

```bash
gcloud sql connect myinstance --user=postgres
# → lance cloud-sql-proxy (écoute sur 127.0.0.1), puis psql

gcloud sql instances describe myinstance \
  --format="yaml(region,gceZone,secondaryGceZone,settings.availabilityType,settings.backupConfiguration.enabled)"
```

| Mesuré | Sens |
|---|---|
| `gceZone: us-central1-c` / `secondaryGceZone: us-central1-f` | primaire et standby, 2 zones, 1 région |
| `availabilityType: REGIONAL` | c'est la HA |
| `backupConfiguration.enabled: true` | sauvegardes en plus de la HA |
| 1ʳᵉ connexion refusée | instance pas encore prête |

## psql

| Invite | Sens |
|---|---|
| `postgres=>` | prêt |
| `postgres->` | commande en cours (pas de `;`) |
| `postgres(>` | parenthèse ouverte |

- `\r` : vider la commande en cours · `\q` : quitter · ⚠ **pas Ctrl+C** : il a coupé la connexion au lab
- coller les commandes **une par une**

---

Source : [About high availability (Cloud SQL PostgreSQL)](https://docs.cloud.google.com/sql/docs/postgres/high-availability?hl=en)
