# Réseau — modèle en couches, TCP/UDP, diagnostic

> Semaine 2, jour 1. Tout ce qui suit a été observé sur la machine, pas récité.

---

## 1. Le modèle en couches

### Le schéma

```
┌───────────────────────────────────────────────────────────────┐
│ 7  APPLICATION    HTTP · DNS · SSH · TLS                      │
│                   « que veut dire ce message »                │
├───────────────────────────────────────────────────────────────┤
│ 4  TRANSPORT      TCP · UDP                                   │
│                   « quel processus, et avec quelles garanties »│
│                   → ports, numéros de séquence, accusés       │
├───────────────────────────────────────────────────────────────┤
│ 3  RÉSEAU         IPv4 · IPv6 · ICMP                          │
│                   « quelle machine, et par où »               │
│                   → adresses, routage, TTL                    │
├───────────────────────────────────────────────────────────────┤
│ 2  LIAISON        Ethernet · Wi-Fi                            │
│                   « quelle carte sur ce lien »                │
│                   → adresses MAC, trames, MTU                 │
├───────────────────────────────────────────────────────────────┤
│ 1  PHYSIQUE       cuivre · fibre · radio                      │
│                   (inexistant sur loopback : copie mémoire)   │
└───────────────────────────────────────────────────────────────┘
```

Le modèle OSI en compte sept ; les couches 5 et 6 (session, présentation) n'ont pas d'équivalent pratique dans TCP/IP et ne servent qu'en théorie. On travaille sur quatre couches réelles.

### L'encapsulation

Chaque couche enveloppe la précédente et ajoute son en-tête. Chaque couche ne lit que le sien.

```
[ Ethernet [ IP [ TCP [ HTTP: GET /health ] ] ] ]
  └ 14 o    └ 20/40 o  └ 20 o   └ les données
```

Sur le chemin, un commutateur ne regarde que l'enveloppe Ethernet, un routeur que l'enveloppe IP, et seul le destinataire ouvre jusqu'au HTTP.

---

## 2. Capturer avec tcpdump

```bash
sudo tcpdump -i lo -n -c 20 port 3000        # loopback, 20 paquets, port 3000
sudo tcpdump -i any -n -c 10 port 53         # toutes interfaces, DNS
sudo tcpdump -i eth0 -n -S host 1.2.3.4      # numéros de séquence absolus
sudo tcpdump -i any -n -w capture.pcap port 443   # écrire pour analyse ultérieure
```

| Option | Rôle |
|---|---|
| `-i` | interface · `any` pour toutes · `lo` pour localhost |
| `-n` | pas de résolution de noms — **systématique** en diagnostic |
| `-c N` | s'arrêter après N paquets, sinon ça tourne indéfiniment |
| `-S` | numéros de séquence **absolus** (par défaut relatifs après les 2 premiers) |
| `-w f.pcap` | écrire dans un fichier, lisible par Wireshark |
| `-v` / `-vv` | décodage plus détaillé |

### Lire la notation des flags

| Flag | Signification |
|---|---|
| `[S]` | SYN — ouverture |
| `[S.]` | SYN + ACK |
| `[.]` | ACK seul |
| `[P.]` | PUSH + ACK — **porte des données** |
| `[F.]` | FIN + ACK — fermeture |
| `[R]` | RESET — rupture brutale |

Le **point** vaut ACK. `[P.]` se lit « PUSH et ACK ».

---

## 3. Anatomie d'une requête HTTP — 10 paquets

```
 #  sens      flags  données   rôle
 1  C → S     [S]       0      SYN
 2  S → C     [S.]      0      SYN-ACK
 3  C → S     [.]       0      ACK          → connexion établie
 4  C → S     [P.]     83      la requête HTTP
 5  S → C     [.]       0      accusé
 6  S → C     [P.]    218      la réponse HTTP
 7  C → S     [.]       0      accusé
 8  C → S     [F.]      0      FIN du client
 9  S → C     [F.]      0      FIN du serveur
10  C → S     [.]       0      ACK final
```

**2 paquets sur 10 portent des données.** 301 octets utiles pour 10 paquets de mécanique. C'est le prix de la fiabilité — et la raison d'être du `keep-alive` et de HTTP/2, qui évitent de repayer ce coût à chaque requête.

---

## 4. Le handshake

```
CLIENT                                      SERVEUR
   │──── SYN  seq=X ──────────────────────────▶│
   │◀─── SYN-ACK  seq=Y, ack=X+1 ──────────────│
   │──── ACK  ack=Y+1 ────────────────────────▶│
   │        ═══ connexion établie ═══          │
   │──── données  seq=X+1 ────────────────────▶│
```

### Les règles

- **`ack` = le prochain numéro attendu**, pas une demande. `ack=X+1` signifie « j'ai tout reçu jusqu'à X ».
- L'accusé est **cumulatif** : un seul `ack` confirme tout ce qui précède.
- **SYN et FIN consomment chacun un numéro de séquence** bien qu'ils ne portent aucune donnée. C'est ce qui permet de les accuser.
- Les numéros initiaux sont **tirés au hasard** (32 bits) : sinon un attaquant qui ne voit pas le trafic pourrait injecter des paquets dans une connexion en cours. C'est l'attaque par prédiction de séquence (Mitnick, 1994).
- `seq 100:184` est un intervalle **ouvert à droite** : octets 100 à 183, soit 84 octets.

### Vérification sur une capture réelle

```
X = 25494504, Y = 1064428358

paquet 2  ack 25494505      = X+1   ✓ le SYN a consommé un numéro
paquet 4  seq 25494505:…    = X+1   ✓ les données reprennent là
paquet 9  ack 25494589      = +1    ✓ le FIN aussi consomme un numéro
```

---

## 5. TCP contre UDP

| | TCP | UDP |
|---|---|---|
| Établissement | 3 paquets | aucun |
| Livraison | garantie, retransmission | aucune garantie |
| Ordre | garanti | aucun |
| Contrôle de flux et congestion | oui | non |
| Coût d'une requête/réponse | ~10 paquets | **2 paquets** |
| Usages | HTTP, SSH, bases de données | DNS, NTP, QUIC, voix, vidéo, jeux, métriques |

### Ce qu'UDP impose à l'application

Sans connexion, rien n'associe une réponse à sa question. DNS le règle avec un **identifiant de transaction** recopié dans la réponse :

```
10.255.255.254.48570 > 10.255.255.254.53: 4064+ [1au] A? github.com. (51)
10.255.255.254.53 > 10.255.255.254.48570: 4064 1/0/1 A 140.82.121.3 (55)
                                          └─┬─┘
                                      le même identifiant
```

**Règle générale : qui choisit UDP renonce aux garanties de TCP et réimplémente celles dont il a besoin.**

L'identifiant ne fait que 16 bits — d'où l'empoisonnement de cache DNS (Kaminsky, 2008), et la randomisation du port source ajoutée en réponse.

**Le DNS utilise aussi TCP** quand la réponse est trop grande : le serveur renvoie une réponse tronquée (drapeau `TC`) et le client refait sa requête en TCP.

---

## 6. ss — sockets et états

```bash
ss -tlnp                              # qui ÉCOUTE — la 1re commande sur une machine inconnue
ss -tanp                              # tout, tous états
ss -tn state established              # seulement les connexions actives
ss -tan '( sport = :3000 or dport = :3000 )'   # filtrer sur un port
ss -s                                 # résumé chiffré par état
```

| Option | Rôle |
|---|---|
| `-t` / `-u` | TCP / UDP |
| `-l` | en écoute seulement |
| `-a` | tous les états |
| `-n` | numérique — sinon `53` s'affiche `domain` |
| `-p` | processus propriétaire (nécessite `sudo` pour ceux des autres utilisateurs) |

L'ordre des options n'a aucune importance : `-tlnp` = `-tnlp` = `-pltn`.

### Les colonnes changent de sens selon l'état

| | Sur une connexion établie | **Sur un socket en écoute** |
|---|---|---|
| `Recv-Q` | octets reçus non lus par l'application | **connexions en attente d'`accept()`** |
| `Send-Q` | octets envoyés non acquittés | **taille max de la file** (*backlog*) |

Un `Recv-Q` non nul sur une ligne `LISTEN` = des connexions s'accumulent, l'application n'accepte pas assez vite. **Signal d'alerte.**

Backlog par défaut : 511 pour Node, 4096 pour beaucoup de démons système. File pleine = connexions refusées ou ignorées en silence, alors que le service paraît vivant.

### Diagnostic par les files d'attente

| Observation | Interprétation |
|---|---|
| `Recv-Q` et `Send-Q` à 0, réponse lente | l'**application** est lente, pas le réseau |
| `Recv-Q` élevé côté serveur | l'application ne lit pas assez vite |
| `Send-Q` élevé | congestion réseau, ou client lent à acquitter |

### TIME_WAIT

Après fermeture, **le côté qui ferme en premier** reste 60 secondes en `TIME_WAIT`.

Deux raisons : garantir que le dernier ACK est arrivé (sinon le pair retransmet son FIN et il faut pouvoir répondre), et empêcher qu'un vieux segment retardé contamine une nouvelle connexion sur le même quadruplet.

**Conséquence en production.** Un quadruplet identifie une connexion ; vers une destination unique, le nombre de connexions simultanées est borné par la plage de ports éphémères :

```bash
cat /proc/sys/net/ipv4/ip_local_port_range     # 32768 60999 → 28 231 ports
```

Un proxy en connexions courtes à 500 req/s accumule 30 000 `TIME_WAIT` et bute sur le plafond : `cannot assign requested address`, alors que ni CPU ni mémoire ne sont saturés.

| Parade | Principe |
|---|---|
| **Connexions persistantes** (keep-alive, HTTP/2) | ne pas fermer — la vraie solution |
| `net.ipv4.tcp_tw_reuse=1` | réutiliser un port en `TIME_WAIT` pour une connexion sortante |
| `SO_REUSEADDR` côté serveur | redémarrer sans attendre |

**Pièges :**
- `tcp_tw_recycle` : **supprimée du noyau en 4.12**, cassait les clients derrière un NAT. Si un article la recommande, il est obsolète.
- `net.ipv4.tcp_fin_timeout` ne règle **pas** `TIME_WAIT` mais `FIN_WAIT_2`. La durée de `TIME_WAIT` est codée en dur.

**Conséquence de conception :** un serveur a intérêt à laisser le client fermer. S'il ferme en premier, il accumule les `TIME_WAIT` sur son unique port 443.

---

## 7. Configuration et routage

```bash
ip -brief address      # les interfaces et leurs adresses, format compact
ip route               # la table de routage
ip link show eth0      # l'adresse MAC, le MTU, l'état
ip neigh               # le cache ARP / découverte de voisins
```

### Lire une table de routage

```
default via 172.24.112.1 dev eth0
172.17.0.0/16 dev docker0  linkdown
172.24.112.0/20 dev eth0   src 172.24.121.122
```

Le noyau applique la règle du **préfixe le plus long** : parmi les routes qui correspondent, il garde celle dont le masque est le plus précis. `default` a un masque `/0` — elle ne gagne que si rien d'autre ne correspond.

| Destination | Route retenue |
|---|---|
| même réseau | la route du réseau → **livraison directe**, sans routeur |
| réseau connu | la route spécifique |
| tout le reste | `default` → la passerelle |

### Plages privées — RFC 1918

```
10.0.0.0/8        192.168.0.0/16        172.16.0.0/12
```

Non routables sur Internet. Un NAT est nécessaire pour en sortir.

### IPv6 link-local

Toute interface IPv6 s'auto-attribue une adresse `fe80::/10` dérivée de sa MAC :

```
MAC    00:15:5d:0b:ec:de
       → insérer ff:fe au milieu : 00:15:5d:ff:fe:0b:ec:de
       → inverser le 7e bit du 1er octet : 02:15:5d:ff:fe:0b:ec:de
       → fe80::215:5dff:fe0b:ecde
```

Valable uniquement sur le lien local, jamais routée. Base de la découverte de voisins, l'équivalent IPv6 de l'ARP.

### localhost est IPv6 en premier

```bash
getent hosts localhost        # → ::1
```

`/etc/hosts` place `::1 localhost` avant `127.0.0.1 localhost`. Un service qui n'écoute que sur `0.0.0.0` refusera une connexion à `localhost` alors que `127.0.0.1` fonctionnera. Écouter sur `*` ou `[::]` couvre les deux familles.

---

## 8. MTU et fragmentation

Le **MTU** est la taille maximale d'une trame transmissible d'un coup. 1500 sur Ethernet classique, moins dès qu'il y a encapsulation : VPN, tunnel, réseau virtuel, réseau de conteneurs.

```bash
ip link show eth0 | grep mtu
ping -c 1 -M do -s 1392 DEST     # 1392 + 28 = 1420 → passe
ping -c 1 -M do -s 1393 DEST     # 1421 → refusé
```

`-M do` positionne le bit **Don't Fragment**. Surcharge : 20 octets d'en-tête IP + 8 d'en-tête ICMP = 28.

| Cas | Comportement |
|---|---|
| `DF` à 0 | le routeur fragmente, le destinataire réassemble |
| `DF` à 1 | le routeur jette et renvoie un ICMP « fragmentation nécessaire » |

Le second est la norme : c'est la **découverte du MTU de chemin**.

### Le trou noir de MTU

Quand un pare-feu bloque l'ICMP, le message d'erreur n'arrive jamais. L'émetteur retransmet indéfiniment des paquets trop gros.

**Symptôme caractéristique : les petites requêtes passent, les grosses gèlent sans message.** Un `curl` sur une page légère fonctionne, un téléversement bloque. Un des diagnostics les plus déroutants, fréquent avec les VPN et les réseaux Kubernetes.

Noter la différence :
- `ping: local error: message too long` = **ton propre noyau** refuse, le paquet n'est jamais parti
- silence = un routeur **distant** jette, et l'ICMP de retour est filtré

---

## 9. Tester la joignabilité

### ping muet ≠ machine injoignable

C'est la conclusion hâtive numéro un. La plupart des hôtes durcis, la quasi-totalité des équilibreurs de charge cloud et le pare-feu de Windows ignorent l'ICMP *echo*. Sur GCP, une instance ne répond au ping que si une règle de pare-feu l'autorise explicitement.

**Tester le port qui t'intéresse, pas l'ICMP :**

```bash
nc -zv -w 3 HOTE PORT
curl -sS -o /dev/null -w "%{http_code}\n" https://site
```

### REJECT contre DROP

| Réponse | Ce que tu vois | Diagnostic |
|---|---|---|
| `RST` immédiat | `Connection refused`, instantané | la machine est là, **rien n'écoute** |
| rien | blocage jusqu'au délai d'attente | **pare-feu en `DROP`** |

`DROP` est utilisé pour ralentir les scanners : un balayage de ports devient mille fois plus long.

**Toute commande réseau dans un script doit avoir un délai d'attente** — `nc -w 3`, `curl --max-time 3`. Sans ça, un `DROP` distant bloque le pipeline indéfiniment.

---

## 10. Traceroute et mtr

### Le mécanisme du TTL

Chaque paquet IP porte un compteur décrémenté par chaque routeur. À zéro, le routeur **jette le paquet et renvoie un ICMP « durée de vie expirée »**, signé de son adresse.

```
TTL=1 → le 1er routeur se dénonce
TTL=2 → le 2e
TTL=3 → ...
```

Le TTL existe pour éviter les boucles de routage ; traceroute détourne ce garde-fou pour cartographier le chemin.

```bash
traceroute -n -q 1 -w 1 -m 20 HOTE
mtr -n -c 20 --report HOTE          # 20 sondes par saut, avec taux de perte
```

### Les règles de lecture — les plus importantes de cette fiche

**Un `*` ne signifie pas que le chemin est cassé.** Le routeur ne répond simplement pas aux paquets expirés. Un traceroute constellé d'étoiles qui atteint sa destination est normal.

**La perte intermédiaire n'a de sens que si elle se poursuit jusqu'à la destination.**

```
 9. 62.115.124.117    10.0% de perte
11. ???              100.0% de perte
12. ???              100.0% de perte
13. 140.82.121.3       0.0% de perte   ← la destination répond à tout
```

Deux sauts à 100 % et la destination à 0 % : les paquets passent, les routeurs refusent juste de se signaler.

**La latence intermédiaire ne mesure pas le temps de transit.**

```
saut 7  → 32,0 ms
saut 13 → 13,5 ms     ← la destination, plus rapide que deux sauts en amont
```

**Pourquoi :** un routeur a deux chemins internes.

| | Chemin rapide (*data plane*) | Chemin lent (*control plane*) |
|---|---|---|
| Exécuté par | des circuits dédiés (ASIC) | le **processeur** du routeur |
| Débit | millions de paquets/s | milliers |
| Rôle | **faire transiter** | répondre aux ICMP, routage, administration |

Faire transiter un paquet reste dans le matériel. **Fabriquer** un message d'erreur ICMP exige de remonter au processeur, qui traite ça en basse priorité entre deux tâches.

Donc la mesure d'un saut intermédiaire = « combien de temps le processeur de ce routeur a mis à me répondre », pas « combien de temps le trafic met à le traverser ». La destination, elle, répond avec sa pile réseau normale : **c'est la seule mesure honnête.**

Trois causes secondaires : la limitation de débit ICMP des routeurs, le routage **asymétrique** (aller et retour par des chemins différents), et le fait que chaque saut est une sonde indépendante.

### Une valeur impossible est un artefact

```
7. 62.115.118.58   Avg -71.4   Best -2029   StDev 461.0
```

Une latence négative est physiquement impossible. **Quand un outil affiche une valeur impossible, c'est l'instrument qui est en cause, pas le système.** Le `StDev` dix fois supérieur à la moyenne le confirme. On jette la mesure, on ne cherche pas d'explication réseau.

(Même leçon que les inodes négatifs de `df` sur les montages Windows.)

---

## En résumé — les sept réflexes

1. `ss -tlnp` : la première commande sur une machine inconnue
2. `-n` systématique sur tous les outils réseau
3. `Recv-Q` non nul sur `LISTEN` = file d'acceptation qui déborde
4. Les deux `Q` à zéro avec une réponse lente = l'application, pas le réseau
5. Ping muet ≠ injoignable → tester le port avec `nc -zv -w 3`
6. Blocage sans réponse = `DROP` · refus immédiat = rien n'écoute
7. Perte intermédiaire dans un traceroute : significative **seulement** si elle se poursuit jusqu'au bout
