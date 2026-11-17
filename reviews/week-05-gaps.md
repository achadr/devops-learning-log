# Semaine 5 — Liste de trous (17/11)

> Construite à partir des **mesures** : QCM global du 17/11 à 100 % (20 q), contrôle oral 3/3, reprise espacée
> 5/5. Le QCM global n'a produit **aucun raté** : les trous ci-dessous viennent des ratés de la semaine encore
> dans le cycle, de ce qui n'a pas été mesuré, et de ce qui n'est pas vérifié.
> Un trou est « fermé » quand il est réussi en reprise espacée à J+7.

## Trous encore dans le cycle de reprise

| # | Trou | Preuve du trou | Réenseigné par | Reprise |
|---|---|---|---|---|
| 1 | HTTP ↔ événementielle (item 43) | 13/11 : « helloworld est événementielle, elle se déclenche » · 16/11 : 3 questions de guidage | mes propres observations de GSP092 (GET, 200, navigateur) | J+1 ✓ 16/11 · J+2 ✓ 17/11 · **J+7 le 20/11** |
| 2 | distribution = métrique définie par l'utilisateur seulement (item 45 bis) | 16/11 QCM Q17 : « système = compteur ou distribution » | **ma lecture** de *Log-based metrics* (*Data types*) | J+1 ✓ 17/11 · **J+2 prochaine séance** · J+7 le 23/11 |
| 3 | 1 topic = l'événement (item 42) | 11/11 : « 3 topics » | correction trouvée seul (« un topic topic-task ») | J+1 ✓ · J+2 ✓ · QCM global ✓ (J+6) · **J+7 le 18/11** |
| 4 | adresse source après la passerelle = IP externe de l'expéditeur (item 33, semaine 4) | 03/11 : 2 fois l'IP de la destination | lab pare-feu | **J+7 le 18/11** |

## Fermés cette semaine (J+7 réussi)

À l'oral le 17/11 : 37 (`compute/region` ↔ `--location`) · 38 (suppression anticipée) · 39 (relire sa sortie).
Au QCM global du 17/11 : 22 bis (familles de machines) · 35 (cible d'une règle de sortie) · 36 (`req.ip` sans
trust proxy) · 40 (Archive en millisecondes) · 41 (PostgreSQL sur ma VM = moi) · 25 bis (Free Tier = facturation).
Plus tôt dans la semaine : 26, 27, 28, 30 (13/11) · 29, 31 (16/11) · 34 (11/11).
Encore dans le cycle : 44 (métrique pas rétroactive), juste à J+2 au QCM global → J+7 le 20/11.

## Non étudié (programme ACE)

| Trou | Prévu |
|---|---|
| Export de la facturation (Cloud Billing export) : à quoi il sert, en quoi il diffère d'un budget | S6, doc à lire avant |
| Jalon J2 (compose : API sans état + PostgreSQL + émulateurs Storage et Pub/Sub, commandes de déploiement écrites) | **non commencé**, décision le 17/11 |
| Questions d'exemple officielles de l'ACE, passées « à froid » | avant S7 |

## Non vérifié (dette notée, non corrigée)

- `retryPolicy: RETRY_POLICY_DO_NOT_RETRY`, alors que `travel.jpg` a été traitée après deux refus (ARC101) : non expliqué.
- ARC101 : aucune ligne `published` dans les journaux, et le topic n'a pas d'abonnement : non vérifiable.
- `serviceAccountTokenCreator` pour l'agent Pub/Sub (GSP644) : question ouverte depuis le 11/11.
- Frais de suppression anticipée pour l'action **Delete** du cycle de vie : non lu explicitement.
- Lecture plus chère en Coldline qu'en Nearline : non lu.

## Méthode

- Le QCM global avait un biais : bonne réponse souvent la plus longue et la seule justifiée. À partir de la semaine 6,
  les options auront une longueur comparable et aucune ne portera sa raison.
- Une question ouverte ne laisse pas d'indice : à garder en contrôle quand un QCM est à 100 %.
