# CIDR — l'essentiel

> Lire un bloc de tête, sans binaire et sans outil.
> Les ⚠ marquent les pièges rencontrés le 16/10 — à relire en priorité.

---

## Fondations

- une adresse IPv4 = **4 octets** = **4 × 8 = 32 bits** → d'où le `/32` maximum
  - *octet* signifie littéralement « groupe de huit bits »
- un octet compte de **0 à 255** (2⁸ = 256 valeurs) — ⚠ `192.168.1.265` n'existe pas
  - la preuve : si un octet faisait 4 bits, il irait de 0 à 15, et `192` serait impossible
- le préfixe `/n` = **nombre de bits fixés**, jamais une valeur à soustraire
  - ⚠ `/8` ne donne pas un masque de 245 : 8 uns puis 24 zéros → `255.0.0.0`
- total d'adresses = **2^(32 − préfixe)** · utilisables = **total − 2**
- intuition inversée : **plus le nombre après le slash est grand, plus le bloc est petit**
- CIDR = *Classless* Inter-Domain Routing — les « classes A/B/C » sont abandonnées depuis 1993

```
/8    1 octet  fixé,  3 octets libres    16 777 216 adresses
/16   2 octets fixés, 2 octets libres        65 536
/24   3 octets fixés, 1 octet  libre            256
/32   4 octets fixés, 0 bit    libre              1
```

---

## La table

| Bits dans l'octet | Masque | **Largeur du bloc** |
|---|---|---|
| 1 | 128 | 128 |
| 2 | 192 | 64 |
| 3 | 224 | 32 |
| 4 | 240 | 16 |
| 5 | 248 | 8 |
| 6 | 252 | 4 |
| 7 | 254 | 2 |
| 8 | 255 | 1 |

- colonne **largeur** : les puissances de 2 en descendant
- colonne **masque** : chaque ligne = la précédente + la largeur correspondante
- **largeur = 256 − masque** et **largeur = 2^(bits libres)** — deux écritures du même nombre
  - démonstration : masque = somme des poids fixés = 255 − (largeur − 1) = 256 − largeur
- la table n'est qu'un gain de temps : elle se reconstruit en additionnant les poids
  - ex. `/20` → 4 bits fixés → 128+64+32+16 = **240** → largeur 256−240 = **16**

---

## La méthode du nombre magique

### Les quatre étapes

1. **octet intéressant** : /1→8 = 1er · /9→16 = 2e · /17→24 = 3e · /25→32 = 4e
2. **masque de cet octet** (table ci-dessus) — les octets avant sont à 255, ceux après à 0
3. **largeur** = 256 − masque
4. ⚠ **arrondir l'octet de l'adresse vers le bas** au multiple de la largeur

```
réseau    : octet arrondi bas, puis tous les octets suivants à 0
diffusion : réseau + largeur − 1, puis tous les octets suivants à 255
```

- ⚠ les étapes 1 à 3 ne dépendent que du **préfixe** et se mémorisent
- ⚠ l'étape 4 dépend de **l'adresse** et se **recalcule à chaque fois**
  - l'erreur la plus fréquente : recycler le résultat d'un exercice au même préfixe

### Pourquoi ça marche

Le préfixe coupe l'octet en deux. Les bits de gauche sont verrouillés, ceux de droite comptent.

- les bits de droite parcourent `2^k` valeurs consécutives → **c'est la largeur**
- les bits de gauche ont tous un poids **multiple de `2^k`** → toute somme de bits fixés est
  un multiple de `2^k` → **les blocs démarrent forcément aux multiples de la largeur**

C'est le même mécanisme qu'un arrondi décimal : « dans quelle centaine tombe 437 ? » →
`437 ÷ 100 = 4,37` → `4 × 100 = 400`. Seule la base change (2 au lieu de 10).

- ⚠ les frontières s'obtiennent en **ajoutant** la largeur : 0, 16, 32, 48, 64…
  - jamais en doublant (`0, 16, 32, 64` est faux — c'est la suite des puissances de 2)
- ⚠ **ne pas sauter de frontière** : avec une largeur de 16, après 192 vient 208, pas 224
- la partie fixée dit **où** commence la fenêtre · la partie libre dit **quelle largeur** elle a
  - en `/20`, le 3e octet ne parcourt que `112 → 127`, pas `0 → 255`

### Exemple déroulé — `172.24.118.200/20`

```
1. /20 ∈ [17,24]               → 3e octet
2. 20 − 16 = 4 bits fixés      → masque 240   → 255.255.240.0
3. largeur                     → 256 − 240 = 16
4. 118 ÷ 16 = 7,375 → 7 × 16   → 112

réseau              172.24.112.0
première utilisable 172.24.112.1
dernière utilisable 172.24.127.254
diffusion           172.24.127.255     (112 + 16 − 1 = 127, puis 255)
total / utilisables 4 096 / 4 094
```

---

## Les deux vérifications

### L'adresse doit tomber dans son propre bloc

> Si l'adresse de départ n'est pas entre le réseau et la diffusion, le résultat est faux.

Attrape le **mauvais bloc** (étape 4 ratée). Une seconde de relecture, aucun calcul.

```
172.31.4.45/28  →  réponse « .192 → .207 »  →  45 n'est pas dedans  →  impossible
192.168.1.6/30  →  réponse « .0 → .4 »      →   6 n'est pas dedans  →  impossible
```

### Les blocs doivent recouvrir exactement 256

> Le dernier bloc de l'octet doit finir à 255.

Attrape la **mauvaise largeur** (étape 3 ratée) — que le test précédent ne voit pas.

```
4 blocs × 64 = 256 ✓      16 blocs × 16 = 256 ✓
10.1.1.200/26  →  réseau .192 → diffusion .255, car 192 + 64 = 256
                  ⚠ « .207 » appliquerait la largeur du /28, pas du /26
```

---

## Adresses réservées

### Les 2 adresses standard

- **réseau** (bits libres à 0) = l'identifiant du bloc, celui des tables de routage
- **diffusion** (bits libres à 1) = « toutes les machines à la fois » (ex. `DHCPDISCOVER`)
- ⚠ le `− 2` est une **conséquence** du protocole, pas une convention à mémoriser

| Préfixe | Total | Utilisables | |
|---|---|---|---|
| /30 | 4 | **2** | liaison point à point entre deux routeurs |
| /31 | 2 | 0 | inutilisable (sauf RFC 3021, point à point) |
| /32 | 1 | 0 | désigne **une** machine : règle de pare-feu, route |

### GCP en confisque 4

| Position | Dans `10.1.2.0/24` | Usage |
|---|---|---|
| première | `10.1.2.0` | adresse de réseau |
| **deuxième** | **`10.1.2.1`** | **passerelle par défaut de Google** |
| **avant-dernière** | **`10.1.2.254`** | **réservée par Google, usage futur** |
| dernière | `10.1.2.255` | adresse de diffusion |

- aucune VM ne porte jamais `.1` : c'est le routeur virtuel de Google
- le plus petit sous-réseau GCP est un **`/29`** → 8 adresses → **4 utilisables** (la moitié)

| Préfixe | Total | Hors cloud | **Sur GCP** |
|---|---|---|---|
| /29 | 8 | 6 | **4** |
| /28 | 16 | 14 | **12** |
| /24 | 256 | 254 | **252** |
| /20 | 4 096 | 4 094 | **4 092** |

### Dimensionner un sous-réseau GCP

```
1. besoin en machines
2. + 4                              (confisquées par GCP)
3. arrondir à la puissance de 2 supérieure
4. le préfixe correspondant
```

- une taille de bloc est **toujours** une puissance de 2 : 1, 2, 4, 8, 16, 32, 64…
  - il n'existe pas de bloc de 10 ni de 12 → **on gaspille toujours des adresses**
- ex. besoin 10 machines → 14 → 16 → **`/28`**, 2 adresses de marge
- ⚠ besoin 12 → 16 → `/28` → **exactement 12 utilisables, zéro marge** → prendre `/27`

---

## Blocs réservés

| Bloc | Nom | Usage |
|---|---|---|
| `10.0.0.0/8` | privé RFC 1918 | 16,7 M — le défaut sur GCP |
| `172.16.0.0/12` | privé RFC 1918 | 1 M — se termine à `172.31.255.255` |
| `192.168.0.0/16` | privé RFC 1918 | 65 k — box domestiques |
| `127.0.0.0/8` | boucle locale | **tout** le /8, pas seulement `127.0.0.1` |
| `169.254.0.0/16` | lien-local | **DHCP a échoué** — diagnostic, jamais une config |
| `0.0.0.0/0` | route par défaut | « toutes les destinations » (`ip route`) |
| `224.0.0.0/4` | multidiffusion | un groupe d'abonnés, pas un réseau |

- les plages RFC 1918 **ne sont pas routables sur Internet** → d'où le NAT pour sortir
  - c'est ce qui permet à des millions de réseaux d'utiliser les mêmes adresses sans collision
- `169.254.x.x` sur une machine = le serveur DHCP n'a pas répondu
- `127.0.0.2` fonctionne aussi : utile pour plusieurs services sur le même port en local

---

## Vérifier avec l'outil

**Toujours calculer à la main d'abord**, l'outil ensuite — sinon le réflexe ne se construit pas.

```bash
ipcalc 172.24.112.0/20       # Address/Netmask en binaire, Network, Broadcast, HostMin/Max, Hosts/Net
ipcalc -b 10.0.5.200/28      # sans l'affichage binaire
ip -brief address            # les adresses locales, avec leur préfixe
ip route                     # les blocs joignables, 0.0.0.0/0 = défaut
```

- dans `ipcalc`, l'**espace** dans l'affichage binaire marque la frontière du préfixe
- le **wildcard** est le complément du masque (`0.0.15.255` pour `/20`) et donne la largeur
- `Hosts/Net` = total − 2 — ne tient **pas** compte des 4 de GCP
