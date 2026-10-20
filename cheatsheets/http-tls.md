# HTTP et TLS — l'essentiel

> Lire une trace, attribuer un code de statut, diagnostiquer un échec TLS.
> Les ⚠ marquent les pièges rencontrés le 20/10 — à relire en priorité.
> Tous les exemples viennent de captures réelles.

---

## ⚠ Les paires à ne pas inverser

| | D'un côté | De l'autre |
|---|---|---|
| **Qui émet** | `500` = **l'application** a tourné et planté → il y a une trace | `502` = **le proxy** parle, l'app n'a peut-être pas été jointe |
| **Amont vivant ?** | `502` = aucune garantie | `504` = il a **attendu**, donc la connexion a été acceptée |
| **Refus** | `401` = **identité** (authentification) · porte `WWW-Authenticate` | `403` = **permission** (autorisation) |
| **Redirection** | `301` permanent · **mis en cache, irréversible** | `302` temporaire · **réversible** |
| **Méthode** | `301`/`302` → le client peut transformer `POST` en `GET` | `307`/`308` → méthode et corps **préservés** |
| **Négociation** | `415` = « ton `Content-Type` m'est inconnu » (ce que tu **envoies**) | `406` = « je ne sais pas produire ton `Accept` » |
| **Nom du site** | **SNI** (TLS) → choisit le **certificat** · **en clair** | **`Host`** (HTTP) → choisit le **site** · chiffré |
| **Attaquant** | **passif** (écoute) → le chiffrement suffit | **actif** (au milieu) → il faut l'**authentification** |
| **Fichiers Let's Encrypt** | `cert.pem` = la feuille **seule** ❌ | `fullchain.pem` = feuille + intermédiaires ✅ |
| **Économie du cache** | `ETag` + `304` → l'aller-retour a lieu, le **corps** est épargné | `max-age` → **aucune requête** émise |

---

## Structure d'un message HTTP/1.1

```
GET /produit/42 HTTP/1.1\r\n       ← LIGNE DE REQUÊTE : méthode, chemin, version
Host: boutique.fr\r\n              ┐
User-Agent: curl/8.5.0\r\n         │ EN-TÊTES, « Nom: valeur »
Accept: */*\r\n                    ┘
\r\n                               ← ⚠ LIGNE VIDE : fin des en-têtes
{"quantite": 2}                    ← CORPS (optionnel)
```

La réponse a la même forme, avec une **ligne de statut** : `HTTP/1.1 200 OK`.

- ⚠ **la ligne vide est le délimiteur.** Sans elle, le serveur attend d'autres en-têtes
  → une requête mal formée **bloque**, elle n'échoue pas. Encore une panne silencieuse.
- à faire une fois, pour voir le protocole brut :
  ```bash
  printf 'GET / HTTP/1.1\r\nHost: example.com\r\n\r\n' | nc -w 3 example.com 80
  ```

### Où finit le corps ?

Sur une connexion `keep-alive`, la fermeture ne peut plus servir de signal (c'était le
mécanisme de HTTP/1.0). Deux remplaçants :

```
Content-Length: 1256          le client lit exactement 1256 octets
Transfer-Encoding: chunked    morceaux préfixés par leur taille, en HEXADÉCIMAL
                              un morceau de taille 0 marque la fin
```

Observé : `241` en hexadécimal = **577** octets, soit exactement le total annoncé par `curl`
sur la même page servie en HTTP/2.

- ⚠ **ni l'un ni l'autre** → le client attend indéfiniment. Pas d'erreur, un **blocage**.

---

## Lire une trace `curl -v`

```
>   ce que TU ENVOIES          (requête HTTP)
<   ce que tu REÇOIS           (réponse HTTP)
*   les commentaires de CURL   sur son propre travail
```

> ⚠ **DNS, TCP et TLS n'apparaissent QUE sur les lignes `*`.** Si HTTP échoue, c'est souvent
> **avant le premier `>`** — donc on lit les `*` d'abord.

---

## HTTP/1.1, 2 et 3

| | Transport | Nature | Nom du site |
|---|---|---|---|
| HTTP/1.1 | TCP | **textuel** | `Host:` |
| HTTP/2 | TCP | **binaire**, en-têtes compressés | `:authority` |
| HTTP/3 | **QUIC sur UDP** | binaire | `:authority` |

- en HTTP/2, les **pseudo-en-têtes** portent la ligne de requête éclatée :
  `:method`, `:path`, `:scheme`, `:authority`
- ⚠ `curl` affiche `> GET / HTTP/2` : **ces octets ne circulent pas**, c'est une traduction.
  La vérité est dans les lignes `*` au-dessus.
  → **toujours se demander si on regarde les octets ou une représentation**
- HTTP/2 **impose les noms d'en-têtes en minuscules** (la compression repose sur un dictionnaire)
- **ALPN** négocie la version **à l'intérieur de la poignée de main TLS**, sans aller-retour
- `alt-svc: h3=":443"; ma=86400` → le serveur annonce HTTP/3 ; QUIC étant de l'**UDP**,
  cela a des conséquences sur les pare-feu

---

## Les en-têtes d'exploitation

### `Host` — une IP, des milliers de sites

Vérifié : même IP, même port, même requête, **seul `Host` change** → `200` puis `409`.

> **Le DNS t'amène à une machine. L'en-tête `Host` t'amène au bon site sur cette machine.**
> Deux étages de résolution. Et le rejet survient **après** l'établissement de TCP :
> réseau ✅ · TCP ✅ · HTTP ❌.

### La symétrie `Content-*` / `Accept-*`

| Je décris ce que **j'envoie** | Je demande ce que **je veux** |
|---|---|
| `Content-Type: application/json` | `Accept: application/json` |
| `Content-Encoding: gzip` | `Accept-Encoding: gzip, br` |
| `Content-Language: fr` | `Accept-Language: fr-FR, en;q=0.8` |

- **`Content-*` décrit le message où il se trouve · `Accept-*` décrit le message d'après**
- `q=` de 0 à 1 : une **préférence**, pas une exigence · absent = 1
- `charset=utf-8` fait partie du `Content-Type`, ce n'est pas un en-tête à part

### `Vary` — l'oubli qui casse les caches

> **Toute réponse qui varie selon un en-tête de requête doit déclarer `Vary` sur cet en-tête.**

```
sans Vary   →  clé du cache = URL seule
avec Vary   →  clé du cache = URL + valeur de l'en-tête déclaré
```

⚠ Le **premier** client reçoit la bonne réponse. **La victime est le suivant**, dont les
capacités diffèrent et qui reçoit une version qu'il ne sait pas lire. Bug qui ne se reproduit
que dans un certain ordre.

### `X-Forwarded-For` — l'adresse réelle du client

Derrière un proxy, l'application voit l'adresse source du `SYN` qu'elle a reçu, donc **celle
du proxy**. Toutes les lignes de journal portent la même IP.

```
CLIENT ──► CDN ──► répartiteur ──► APPLICATION
X-Forwarded-For: 203.0.113.50, 198.51.100.7, 10.0.0.5
                 └ client ────┘  └─ CDN ───┘  └ le tien ┘
                 le plus à GAUCHE = le plus ANCIEN
```

- ⚠ **c'est un en-tête HTTP ordinaire : n'importe quel client peut l'envoyer.** Le proxy
  **ajoute** à la suite, il ne remplace pas → **la valeur de gauche est contrôlée par
  l'attaquant**
- > **Règle : on remonte depuis la DROITE, on saute les proxys de confiance, on retient la
  > première adresse qui n'en fait pas partie.** L'injection est forcément à gauche de la
  > vraie valeur, donc hors de portée.
- limitation de débit ou blocage basés sur la valeur de **gauche** → contournables en une ligne
- nginx :
  ```nginx
  set_real_ip_from  10.0.0.5;        # ⚠ l'adresse EXACTE, pas un /8 entier
  real_ip_header    X-Forwarded-For;
  real_ip_recursive on;
  ```
- **conséquence pour un post-mortem** : une accusation fondée sur un en-tête falsifiable,
  sans frontière de confiance établie, n'est pas défendable. La mention à écrire :
  *« adresses des connexions TCP directes, sans intermédiaire, donc non falsifiables »*

---

## Les codes de statut, en diagnostic

> **Un code ne dit pas seulement ce qui s'est passé, il dit QUI a répondu.** Et celui qui
> répond n'est pas toujours l'application : un répartiteur, un proxy ou un pare-feu applicatif
> ont leurs propres conventions, parfois fantaisistes (observé : Cloudflare renvoie `409` pour
> un `Host` inconnu, là où `404` ou `421` conviendraient).

```
4xx   erreur du CLIENT   → regarde la requête
5xx   erreur du SERVEUR  → regarde le serveur
```

### Le quatuor des `5xx`

```
CLIENT  ──►  PROXY / RÉPARTITEUR  ──►  APPLICATION
```

| Code | Émis par | Signification | Où chercher |
|---|---|---|---|
| **500** | **l'application** | atteinte, exécutée, **a planté** | journaux **applicatifs** |
| **502** | **le proxy** | réponse **invalide ou absente** | l'app est-elle vivante ? morte en cours ? |
| **503** | proxy ou app | **aucune instance saine**, ou refus délibéré | santé des instances |
| **504** | **le proxy** | il a **attendu** trop longtemps | app vivante mais **trop lente** |

- ⚠ **des journaux applicatifs vides sur un `502` est le cas ATTENDU** : soit l'app n'a jamais
  été atteinte, soit elle est morte avant d'écrire. Ces journaux ne **peuvent** rien contenir.
- > **Ordre de lecture sur un `5xx` : journaux du PROXY → journaux SYSTÈME → journaux
  > APPLICATIFS.** Et non l'inverse, qui est le réflexe du développeur.

```bash
sudo tail -n 50 /var/log/nginx/error.log   # il NOMME la cause
journalctl -u <service> -n 50 --no-pager   # systemd a-t-il redémarré ?
systemctl status <service>                 # combien de redémarrages ?
sudo dmesg | grep -i oom                   # le tueur de mémoire est-il passé ?
```

| Message du proxy | Traduction |
|---|---|
| `connect() failed (111: Connection refused)` | rien n'écoute — processus mort |
| `upstream prematurely closed connection` | mort **en cours** de réponse |
| `no live upstreams` | toutes les instances marquées malsaines |
| `upstream timed out` | c'est un `504`, pas un `502` |

- `Restart=on-failure` transforme un plantage en `502` **intermittent** : le service meurt,
  systemd le relance en 5 s, et le proxy renvoie des `502` pendant ce temps. Illisible du
  dehors, parfaitement lisible dans `journalctl`.

### Lire une distribution de `5xx`

Observé sur `velocite-access.log` : **1100 × 500, 551 × 502, 536 × 503** (total 2187 ✓).

> **Un proxy réellement en panne produit des `502`/`503` _sans_ `500`** — l'application n'est
> jamais atteinte, donc elle n'émet rien. La présence de `500` **prouve** que le proxy
> transmettait et que l'application tournait. Le proxy est écarté comme cause.

Les trois codes décrivent alors **trois degrés d'une même défaillance** :

```
500  elle lève une exception          → échoue PROPREMENT
502  elle meurt en cours de réponse   → échoue BRUTALEMENT
503  aucune instance saine            → MOMENTANÉMENT ABSENTE
```

### Les autres

- `304 Not Modified` : `ETag: "a3f9"` → le client renvoie `If-None-Match: "a3f9"` → `304`
  **sans corps**. `Last-Modified`/`If-Modified-Since` est la version historique, moins fiable
  (pas de résolution sous la seconde).
- `499` (nginx seulement) : **le client a fermé avant la réponse**. Ce n'est pas ton erreur —
  mais un **pic de `499` signale une application si lente que les gens abandonnent**. Le
  symptôme n'est pas dans les `5xx`.
- ⚠ `303 See Other` est **le bon code** après une soumission de formulaire (il force le passage
  en `GET` et évite le renvoi), mais **il ne préserve pas la méthode** → pour une API, `307`/`308`.

---

## TLS — les trois garanties

```
1. CONFIDENTIALITÉ   personne sur le trajet ne peut LIRE
2. INTÉGRITÉ         personne sur le trajet ne peut MODIFIER
3. AUTHENTIFICATION  tu parles bien au détenteur du nom demandé
```

> **Le chiffrement sans authentification ne vaut rien.** Un attaquant au milieu négocie les
> clés **avec toi** : deux connexions parfaitement chiffrées, et il lit tout en clair.
> Tu n'as pas chiffré « vers la banque », tu as chiffré « vers celui qui a répondu ».

```
attaquant PASSIF (écoute)        → le chiffrement suffit
attaquant ACTIF (au milieu)      → seule l'AUTHENTIFICATION l'arrête
```

### ⚠ Ce que le certificat atteste réellement

La quasi-totalité des certificats sont **DV** (*Domain Validated*). L'autorité a vérifié **une
seule chose** : que le demandeur **contrôlait le domaine** — par un `TXT` ou un fichier servi.
C'est la preuve de possession du DNS, rien de plus.

```
https:// sur un site d'hameçonnage  →  PARFAITEMENT NORMAL
```

Le cadenas dit : *« ta connexion est privée, et tu parles au détenteur du nom affiché »*.
Il ne dit **rien** sur l'honnêteté de ce détenteur. Les certificats **OV**/**EV** vérifient
l'identité juridique ; les navigateurs ont **retiré** la barre verte des EV, personne ne la
regardait.

### Et c'est un NOM qui est validé

```
*  subjectAltName: host "example.com" matched cert's "example.com"
```

Pas l'adresse IP. D'où l'erreur sur `https://104.20.23.154` : le certificat ne contient pas
cette adresse. **Le DNS donne une IP, la validation porte sur le nom qui a servi à l'obtenir.**

---

## La poignée de main

```
OUT  Client hello              ← contient le SNI, EN CLAIR
IN   Server hello
IN   Encrypted Extensions      ← à partir d'ici tout est chiffré,
IN   Certificate                  y compris le certificat (nouveau en TLS 1.3)
IN   CERT verify
IN   Finished
OUT  Finished
```

- **TLS 1.3 = UN aller-retour.** TLS 1.2 en demandait deux → sur une liaison à 150 ms, on
  économise 150 ms par **nouvelle** connexion. C'est la raison opérationnelle d'exiger 1.3.

### SNI et `Host` — le même nom, deux étages

```
┌─ TLS : Client hello ───────────────────┐
│  SNI: example.com      ← EN CLAIR      │  → choisit le CERTIFICAT
└────────────────────────────────────────┘
      ↓ tunnel établi
┌─ HTTP : GET / ─────────────────────────┐
│  Host: example.com     ← chiffré       │  → choisit le SITE
└────────────────────────────────────────┘
```

- ⚠ **le SNI est en clair par nécessité CHRONOLOGIQUE** : il faut le nom pour choisir le
  certificat, le certificat pour établir le chiffrement, et le chiffrement pour cacher le nom.
  Boucle impossible. Le `Host` arrive après et profite du tunnel.
- conséquence : un fournisseur d'accès voit **quels sites** tu visites même en HTTPS.
  Le correctif s'appelle **ECH** (*Encrypted Client Hello*), en cours de déploiement.
- SNI mal configuré → **mauvais certificat présenté** · client trop vieux sans SNI →
  certificat par défaut du serveur. Dans les deux cas, symptôme `name mismatch`.

### Asymétrique puis symétrique

```
TLSv1.3 / TLS_AES_256_GCM_SHA384 / X25519 / id-ecPublicKey
          └─ symétrique ───────┘   └ échange ┘  └ certificat ┘
```

L'asymétrique est ~1000× plus lent : on l'utilise une fois pour convenir d'une clé, puis tout
passe en symétrique.

> ⚠ **Le certificat ne chiffre RIEN. Il authentifie l'échange de clés.**

### ⚠ Un certificat expiré

```
le chiffrement fonctionnerait parfaitement — les mathématiques ignorent le calendrier
c'est le CLIENT qui refuse, par POLITIQUE
```

Politique justifiée : un certificat expiré a peut-être été **révoqué** entre-temps, et la
vérification de révocation en temps réel est peu fiable → la date sert de **filet de dernier
recours**.

> La panne la plus bête du métier : tout fonctionne, et le service est inaccessible pour
> 100 % des utilisateurs à cause d'une date.

Et donc : `curl -k`, `verify=false` ne « masquent pas un avertissement gênant » — ils
**suppriment la garantie 3**, donc les deux autres par ricochet. Jamais en production.

---

## La chaîne de confiance

Observé sur `example.com` — **chaque `i:` est le `s:` du suivant** :

```
0  s: example.com
   i: Cloudflare TLS Issuing ECC CA 3   ─┐  valide 90 JOURS
1  s: Cloudflare TLS Issuing ECC CA 3   ─┘  valide 10 ans
   i: SSL.com TLS Transit ECC CA R2     ─┐
2  s: SSL.com TLS Transit ECC CA R2     ─┘  valide 15 ans
   i: SSL.com TLS ECC Root CA 2022      ─┐
3  s: SSL.com TLS ECC Root CA 2022      ─┘
   i: AAA Certificate Services            ← signature CROISÉE (racine ancienne,
                                            pour les clients qui ne connaissent pas SSL.com)
```

### Pourquoi une hiérarchie

```
niveau 0    clé privée sur un serveur web exposé à Internet   → risque MAXIMAL → 90 jours
niveau 1-2  clé dans un module matériel de l'autorité
niveau 3    clé dans un coffre, machine HORS LIGNE            → risque MINIMAL → 15 ans
```

> **La racine ne signe pas directement parce que sa clé doit rester hors ligne.** L'intermédiaire
> est **sacrifiable** : compromis, on le révoque et on le remplace ; la racine survit.
> Architecture de confinement du risque.

Et 90 jours **impose** l'automatisation : personne ne tient un calendrier trimestriel fiable.

### Où vit la confiance

```
le serveur envoie :  la feuille + les INTERMÉDIAIRES
le client possède :  la RACINE   (/etc/ssl/certs/ca-certificates.crt)
```

- mesuré : **121 autorités** dans le magasin local
- ⚠ **n'importe laquelle des 121 peut émettre un certificat valide pour n'importe quel
  domaine**, sans ton accord. La sécurité de l'ensemble est celle du maillon le plus faible
  parmi 121, répartis dans une vingtaine de juridictions.
- **DigiNotar, 2011** : autorité néerlandaise compromise, certificats frauduleux pour
  `*.google.com`, interception des Gmail iraniens **avec un certificat valide**. Retirée de
  tous les magasins, faillite en quelques semaines.

Deux garde-fous nés de là :

**Certificate Transparency** — toute émission est publiée dans des journaux publics et
inaltérables (Chrome l'exige). Ça ne **prévient** pas la fraude, ça la rend **détectable**.
Recherche publique : `crt.sh`.

**Les enregistrements `CAA`** — un enregistrement **DNS** qui restreint les autorités autorisées :

```
boutique.fr.   CAA   0 issue "letsencrypt.org"
```

Observé : `google.com` → `0 issue "pki.goog"`. De 121 autorités autorisées à **une**. Une ligne
de DNS, gratuite, l'un des durcissements les plus rentables qui existent.
Étiquettes : `issue`, `issuewild` (génériques), `iodef` (où signaler).

---

## Les quatre causes de panne TLS

| | Cause | Ce qu'`openssl` affiche | Correction |
|---|---|---|---|
| **1** | **Certificat expiré** | `NotAfter` dépassé | renouveler — et **surveiller** |
| **2** | **Chaîne incomplète** | `verify error:num=20: unable to get local issuer certificate` | servir `fullchain.pem` |
| **3** | **Nom non concordant** | nom absent du `subjectAltName` | corriger le certificat ou le SNI |
| **4** | **Horloge décalée** | `NotBefore` **dans le futur** | régler l'heure du **client** |

```bash
echo | openssl s_client -connect example.com:443 -servername example.com 2>/dev/null \
  | openssl x509 -noout -subject -dates -ext subjectAltName
```

- ⚠ **`-servername` envoie le SNI.** Sans lui, `openssl` reçoit le certificat **par défaut**
  du serveur → faux diagnostic de non-concordance de nom. L'erreur la plus fréquente.
- ⚠ **`</dev/null`** sinon `openssl` attend ton entrée et ne rend jamais la main
  (même famille que `nc` sans `-w`)

### ⚠ La cause 2 est la vicieuse

```
dans le NAVIGATEUR            →  ça marche
avec curl, Java, Python, Go   →  ça échoue
```

Les navigateurs **mettent en cache les intermédiaires** rencontrés ailleurs et savent aller
les chercher ; les autres clients ne font **ni l'un ni l'autre**.

```
cert.pem        ← la feuille SEULE          ❌ ne jamais servir celui-là
fullchain.pem   ← feuille + intermédiaires  ✅
```

Le nom des fichiers ne prévient pas, les deux existent côte à côte, et le navigateur masque
l'erreur. Le symptôme est « ça marche chez moi », pour une raison totalement différente du
`/etc/hosts`.

### ⚠ La cause 3 et les génériques

> **Le `*` remplace exactement UNE étiquette. Ni zéro, ni deux.**

```
*.boutique.fr   =   <UNE étiquette> . boutique.fr

www.boutique.fr    une étiquette    ✅
boutique.fr        ZÉRO étiquette   ❌  ← l'apex
a.b.boutique.fr    DEUX étiquettes  ❌
```

D'où **deux entrées** nécessaires : `DNS:boutique.fr, DNS:*.boutique.fr`.

**L'apex** = le nom de la zone elle-même, celui qui porte le `SOA` (relatif à la **zone**, pas
à l'extension). Il est spécial deux fois : il interdit le `CNAME` (hier) et échappe au
générique (aujourd'hui). → **réflexe de vérification systématique sur l'apex**.

---

## ACME et la surveillance

| | `HTTP-01` | `DNS-01` |
|---|---|---|
| **Comment** | servir un fichier sur `/.well-known/acme-challenge/<jeton>` | publier un `TXT` sur `_acme-challenge.domaine` |
| **Nécessite** | **port 80 ouvert** et joignable | accès **API à la zone DNS** |
| **Générique `*`** | **impossible** | **seule méthode** |
| **Service non exposé** | impossible | **possible** |

- un générique **impose** `DNS-01` → donc un jeton d'API DNS → **un secret à gérer** : l'une
  des premières vraies raisons d'avoir un gestionnaire de secrets
- `DNS-01` permet de certifier un service **interne**, sans port 80 public
- ⚠ **le cache négatif guette** : si l'autorité interroge le `TXT` trop tôt et obtient
  `NXDOMAIN`, l'absence est mise en cache pour la durée du `minimum` du `SOA`.
  → *ne jamais interroger un nom avant de l'avoir créé*

### ⚠ Ce qui tombe en panne malgré l'automatisation

**1. Un renouvellement qui échoue, échoue EN SILENCE.** Le minuteur tourne, `certbot` rate,
personne n'est prévenu, et 90 jours plus tard le site tombe. Aucun symptôme entre les deux.

- **cron ne rattrape JAMAIS** une exécution manquée → machine éteinte à l'heure prévue =
  renouvellement jamais fait. Un **minuteur systemd avec `Persistent=true`** rattrape.

**2. Le renouvellement peut réussir et le serveur servir quand même l'ancien certificat.**

```
certbot renouvelle        →  nouveau fichier écrit sur disque        ✅
rien ne recharge nginx    →  il sert l'ANCIEN, chargé en mémoire     ❌
```

Un serveur web garde son certificat **en mémoire**. D'où `--deploy-hook` : recharger
**uniquement si** un renouvellement a eu lieu — exactement la règle d'idempotence
(`cmp -s`, puis redémarrer seulement si quelque chose a changé).

Sans le crochet : fichier valide, journaux verts, `--dry-run` qui passe — **et certificat
expiré en production**. Tous les indicateurs mentent.

### La règle qui règle les deux

> ⚠ **On ne surveille pas le mécanisme de renouvellement. On surveille la date d'expiration
> du certificat réellement SERVI en production, interrogée sur le port.**

Surveiller le minuteur, c'est surveiller son **hypothèse** sur le fonctionnement. Sonder le
port, c'est mesurer ce que l'utilisateur **reçoit**.

```bash
echo | openssl s_client -connect boutique.fr:443 -servername boutique.fr 2>/dev/null \
  | openssl x509 -noout -enddate
```

Alerter sous 20 jours. Pas les fichiers, pas les journaux, pas le minuteur : **le port**.

- les **chiffres de quotas** de Let's Encrypt changent régulièrement → les lire sur la
  documentation au moment où on en a besoin, jamais les mémoriser

---

## Commandes

```bash
curl -v https://site -o /dev/null            # la trace complète ; lire les lignes * d'abord
curl -s -o /dev/null -w '%{http_code}\n' URL # juste le code de statut
curl -H 'Host: autre.fr' http://<IP>/        # tester l'hébergement mutualisé
curl -I URL                                  # HEAD : les en-têtes seuls
printf 'GET / HTTP/1.1\r\nHost: X\r\n\r\n' | nc -w 3 X 80    # HTTP brut, sans client HTTP

openssl s_client -connect site:443 -servername site </dev/null 2>&1 | head -n 25
echo | openssl s_client -connect site:443 -servername site 2>/dev/null \
  | openssl x509 -noout -subject -dates -ext subjectAltName
openssl s_client -connect site:443 -servername site -showcerts   # la chaîne complète
openssl s_client -connect site:443 -tls1_2                       # forcer une version

dig CAA domaine +short                       # quelles autorités sont autorisées
grep -c "BEGIN CERTIFICATE" /etc/ssl/certs/ca-certificates.crt   # taille du magasin
```
