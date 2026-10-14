# Post-mortem — Dégradation du service Vélocité du 11 octobre 2026

**Statut :** cause racine non établie - investigation côté infrastructure requise
**Rédigé le :** 2026-10-14
**Sévérité :** SEV2 - service dégradé mais disponible, parcours d'achat partiellement impacté, aucune perte de données

## 1. Résumé

Le 11 octobre 2026 entre 18h00 et 19h59, la boutique Vélocité a renvoyé une 
erreur serveur sur une requête sur quatre. 2 187 requêtes ont échoué sur les 8 650 reçues 
pendant ces deux heures. Les requêtes servies l'ont été quatre fois plus lentement que d'habitude.

Le service est revenu à la normale seul à 20h00, sans intervention. La cause
n'est pas établie : les données de log excluent une saturation par le trafic
et désignent une ressource partagée indisponible par intermittence.

## 2. Impact

Sur la plage 18h00–19h59, **2 187 requêtes ont échoué sur les 8 650 reçues**,
soit 25 % du trafic de la soirée. Les requêtes servies l'ont été en 1,753 s
en moyenne contre 0,445 s le reste de la journée — **quatre fois plus
lentement**.

Côté client, une tentative sur quatre se soldait par une page d'erreur, et
cela sur l'ensemble du site : catalogue, fiches produit, panier et validation
de commande. Un visiteur enchaînant une dizaine de pages avait donc toutes
les chances d'en voir plusieurs échouer, y compris au moment de valider son
panier.

Trois clients ont signalé le problème par écrit. Le nombre de personnes
réellement affectées est très supérieur : seule une faible proportion des
clients signale un incident, les autres abandonnent sans rien dire.

## 3. Chronologie

| Horodatage | Événement |
|---|---|
| 11/10 18:00:00 | Première requête en erreur 5xx observée dans le log d'accès |
| 11/10 18:00–19:00 | Sur 4 140 requêtes, 1 025 en erreur 5xx — 24,8 % d'échec |
| 11/10 ~18:30 | Réception de 3 plaintes clients signalant l'impossibilité de finaliser leur commande *(source : signalement client, non corroboré par le log — une plainte ne laisse pas de trace côté serveur)* |
| 11/10 19:00–20:00 | Sur 4 510 requêtes, 1 162 en erreur 5xx — 25,8 %, le taux d'échec horaire le plus élevé de la journée |
| 11/10 19:59:49 | Dernière requête en erreur 5xx observée |
| 11/10 20:00–21:00 | Heure la plus chargée de la journée (4 690 requêtes) et **aucune erreur 5xx** — retour à la normale sans intervention |
| 12/10 09:00 | Signalement par la responsable e-commerce, soit **15 heures après le début de l'incident** |
| 12/10 | Analyse du log d'accès |

## 4. Détection

L'incident n'a été détecté par aucun système. Il a été signalé par des
humains : trois clients pendant l'incident, puis la responsable e-commerce
le lendemain matin.

Le délai de détection est de **15 heures après le début** de l'incident et
**13 heures après sa fin**. L'incident était terminé depuis plus d'une
demi-journée quand l'équipe en a eu connaissance : aucune intervention
n'était possible, seule une analyse a posteriori l'était.

Aucune supervision ne couvrait ce cas. Pendant les deux heures, le service
était `active` au sens de systemd et répondait à toutes les requêtes — il y
répondait simplement par une erreur une fois sur quatre. **Surveiller qu'un
processus tourne ne dit rien de ce qu'il répond.**

Deux alertes auraient détecté l'incident en quelques minutes :

| Alerte | Grandeur | Seuil | Fenêtre | Rôle |
|---|---|---|---|---|
| Taux d'erreur | part de réponses 5xx | > 1 % | 5 min | constate la dégradation |
| Latence | p95 du temps de réponse | > 0,9 s (2× la normale) | 5 min | **indicateur avancé** : le service ralentit avant d'échouer |

## 5. Méthode d'investigation

Toute l'analyse a été menée sur le seul log d'accès Nginx
(`velocite-access.log`, 50 295 lignes), sans accès au serveur.

| Commande | Ce qu'elle a établi |
|---|---|
| `awk '{codes[$9]++} END {for (c in codes) print codes[c], c}' \| sort -rn` | 2 187 réponses 5xx sur 50 295 requêtes, soit 4,35 % sur la journée — niveau d'incident majeur pour un site marchand |
| `awk '{split($4,t,":"); h=t[2]; req[h]++; if ($9 ~ /^5/) err[h]++} END {...}' \| sort` | A localisé l'incident sur la plage 18h–20h et **réfuté l'hypothèse de la charge** : 20h a traité 4 690 requêtes sans une seule erreur |
| `awk '{split($4,t,":"); h=t[2]+0; if (h>=18 && h<=19) {a+=$NF; na++} else {b+=$NF; nb++}} END {...}'` | Temps de réponse moyen de 1,753 s pendant l'incident contre 0,445 s hors incident — facteur 3,9. Le service ne tombait pas, il **ralentissait** : signature d'une attente sur une ressource, pas d'un plantage |
| `awk '{split($4,t,":")} t[2]==18 && $9 ~ /^5/ {print $7}' \| sort \| uniq -c \| sort -rn` | Erreurs réparties proportionnellement au trafic de chaque page, **fichiers statiques et `/health` compris** — écarte une fonctionnalité défaillante, désigne une indisponibilité de toute la chaîne de service |
| `awk '$9 ~ /^4/ {c[$1]++} END {for (i in c) if (c[i]>100) print i, c[i]}'` | Deux IP hostiles identifiées, 3 721 requêtes, **100 % de 404 et 403** — aucune corrélation avec la fenêtre d'incident, écartées comme cause |

## 6. Hypothèses réfutées

| Hypothèse | Donnée qui la contredit |
|---|---|
| **Saturation sous la charge du soir** | L'heure de 20h a traité 4 690 requêtes — le pic de la journée — sans une seule erreur 5xx. Si la capacité était en cause, cette heure serait la pire |
| **Attaque par déni de service** | Les deux IP hostiles ont émis 3 721 requêtes réparties uniformément sur 24 h, sans corrélation avec la fenêtre 18h–20h. Leurs requêtes ont reçu 100 % de 404 et 403, servies par le proxy en 0,005 s sans jamais atteindre l'application |
| **Une fonctionnalité applicative défaillante** | Les erreurs touchent toutes les URL dans la proportion de leur trafic habituel, y compris les fichiers statiques et le point d'entrée `/health`. Une fonctionnalité cassée produirait une concentration sur une ou deux URL |
| **Une panne franche de l'application** | 75 % des requêtes ont continué d'être servies pendant toute la fenêtre. Le service n'a jamais été totalement indisponible |
| **Le scan de vulnérabilités à l'origine de la hausse de bande passante** | Les 3 721 requêtes hostiles représentent environ 580 Ko sur la journée — les réponses d'erreur font 153 à 162 octets. Négligeable |

## 7. Cause probable

**Niveau de certitude : hypothèse la plus compatible avec les données,
non démontrée.** Une confirmation exige un accès au serveur, dont
l'investigation n'a pas disposé.

Chaîne causale, en remontant depuis l'impact :

1. Les clients ne pouvaient pas finaliser leurs commandes
   → parce que l'application renvoyait des erreurs 500, 502 et 503
2. → parce que la chaîne de service était indisponible par intermittence,
     et lente le reste du temps (facteur 3,9 sur la latence)
3. → parce qu'une ressource partagée par toutes les requêtes — base de
     données, pool de connexions, ou ressource système de la machine — était
     saturée ou inaccessible
4. → **les données s'arrêtent ici.**

Trois caractéristiques orientent vers une **tâche planifiée** plutôt que
vers une défaillance matérielle ou logicielle :

- la première erreur survient à **18:00:00**, à la seconde près sur le
  basculement de l'heure ; une dégradation progressive ne commence pas à
  une heure ronde
- la durée est de **deux heures pleines**
- le retour à la normale est **automatique**, sans intervention humaine ;
  une panne matérielle ne se répare pas toute seule à heure fixe

Les candidats compatibles, par ordre de vraisemblance : une tâche de fond
nocturne déclenchée trop tôt (export comptable, sauvegarde, réindexation)
monopolisant la base ; un déploiement effectué à 18h et annulé à 20h ; une
fenêtre de maintenance chez un prestataire tiers.

## 8. Angles morts

L'analyse repose sur **une seule source** : le log d'accès du serveur web,
sur **une seule journée**. Ce que cette source ne peut pas montrer :

| Ce qui manque | Ce que ça empêche de conclure |
|---|---|
| Logs applicatifs (`journalctl -u velocite`) | Le message d'erreur exact, la pile d'appel, l'origine applicative des 500 |
| Métriques système de la machine (CPU, mémoire, I/O, réseau) | Si la machine elle-même était saturée |
| Métriques de la base de données (connexions, requêtes lentes, verrous) | L'hypothèse principale reste invérifiable |
| Liste des tâches planifiées (`crontab`, timers systemd) | L'hypothèse de la tâche de fond ne peut être ni confirmée ni écartée |
| Historique des déploiements | L'hypothèse du déploiement annulé est inexplorée |
| Logs des jours précédents et suivants | Impossible de dire si l'incident est **isolé ou récurrent** — c'est pourtant la première question à poser |

Une limite propre à la source elle-même : un log d'accès ne contient que les
requêtes **parvenues au serveur**. Les clients dont la connexion a expiré
avant d'obtenir une réponse, ou qui ont abandonné avant d'envoyer leur
requête, n'y figurent pas. **L'impact réel est donc supérieur aux chiffres
de ce document**, dans une proportion inconnue.

## 9. Constats annexes
> Les adresses des sources hostiles sont conservées en clair au titre de la sécurité du système d'information (intérêt légitime). Les adresses des visiteurs légitimes ne figurent pas dans ce document.

Observations issues de l'investigation, **sans lien établi avec l'incident**.

### Fiche produit anormalement lente — à traiter en priorité

`/produit/btwin-riverside-500` répond en **3,645 s** de moyenne sur 2 340
appels, contre 0,571 s et 0,535 s pour les deux autres fiches produit, à
trafic comparable et sur le même gabarit. Facteur 6,4.

Le comportement est **permanent** : il précède l'incident et persiste
après. Causes habituelles : requête N+1, index manquant, média non
redimensionné, appel synchrone à un service externe.

Cette page est consultée 2 340 fois par jour. Chaque seconde d'attente
supplémentaire dégrade le taux de conversion.

### Scan de vulnérabilités automatisé

l'IP 45.227.253.109 a émis 2 713 requêtes sur 24 h vers des chemins caractéristiques
d'une reconnaissance automatisée : `/wp-admin/`, `/.env`, `/.git/config`,
`/backup.sql`, `/phpmyadmin/`. User-agent `python-requests/2.31.0`, non
déguisé. Rythme d'environ 2 requêtes par minute, sous les seuils de
détection usuels.

**Aucune compromission.** Les 2 713 requêtes ont reçu 2 713 réponses 404 de
162 octets, servies par le serveur web sans que l'application soit
sollicitée. Vérifié par : `awk '$1=="45.227.253.109" && $9!=404'` → zéro ligne.

### Tentative de force brute sur l'authentification

L'IP 193.106.191.44 a émis 1 008 requêtes `POST /admin/login`, toutes refusées
en 403 par le proxy, en 0,011 s de moyenne. La logique d'authentification
n'a jamais été atteinte.

### Liens morts

Après soustraction des 2 713 requêtes du scanner, il reste **833 erreurs
404** émises par des visiteurs légitimes, réparties sur des centaines d'IP.
Aucune ne dépasse le seuil de 100, ce qui écarte un lien mort massivement
diffusé — il s'agit de bruit de fond.

## 10. Actions

| # | Action | Type | Propriétaire | Échéance |
|---|---|---|---|---|
| 1 | Lister les tâches planifiées (`crontab -l` de tous les utilisateurs, `systemctl list-timers`) et identifier celles actives entre 18h et 20h | Priorité | | |
| 2 | Vérifier l'historique des déploiements du 11/10 entre 17h et 21h | Priorité | | |
| 3 | Extraire les métriques de la base de données sur la plage 17h–21h : connexions actives, requêtes lentes, verrous | Priorité | | |
| 4 | Créer une alerte sur le taux de réponses 5xx dépassant 1 % sur 5 minutes | Priorité | | |
| 5 | Créer une alerte sur le p95 du temps de réponse dépassant 0,9 s sur 5 minutes | Priorité | | |
| 6 | Porter la rétention des logs d'accès à 30 jours pour permettre la détection de récurrences | Amélioration | | |
| 7 | Instrumenter `/produit/btwin-riverside-500` pour localiser les 3,6 s (requêtes SQL, appels externes, taille des médias) | Amélioration | | |
| 8 | Mettre en place une limitation de débit par IP sur le serveur web | Amélioration | | |
| 9 | Vérifier qu'aucun des chemins ciblés par le scan ne renvoie autre chose qu'un 404 | Amélioration | | |

## 11. Ce qui a bien fonctionné

- **Le format de log contenait le temps de réponse.** Ce champ ne fait pas
  partie du format Nginx par défaut ; quelqu'un l'a ajouté délibérément.
  Sans lui, la dégradation de latence — l'indice qui a orienté vers une
  contention plutôt qu'un plantage — était invisible.
- **Les requêtes hostiles n'ont jamais atteint l'application.** Les 404 et
  les 403 ont été servis par le serveur web en moins de 10 ms. La séparation
  des responsabilités entre proxy et application a joué son rôle.
- **Le service est revenu seul.** Aucune intervention manuelle n'a été
  nécessaire, aucune donnée n'a été perdue.
- **Le format de log homogène** a permis de mener l'analyse complète en
  quelques commandes, sans outil spécialisé.
