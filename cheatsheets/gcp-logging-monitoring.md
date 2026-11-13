# GCP — Cloud Logging et Cloud Monitoring

> Fiche du 12/11 (semaine 5, jour 3), écrite après le QCM du 13/11 (14/15, raté = clic par erreur, vérifié à l'oral).
> Pratique prévue : lab GSP092 (métrique basée sur les journaux, tableau de bord).

---

# Cloud Logging

## 1. Le besoin

Tous les services envoient leurs journaux à Cloud Logging. Trois demandes :
garder **l'audit** un an · analyser **les erreurs** en SQL · **ne plus payer** le débogage inutile.

## 2. Les défis

Tout arrive **au même endroit**, alors que chaque demande exige un traitement différent : il manque un **tri**.

## 3. Le principe

Un centre de tri qui **lit les informations** de chaque journal (type de ressource, nom, gravité, contenu)
et applique des **règles de filtrage associées à des destinations**.

## 4. La solution : le Log Router

- chaque **sink** = **un filtre d'inclusion** (+ des filtres d'**exclusion**) + **une destination**
- destinations : **log bucket**, **BigQuery**, **Cloud Storage**, **Pub/Sub**, un autre projet
- ⚠ **pas rétroactif** : un sink ne traite que ce qui arrive **après** sa création

| Sink / bucket | Reçoit | Rétention par défaut | Modifiable ? |
|---|---|---|---|
| **`_Required`** | une partie des **journaux d'audit** (qui a modifié quoi) | **400 jours** | ❌ ni le sink, ni la durée |
| **`_Default`** | **tout le reste** | **30 jours** | ✅ durée de 1 à 3 650 jours, exclusions, désactivation |

| Demande | Configuration |
|---|---|
| garder l'audit un an | **rien** : `_Required` le garde 400 jours |
| analyser les erreurs en SQL | un **sink vers BigQuery**, filtré sur le service et le texte des erreurs |
| ne plus payer le débogage | un **filtre d'exclusion** sur `_Default` |

> ⚠ `console.log("Error: …")` produit une gravité **Default** : un filtre `severity=ERROR` ne le voit pas.
> Il faut filtrer sur le **texte** et le **service**.

---

# Cloud Monitoring

## 1. Le besoin

À 3 h, le convertisseur échoue sur chaque fichier. L'équipe l'apprend à 11 h, par un client,
alors que les journaux contenaient les erreurs depuis 3 h.

## 2. Les défis

| Défi | Pourquoi |
|---|---|
| journaux **passifs** | il faut un humain pour les lire |
| personne à 3 h | la surveillance humaine s'arrête la nuit |
| service qui **ment** | il répond `200 OK` en cachant ses erreurs : les signaux habituels sont au vert |

## 3. Le principe

Un robot qui **surveille** à la place de l'humain : ce qu'il regarde et à partir de quand c'est anormal,
**qui** il prévient, et **ce que la personne doit savoir** pour agir.

## 4. La solution : la règle d'alerte

| Partie | Rôle |
|---|---|
| **Condition** | l'état qui demande une réaction (ex. : plus de 5 erreurs par minute) |
| **Canaux de notification** | **qui** prévenir (e-mail, Slack…) |
| **Documentation** | ce qu'il faut savoir pour agir : liens, procédure |

Une condition surveille un **nombre**. Les journaux sont du **texte**.
→ la **métrique basée sur les journaux** fait le pont : elle compte ou extrait une valeur des journaux.

```
journaux « Error: » ─▶ métrique basée sur les journaux (un nombre) ─▶ condition « > 5 / min »
                                                                         │
                                                                         ▼
                                                     canal de notification + documentation ─▶ astreinte
```

> Un service qui attrape toutes ses erreurs et répond 200 est **invisible** pour la surveillance.

---

Sources : [Route log entries](https://docs.cloud.google.com/logging/docs/routing/overview) ·
[Cloud Logging quotas and limits](https://docs.cloud.google.com/logging/quotas) ·
[Alerting overview](https://docs.cloud.google.com/monitoring/alerts)
