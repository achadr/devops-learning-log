# DNS — l'essentiel

> Diagnostiquer une résolution, lire une réponse, comprendre le cache.
> Les ⚠ marquent les pièges rencontrés le 19/10 — à relire en priorité.
> Tous les chiffres viennent de captures réelles.

---

## ⚠ Les paires à ne pas inverser

Mode d'erreur dominant au QCM du 19/10 (4 inversions sur 8 erreurs) : les deux concepts
sont connus, l'étiquette est placée du mauvais côté. **À relire en premier.**

| | D'un côté | De l'autre |
|---|---|---|
| **Outils** | `getent hosts` **voit** `/etc/hosts` (chemin de l'appli) | `dig` **ignore** `/etc/hosts` (DNS pur) |
| **Échec** | `NXDOMAIN` = le nom n'existe pas → **réponse NORMALE** | `SERVFAIL` = **PANNE** du résolveur |
| **Zéro réponse** | `NXDOMAIN` = le **nom** n'existe pas | `NODATA` (`NOERROR`+0) = le nom existe, pas ce **type** |
| **Refus** | `REFUSED` = **réponse explicite**, un serveur est là (≈ REJECT) | *timeout* = **silence**, rien n'est prouvé (≈ DROP) |
| **Nom** | `api.stripe.com.` avec point = **absolu**, 1 requête | `api.stripe.com` sans point = **relatif**, candidats fabriqués |
| **Récursion** | `rd` = le **client demande** | `ra` = le **serveur accepte** |
| **Fraîcheur** | `aa` présent = **première main** | `aa` absent = **cache**, possiblement périmé |
| **Durée de cache** | TTL de l'enregistrement = l'enregistrement **existe** | `minimum` du `SOA` = **l'absence** (cache négatif) |
| **`NS`** | chez le **parent** = sert à **trouver** la zone (TTL 48 h) | dans la **zone** = déclaration officielle de l'enfant |
| **Port 53** | UDP seul autorisé → **seules les grosses** réponses cassent | UDP+TCP → tout passe |

---

## La chaîne de résolution

```
application
 └─ résolveur système (libc)  ──lit──►  /etc/nsswitch.conf
                                        « hosts: files dns »  ← l'ORDRE des sources
      ├─ files ─► /etc/hosts            ⚠ AUCUN paquet réseau émis
      └─ dns ──► /etc/resolv.conf       quel serveur interroger
                  └─ RÉSOLVEUR RÉCURSIF (cache)
                       ├─ racine (.)     → « voici qui gère .com »
                       ├─ TLD (.com)     → « voici qui gère github.com »
                       └─ AUTORITAIRE    → LA réponse (drapeau aa)
```

- ⚠ **il n'existe pas « un » serveur DNS** qui détiendrait les correspondances
  - des centaines de millions de noms → aucune machine, aucune organisation ne peut les tenir
  - chaque étage ne connaît que **le maillon suivant** — même structure qu'une table de routage
- le serveur de `/etc/resolv.conf` ne détient **pas** la vérité : il a un **cache**
- ⚠ un nom présent dans `/etc/hosts` **court-circuite tout** : ni requête, ni cache, ni délégation

### `dig` ≠ `getent` ⚠

| Outil | Chemin suivi | Question à laquelle il répond |
|---|---|---|
| `getent hosts <nom>` | suit `nsswitch` → `files` puis `dns` | **ce que l'application va obtenir** |
| `dig <nom>` | client DNS pur, **ignore `/etc/hosts`** | **ce que le DNS répond** |

> **Quand les deux divergent, quelque chose de local interfère.** Diagnostic en deux commandes.

- l'incident classique : `dig` donne la bonne IP, l'application tape sur l'ancienne → `/etc/hosts`
- et son inverse : « ça marche sur ma machine » → une ligne dans `/etc/hosts`
- `getent` sort avec le **code 2** si le nom est introuvable (utile sous `set -e`)

### Récursif vs itératif

Deux **rôles dans la même résolution**, pas deux types de DNS :

- le **client** envoie une requête **récursive** : « donne-moi la réponse finale »
- le **résolveur** envoie des requêtes **itératives** : chaque étage renvoie vers le suivant
- les serveurs racine et de TLD **refusent** la récursion — vérifié : `WARNING: recursion
  requested but not available`

| Serveur interrogé | Drapeaux observés | Lecture |
|---|---|---|
| `a.root-servers.net` | `qr rd` | renvoi · pas de récursion · pas autoritaire |
| `8.8.8.8` | `qr rd ra` | récursif · réponse de **cache** |
| `ns-421.awsdns-52.com` | `qr aa rd` | **autoritaire** · pas de récursion |

- `rd` = *recursion desired* (le client demande) · `ra` = *recursion available* (le serveur accepte)
- **`aa` est le seul drapeau qui garantit une réponse de première main.** Sans lui : du cache.

---

## Lire une réponse `dig`

```
;; ->>HEADER<<- status: NOERROR          ← LE statut : la cause est là
;; flags: qr aa rd ra;  ANSWER: 1, AUTHORITY: 8, ADDITIONAL: 3
;; QUESTION SECTION      la question, renvoyée telle quelle
;; ANSWER SECTION        la réponse — TTL en 2e colonne
;; AUTHORITY SECTION     qui fait autorité / le SOA sur un échec
;; ADDITIONAL SECTION    les IP des serveurs cités (glue) + pseudo-section OPT
;; Query time            0-3 ms = cache · 10-100 ms = réseau
```

- ⚠ **`+short` masque le statut** → `+short` pour scripter, `dig` nu pour **diagnostiquer**
- `ANSWER: 0` + des `NS` dans `AUTHORITY` = un **renvoi**, pas une réponse
- drapeaux : `qr` réponse · `aa` autoritaire · `tc` tronqué · `rd`/`ra` récursion

---

## La délégation

- la zone parente contient les **`NS`** de ses enfants — pas leur contenu
  - acheter un domaine = **faire écrire ces `NS` dans la zone parente**, rien d'autre
- **glue records** : le parent fournit aussi les **IP** des serveurs, dans `ADDITIONAL`
  - sinon dépendance circulaire (résoudre le nom du serveur de noms)
- ⚠ **un serveur ne fournit de colle que pour les noms de sa propre zone**
  - observé : `.com` donne l'IP de `ns-421.awsdns-52.com` mais pas celles des 7 autres
    (`.net`, `.org`, `.co.uk`) → `ADDITIONAL: 27` chez la racine contre `ADDITIONAL: 3` ici
  - conséquence : serveurs de noms **dans sa propre extension** = une étape de moins
- 13 identités racine (`a.`→`m.root-servers.net`), des centaines d'instances en **anycast**
  - la limite à 13 est historique : la liste devait tenir dans 512 octets d'UDP

### ⚠ Les `NS` existent à DEUX endroits

```
zone .com        (PARENT)  github.com.  172800  IN  NS  ...    48 h
zone github.com  (ENFANT)  github.com.     900  IN  NS  ...    15 min
```

Deux jeux de données distincts, gérés par deux entités, avec leurs TTL propres — **et ils
peuvent se contredire** (incohérence de délégation).

> **Changer de serveurs de noms se fait toujours en deux endroits : chez le registraire
> (le parent) ET dans la zone (l'enfant).** Oublier le parent = 48 h chez l'ancien fournisseur.

### Redondance

GitHub a **8 `NS` chez 2 fournisseurs** (Route 53 + NS1). En octobre 2016, une attaque contre
Dyn — fournisseur unique — a rendu Twitter, Spotify, Reddit et GitHub inaccessibles : les
serveurs web tournaient, mais **plus personne ne résolvait leurs noms**.

---

## Les enregistrements

| Type | Contenu | Usage réel |
|---|---|---|
| `A` | une IPv4 | le cas de base |
| `AAAA` | une IPv6 | `localhost` répond `::1` en premier |
| `CNAME` | **un autre nom** | alias vers un équilibreur de charge managé |
| `MX` | serveur de messagerie + **priorité** | **le plus petit nombre gagne** · ordre non garanti |
| `TXT` | texte libre | SPF, DKIM, et **preuve de possession** |
| `NS` | serveurs autoritaires | porte la délégation |
| `SOA` | paramètres de la zone | dont le **cache négatif** |
| `PTR` | IP → nom | journaux, réputation de messagerie |
| `SRV` | service + port + priorité | découverte de service |

### Le `SOA`, champ par champ

```
com.  900  IN  SOA  a.gtld-servers.net. nstld.verisign-grs.com.
                    1792421974  1800  900  604800  900
```

| Valeur | Nom | Rôle |
|---|---|---|
| `a.gtld-servers.net.` | MNAME | le serveur **primaire** |
| `nstld.verisign-grs.com.` | RNAME | le responsable — **le 1er point remplace le `@`** |
| `1792421974` | SERIAL | version de la zone |
| `1800` | REFRESH | fréquence de vérification par les secondaires |
| `900` | RETRY | délai de reprise après échec |
| `604800` | EXPIRE | 7 j sans contact → le secondaire **cesse de répondre** |
| `900` | **MINIMUM** | ⚠ **durée du cache des réponses négatives** |

- ⚠ **le serial doit TOUJOURS augmenter**, sinon les secondaires servent l'ancienne zone
  - conventions : `AAAAMMJJnn` (`2026101901`) ou horodatage Unix
- l'`EXPIRE` est un garde-fou : mieux vaut **aucune** réponse qu'une réponse périmée

### ⚠ Les trois règles du `CNAME`

1. **un `CNAME` ne cohabite avec AUCUN autre type** sur le même nom (exclusivité absolue)
2. **donc un `CNAME` est impossible à l'apex** — l'apex porte obligatoirement `SOA` + `NS`
3. **un `CNAME` coûte une résolution de plus** — le résolveur doit suivre l'alias

Vérifié : `dig CNAME github.com` → `NOERROR` avec `ANSWER: 0`, et le `SOA` dans `AUTHORITY`.
Ce `SOA` **occupe la place**.

La chaîne revient entière dans `ANSWER` :
```
www.github.com.  619  IN  CNAME  github.com.      ← TTL long  (alias stable)
github.com.       48  IN  A      140.82.121.4     ← TTL court (adresse mobile)
```
Deux comptes à rebours **indépendants**.

### Le problème de l'apex, et les trois sorties

```
www.boutique.fr.   CNAME  lb-1234.elb.provider.net.    ✅
boutique.fr.       CNAME  lb-1234.elb.provider.net.    ❌ INTERDIT (règle 2)
```

| Solution | Principe |
|---|---|
| **`A` vers une IP statique réservée** | **la réponse GCP** — on réserve l'IP globale, **puis** on configure le nom |
| `ALIAS` / `ANAME` | type propriétaire, résolu côté serveur, ne renvoie que des `A` — hors standard |
| redirection HTTP `301` | historique, un aller-retour de plus, robuste |

### `TXT` et la preuve de possession

> Le service donne une chaîne aléatoire → tu la publies en `TXT` → il la retrouve.
> **Seul quelqu'un qui contrôle la zone a pu l'y mettre.**

- épine dorsale du défi **`DNS-01`** d'ACME : certificat **sans exposer de serveur web**,
  et seule voie pour un certificat générique (`*.boutique.fr`)
- `v=spf1 include:_spf.google.com ~all` → qui a le droit d'envoyer du courrier pour ce domaine
- ces lignes s'accumulent pendant des années, personne n'ose les supprimer

### `PTR` — un indice, jamais une preuve

Le `PTR` est contrôlé par le propriétaire du **bloc d'adresses**, pas du nom. La vérification
réelle est le **FCrDNS** : IP → nom → **re-résoudre le nom** → retomber sur l'IP de départ.

---

## TTL et cache

```bash
dig github.com @8.8.8.8 | grep -A1 "ANSWER SECTION"  # TTL 60
sleep 10                                              #
dig github.com @8.8.8.8 | grep -A1 "ANSWER SECTION"  # TTL 46  ← décrémenté
```

Le TTL est un **compte à rebours décrémenté par chaque intermédiaire**. À 0, l'entrée est
jetée et la question repart vers l'autoritaire.

### Le TTL se choisit par type d'enregistrement

| Enregistrement | TTL mesuré | Pourquoi |
|---|---|---|
| `github.com` **A** | **60** (1 min) | doit pouvoir basculer vite en cas de panne |
| `github.com` **NS** | **172800** (48 h) | ne change presque jamais |
| `com.` **SOA** minimum | **900** (15 min) | cache négatif de la zone |
| `fr.` **SOA** minimum | **600** (10 min) | chaque zone fixe le sien |

> **Le TTL se choisit sur la vitesse à laquelle on pourrait avoir besoin de changer
> l'enregistrement.** Arbitrage réactivité ↔ robustesse.

- un TTL **court** = basculement rapide, mais charge élevée **et fragilité** : si les
  autoritaires tombent, le nom cesse de résoudre en quelques minutes
- un TTL **long** = le cache devient un **amortisseur de panne** (24 h pour réparer)

### ⚠ « La propagation DNS » n'existe pas

Rien ne se propage, rien n'est poussé. **Les caches expirent**, chacun à son rythme selon le
moment où il a interrogé. D'où l'impression de délai aléatoire.

### ⚠ Migrer un nom sans coupure

**Le piège : l'abaissement du TTL est lui-même soumis à l'ancien TTL.** Un résolveur qui
détient l'enregistrement avec `TTL=86400` ne découvrira le nouveau TTL qu'en reposant la
question — donc jusqu'à 24 h plus tard.

```
J−2  TTL : 86400 → 300          (n'atteindra certains caches que dans 24 h)
J−1  ── attendre 86400 s complètes ──
     tous les caches détiennent maintenant TTL=300
J−1  le nouveau serveur est prêt, testé PAR SON IP (pas par le nom)
J0   on change l'enregistrement A
J0   +300 s : tous les résolveurs ont basculé
J0   on LAISSE l'ancien serveur allumé ≥ 24 h (filet)
J+1  TTL : 300 → 86400          (on revient à la robustesse)
```

### ⚠ Cache négatif

Un `NXDOMAIN` est mis en cache pour la durée du champ `minimum` du `SOA` de **l'ancêtre
existant le plus proche** (le nom demandé n'ayant pas de zone).

- il n'existe **pas pour le confort local** : il **protège la hiérarchie** d'une charge
  massive de requêtes pour des noms inexistants (fautes de frappe, robots, suffixes bidon)
- ⚠ **ce n'est pas la création qui tarde, c'est l'absence qui est en cache**
- > **Ne jamais interroger un nom avant de l'avoir créé.** Une seule requête prématurée
  > empoisonne le cache pour la durée du minimum.

### Quel cache ?

Linux n'a **pas** de cache DNS système par défaut (`hosts: files dns`, aucune couche de cache).
Le cache est chez le **résolveur récursif**, et le navigateur a le sien. En diagnostic, savoir
**lequel** on vide.

### ⚠ Ne jamais figer une IP obtenue par résolution

Observé : deux adresses différentes pour `github.com` en 14 secondes, l'autoritaire alternant
(`ANSWER: 1` à chaque fois, adresse différente).

- répartition **côté serveur** → le client ne connaît qu'une adresse, **aucun repli**
  → le TTL de 60 s est alors le **seul** mécanisme de basculement
- l'autre école : plusieurs `A` renvoyés, repli **côté client**, TTL long
- jamais d'IP résolue dans un fichier de configuration ni dans une règle de pare-feu
  → on autorise un **nom**, ou un **bloc publié** par le fournisseur

---

## Diagnostic

### Les statuts — la cause est dans l'en-tête

| Statut | `ANSWER` | Signification | Où chercher |
|---|---|---|---|
| `NOERROR` | ≥ 1 | ça marche | — |
| `NOERROR` | **0** | ⚠ **NODATA** : le nom existe, pas ce **type** | mauvais type demandé |
| `NXDOMAIN` | 0 | **le nom n'existe pas** | faute de frappe, enregistrement absent |
| `SERVFAIL` | — | le résolveur **n'a pas pu** | zone, DNSSEC, autoritaires injoignables |
| `REFUSED` | — | le serveur **refuse** | pas récursif pour toi, filtrage par IP |
| *silence* | — | aucune réponse | port 53 filtré, mauvaise IP, pare-feu |

**Les trois confusions coûteuses :**

```
NXDOMAIN  vs  NODATA     même « 0 réponse », causes sans rapport
NXDOMAIN  vs  SERVFAIL   réponse NORMALE et fiable  vs  PANNE
REFUSED   vs  timeout    REJECT (réponse explicite) vs DROP (silence)
```

- `NXDOMAIN` : **le DNS a parfaitement fonctionné** → cherche la faute de frappe
- `SERVFAIL` : **le DNS est en panne** → zone, signatures, accessibilité
- un `REFUSED` prouve qu'un serveur DNS tourne là et t'a entendu · un timeout ne prouve **rien**

### ⚠ L'heuristique : choisir le test qui coupe en deux

Une mauvaise première commande **explore**. Une bonne première commande **élimine la moitié des
causes**, quel que soit son résultat. Le problème est soit **chez toi**, soit **en amont** :

```bash
dig <nom> @8.8.8.8          # ← LA première commande
```

Un résolveur qu'on ne contrôle pas tranche en un aller-retour.
**Ne pas** commencer par relancer un service ou vider un cache : ce sont des actions, pas des
mesures — elles ne réduisent rien et détruisent parfois la preuve.

### L'arbre

```
« le site ne répond plus »
│
└─ dig <nom> @8.8.8.8
   │
   ├─ RÉPOND la bonne adresse  →  le DNS public va bien
   │  └─ dig <nom>   (résolveur par défaut)
   │     ├─ répond pareil  →  ⚠ CE N'EST PAS DU DNS
   │     │                     ss -tlnp      le service écoute-t-il ?
   │     │                     curl -v       port ? certificat ?
   │     │                     getent hosts  /etc/hosts parasite ?
   │     └─ échoue / diffère  →  problème LOCAL
   │                             /etc/resolv.conf · /etc/hosts · search/ndots
   │
   └─ ÉCHOUE  →  problème EN AMONT, il touche tout le monde
      │           → LIRE LE STATUT
      ├─ NXDOMAIN  dig NS <zone> @8.8.8.8      la délégation existe-t-elle ?
      │            dig <nom> @<autoritaire>    présent à la source ?
      │            → présent à la source mais pas ailleurs : cache négatif
      ├─ NODATA    mauvais type demandé
      ├─ SERVFAIL  dig <nom> +cd   ⚠ désactive la validation DNSSEC
      │            → réussit avec +cd ⇒ c'est DNSSEC
      ├─ REFUSED   mauvais serveur interrogé
      └─ timeout   dig <nom> @8.8.8.8 +tcp    UDP bloqué, TCP ouvert ?
```

> ⚠ **`dig` qui répond prouve que le DNS va bien, et RIEN D'AUTRE.**
> Des heures se perdent à creuser le DNS alors que le service n'écoute pas.

### ⚠ Un résolveur intermédiaire peut mentir par omission

Mesuré sur `10.255.255.254` (proxy DNS de WSL) :

```
résolveur WSL   NXDOMAIN   AUTHORITY: 0    0 ms     52 octets   ← SOA jeté
8.8.8.8         NXDOMAIN   AUTHORITY: 1   15 ms    125 octets   ← SOA présent
```

> **Quand une réponse paraît incomplète ou incohérente, interroger un résolveur en amont
> avant de conclure.** Quand deux instruments divergent, l'écart *est* l'information.

---

## `search`, `ndots` et le point final

Le **point final** désigne la racine : le nom est **absolu**, rien ne lui sera ajouté. Toutes
les sorties `dig` l'affichent (`github.com.`, `com.`). Un nom **sans** point final est relatif
et peut être complété.

```
search  monespace.svc.cluster.local  svc.cluster.local  cluster.local
options ndots:5
```

### ⚠ `ndots` décide de l'ORDRE, il ne filtre rien

```
fonction résoudre(nom) :
    si nom se termine par "." :  return interroger(nom)        # absolu, fini

    # ndots utilisé ICI, UNE SEULE FOIS, sur le nom TAPÉ
    si compter_points(nom) >= ndots :
        candidats = [nom] + [nom + "." + s  pour s dans search]
    sinon :
        candidats = [nom + "." + s  pour s dans search] + [nom]

    pour chaque c dans candidats :        # ndots N'APPARAÎT PAS ici
        si interroger(c) réussit : return
    return NXDOMAIN
```

- `compter_points` s'applique au nom **tapé**, jamais aux candidats
- **tous** les suffixes de `search` donnent un candidat, quelle que soit sa longueur
- le `si` ne change que **la position de `[nom]`** dans la liste
- **analogie `$PATH`** : il gouverne l'**ordre** des répertoires essayés, pas l'existence du
  binaire dans chacun. Chaque échec est un « pas trouvé » normal.

### Le coût sur Kubernetes

```
api.stripe.com   →  2 points < 5  →  les suffixes d'abord
    api.stripe.com.monespace.svc.cluster.local   NXDOMAIN
    api.stripe.com.svc.cluster.local             NXDOMAIN
    api.stripe.com.cluster.local                 NXDOMAIN
    api.stripe.com                               ✅
```

**4 requêtes au lieu d'1**, et **×2** pour IPv4 + IPv6 → **8 paquets**, multipliés par chaque
appel sortant de chaque pod. Cause documentée de saturation du DNS interne et de latence
inexpliquée sur les appels externes.

**La correction tient en un caractère :** `api.stripe.com.`
(ou `ndots: 1` dans le `dnsConfig` du pod, au prix des noms courts de services)

---

## UDP, TCP et la taille

```
;; OPT PSEUDOSECTION:
; EDNS: version: 0, flags:; udp: 4096     ← « je peux recevoir 4096 octets »
```

- limite UDP historique : **512 octets** (1987, transmissible sans fragmentation)
  — même contrainte qui a fixé à 13 le nombre de serveurs racine
- **EDNS0** lève le plafond : mesuré, `dig TXT google.com` = **1187 octets en UDP, sans `tc`**
- à voir : `dig TXT google.com +noedns +ignore` → le drapeau **`tc`** apparaît

```
réponse trop grosse  →  réponse TRONQUÉE + drapeau tc
                     →  le client REFAIT la requête en TCP
                     →  TCP n'a pas de limite de taille
```

> ⚠ **Le port 53 doit être ouvert en UDP _et_ en TCP.**
> Ne laisser que l'UDP casse uniquement les **grosses** réponses (`TXT`, DNSSEC, nombreux
> `MX`) : tout marche sauf certaines choses, de façon capricieuse. Le pire type de panne.

Et **les gros datagrammes UDP doivent passer** : des équipements qui bloquent l'UDP fragmenté
ou plafonnent à 512 produisent des lenteurs et des `SERVFAIL` sans cause apparente.

---

## GCP

- **`169.254.169.254`** = serveur de métadonnées, nom `metadata.google.internal`
  - dans `169.254.0.0/16`, le bloc **lien-local** → joignable **uniquement depuis la VM**,
    ce qui est précisément la propriété de sécurité recherchée
  - donne à la VM son identité, ses attributs et ses jetons de compte de service
- apex d'une zone → **IP statique globale réservée** + `A` (voir les règles du `CNAME`)
- zones **privées** de Cloud DNS : résolvables seulement depuis le VPC autorisé

---

## Commandes

```bash
dig <nom>                        # diagnostic : statut + sections + drapeaux
dig <nom> +short                 # script uniquement — ⚠ masque le statut
dig <nom> @8.8.8.8               # LA première commande d'un diagnostic
dig <type> <nom>                 # A AAAA CNAME MX TXT NS SOA SRV
dig -x <ip>                      # résolution inverse (PTR)
dig +trace <nom>                 # toute la descente, racine → autoritaire
dig NS <zone> @a.root-servers.net        # la délégation, vue du parent
dig <nom> @<serveur-autoritaire>         # la source — le drapeau aa doit apparaître
dig <nom> +cd                    # sans validation DNSSEC → isole un SERVFAIL
dig <nom> +tcp                   # force TCP → isole un filtrage UDP
dig <nom> +noedns +ignore        # revient à 512 octets → fait apparaître tc
getent hosts <nom>               # le chemin de l'APPLICATION (voit /etc/hosts)
grep hosts /etc/nsswitch.conf    # l'ordre des sources
cat /etc/resolv.conf             # le résolveur, search, ndots
sudo tcpdump -i any -n port 53   # le DNS sur le fil (interroger @8.8.8.8 explicitement)
```
