# Semaine 5 — Synthèse (10/11 → 17/11)

> Écrite à partir des **mesures** : QCM, labs, sorties de commandes. Pas d'auto-évaluation.

## Les scores de la semaine

| Date | QCM | Score |
|---|---|---|
| 11/11 | Cloud Run (questions sans mots-clés) | **100 %** (16 q) |
| 12/11 | Pub/Sub + lab GSP644 | **100 %** (15 q) |
| 13/11 | Logging + Monitoring | 93 % (15 q) · le raté = clic par erreur, vérifié à l'oral |
| 16/11 | Cloud Run functions + lab GSP092 | **100 %** (13 q) |
| 16/11 | Budgets, cycle de vie, ARC101 | 94 % (18 q) · raté : type des métriques système (item 45) |
| 17/11 | **QCM global, semaine entière, sujets mélangés** | **100 %** (20 q) |
| 17/11 | Contrôle oral, 3 questions ouvertes sans options | **3/3** |

Les QCM du jour mesurent ce qui est **frais** ; le QCM global mesure ce qui est **retenu**.
En semaine 3, le global était tombé à 70 % ; cette semaine, il tient.

⚠ Le QCM global avait un défaut de construction : la bonne réponse était souvent la plus longue, et la seule
à donner sa raison. Le contrôle en questions ouvertes (cycle de vie, budgets, Logging) a confirmé le score.

| Lab Google Skills | Score |
|---|---|
| GSP644 · Cloud Run + Pub/Sub + Cloud Storage (5 crédits) | 100/100 |
| GSP092 · Cloud Run functions + Logging + Monitoring (1 crédit) | 100/100 |
| ARC101 · Challenge Lab, budgets + cycle de vie + Eventarc (1 crédit) | 100/100 |

## Ce que je sais faire maintenant (prouvé par une mesure)

| Notion | La preuve |
|---|---|
| Choisir un service ou un job Cloud Run sur un cas sans mots-clés | QCM du 11/11 |
| Concevoir une application sans état pour Cloud Run (données hors du conteneur) | QCM global Q3 |
| Distinguer max instances et min instances | QCM global Q17 · erreur corrigée au lab GSP092 |
| Monter un fan-out Pub/Sub : un topic par événement, une subscription par traitement | QCM global Q1 |
| Savoir qu'une subscription, un sink, une métrique ne voient que ce qui arrive après leur création | QCM global Q4, Q11, Q20 · contrôle 3 |
| Choisir où lire un journal selon sa rétention (`_Default` 30 j, `_Required` 400 j) | QCM global Q2 · contrôle 3 |
| Écrire une stratégie d'alerte complète (condition, canaux, documentation) | QCM global Q12 |
| Choisir une fonction HTTP ou événementielle : quelqu'un attend-il une réponse ? | reprise du 17/11, sans indice |
| Réparer un déclencheur Eventarc refusé (`run.routes.invoke` → `roles/run.invoker` sur le service) | ARC101, 16/11 |
| Éviter qu'une fonction se redéclenche sur ses propres fichiers | QCM global Q15 · ARC101 |
| Séparer prévenir (budget, e-mail) et couper (Pub/Sub + fonction) | QCM global Q6, Q18 · contrôle 2 |
| Prévoir le coût d'un changement de classe : script (le compteur repart) ou règle (le temps compte) | QCM global Q9 · contrôle 1 |
| Récupérer un objet supprimé par le cycle de vie (soft delete, 7 j par défaut) | QCM global Q13 |

## Les paires à ne pas inverser

| Paire | Mon erreur de la semaine | La bonne |
|---|---|---|
| HTTP ↔ événementielle | « elle se déclenche, donc événementielle » (13/11) | quelqu'un attend-il une réponse ? |
| max ↔ min instances | « 5 au minimum » (lab GSP092) | max plafonne la montée ; min garde des instances allumées |
| 1 topic ↔ N topics | « 3 topics » (11/11) | 1 topic = l'événement, une subscription par traitement |
| système ↔ défini par l'utilisateur (métriques de journaux) | « système = compteur ou distribution » (16/11) | système = compteur, parfois booléen ; distribution = utilisateur seulement |
| e-mail ↔ Pub/Sub (budget) | « topic pour le prévenir par e-mail » (16/11) | e-mail : canal Cloud Monitoring ; Pub/Sub : du code |
| script ↔ règle de cycle de vie | « 30 jours » pour un script (16/11) | script = réécriture, le compteur repart |
| soft delete ↔ suppression définitive | « suppression définitive » ×2 (16/11) | 7 j de soft delete par défaut |

## Ce que j'ai mesuré moi-même (les 5 mesures qui m'ont le plus appris)

1. **`roles/run.invoker` manquant** (ARC101) : un déclencheur Eventarc livre en push vers `run.app`, et l'appelant doit avoir le droit d'invoquer.
2. **Le topic et l'abonnement push créés par Eventarc** (ARC101) : Eventarc s'appuie sur Pub/Sub.
3. **Une métrique basée sur les journaux vide avant sa création** (GSP092) : pas rétroactive.
4. **Le 403 IAM sur l'abonnement push** (GSP644) : le POST vient de Pub/Sub, qui doit être autorisé.
5. **La boucle évitée par le nom** (« already has a thumbnail », ARC101) : chaque objet écrit est un nouvel événement.

## Les trous qui restent

Voir `week-05-gaps.md`. En bref : deux items encore dans le cycle (43, 45 bis), l'export de facturation non
étudié, le jalon J2 non commencé.
