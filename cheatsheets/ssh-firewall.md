# SSH et pare-feu — l'essentiel

> Authentification par clés, tunnels, filtrage à état, modèle GCP.
> Les ⚠ marquent les pièges rencontrés le 21/10 — à relire en priorité.
> Tous les exemples viennent de dispositifs travaillés en séance.

---

## ⚠⚠ Le principe tombé TROIS fois — à relire avant tout le reste

> **On ne vérifie pas le MÉCANISME. On vérifie le RÉSULTAT.**

Vérifier le mécanisme, c'est vérifier **son hypothèse** sur le fonctionnement. Tous les
indicateurs peuvent être verts alors que la production est cassée.

| Vérifier le mécanisme — **insuffisant** | Vérifier le résultat — **ce qu'il faut faire** |
|---|---|
| le minuteur tourne, `certbot` renvoie 0, `--dry-run` passe | **le port sert un certificat valide** |
| les permissions de `~/.ssh` sont correctes | **une connexion par clé aboutit** |
| la règle de pare-feu existe et est active | **le port répond depuis l'extérieur** |
| le conteneur est `Up` | **le point de santé répond 200** |

Trois occurrences en trois jours, sur trois sujets sans rapport : surveillance d'un certificat
(20/10), durcissement SSH (21/10), et le principe lui-même. **Ce n'est pas un détail de TLS ni
de SSH — c'est une règle d'exploitation.**

Le test à s'appliquer : *« si ce que je vérifie était vert ET que la production était cassée,
est-ce possible ? »* Si oui, je vérifie le mécanisme.

---

## ⚠ Les paires à ne pas inverser

| | D'un côté | De l'autre |
|---|---|---|
| **Signature** | **signer** avec la clé **PRIVÉE** | **vérifier** avec la clé **PUBLIQUE** |
| **Chiffrement** | **chiffrer** avec la clé **PUBLIQUE** du destinataire | **déchiffrer** avec **SA** clé **PRIVÉE** |
| **Secret** | mot de passe = secret **réutilisable** → le transmettre, c'est le donner | clé = **signature** liée à un défi unique |
| **Messages SSH** | `authenticity can't be established` = **1re** connexion, normal | `IDENTIFICATION HAS CHANGED` = clé **changée**, ⚠ toujours anormal |
| **Tunnels** | `-L` = port ouvert **chez moi** (local) | `-R` = port ouvert **là-bas** (remote) |
| **Écoute** | `0.0.0.0:443` = joignable du réseau | `127.0.0.1:5432` = ⚠ inatteignable **par construction** |
| **Verdicts** | `REJECT` = réponse explicite (≈ `REFUSED` DNS) | `DROP` = silence (≈ *timeout* DNS) |
| **Ce qui décide** | Linux : **l'ORDRE** des règles | GCP : la **PRIORITÉ** numérique |
| **Pare-feu** | local, **sur** la machine, tombe avec elle | VPC, **avant** la machine, **survit** à sa compromission |
| **Validité** | une règle **VALIDE** est bien formée | une règle **APPLICABLE** cible une instance existante |

### La règle unique qui retrouve les quatre premières cases

> **La clé privée est toujours du côté de ce que SEUL son détenteur peut faire.**

Signer — seul moi produis ma signature. Déchiffrer — seul moi lis ce qu'on m'a chiffré.
Les deux autres opérations sont celles que **tout le monde** doit pouvoir faire : vérifier une
signature, chiffrer un message à mon intention.

Démonstration par l'absurde, à refaire si le doute revient : *si Cloudflare signait avec sa clé
publique, que tout le monde possède, n'importe qui produirait la même signature — elle ne
prouverait rien.* Et : *ton navigateur n'a aucun secret partagé avec Cloudflare, il ne peut
donc disposer que de leur clé publique.*

C'est aussi pourquoi un certificat est **public** : il contient une signature à vérifier, pas
un secret à protéger.

### La construction combinée

```
SIGNER    avec MA clé privée          →  prouve de QUI ça vient
CHIFFRER  avec la clé publique de A   →  seul A pourra LIRE
```

Deux opérations indépendantes, deux questions différentes.

---

## SSH — l'authentification dans les deux sens

```
SERVEUR → CLIENT    clé d'HÔTE        « je suis bien la machine attendue »
CLIENT → SERVEUR    clé UTILISATEUR   « je suis bien l'utilisateur autorisé »
```

Le sens le plus important est **inversé par rapport à TLS** : ici c'est le **client** qui doit
se prouver, parce que ce qu'il obtient est un **shell** — l'exécution de code arbitraire.

```
SUR TA MACHINE     ~/.ssh/id_ed25519        clé PRIVÉE    → SIGNE le défi · ne bouge JAMAIS
SUR LE SERVEUR     ~/.ssh/authorized_keys   clé PUBLIQUE  → VÉRIFIE la signature
```

Le déroulé :

```
1. le serveur envoie un DÉFI (valeur aléatoire)
2. le client le SIGNE avec la clé privée
3. le serveur VÉRIFIE avec la clé publique qu'il détient déjà
```

> **Le serveur ne reçoit à aucun moment un secret.** Une signature ne vaut que pour son défi,
> ne se rejoue pas, et ne permet pas de reconstituer la clé privée.

- `authorized_keys` = un simple fichier texte, **une clé publique par ligne**
- `ssh-copy-id utilisateur@machine` dépose proprement, **avec les bonnes permissions**
- un **balayage de mots de passe** (comme les 1 008 `403` de `193.106.191.44` dans
  `velocite-access.log`) est **inopérant** contre des clés : rien à deviner, et chaque essai
  exige une signature valide
- SSH **n'utilise pas de certificat** dans sa forme courante (des certificats d'hôte OpenSSH
  existent et sont utilisés à grande échelle, mais pas par défaut)

---

## `known_hosts` et le modèle TOFU

SSH n'a **aucune autorité de certification**. Première connexion à une machine jamais
contactée : **tu ne possèdes rien** pour vérifier son identité. Aucune référence, aucun tiers,
aucune signature. C'est une **impasse logique**, pas un défaut d'implémentation.

```
1re connexion   le client affiche l'EMPREINTE, tu acceptes, il MÉMORISE dans ~/.ssh/known_hosts
2e connexion    il COMPARE la clé présentée à celle qu'il a mémorisée
```

> **La protection ne commence qu'à la DEUXIÈME connexion.**

### ⚠⚠ L'avertissement qu'on ne contourne jamais

```
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
```

> **C'est le même message qu'une erreur de certificat : « il y a peut-être quelqu'un au milieu ».**

| Cause **légitime** | Cause d'**attaque** |
|---|---|
| la machine a été réinstallée | quelqu'un s'est inséré sur le trajet |
| l'IP a été réattribuée à une autre VM | détournement DNS vers un autre hôte |

Les deux produisent un message **identique**. Rien dans l'avertissement ne les distingue.

> ⚠ **Donc : vérifier l'empreinte par un canal INDÉPENDANT de SSH avant d'accepter.**
> Décider depuis SSH, c'est demander à l'attaquant potentiel de confirmer qu'il n'est pas un
> attaquant.

Sur GCP, ce canal indépendant existe : la **sortie série** de la VM affiche les clés d'hôte.

**Ce qu'on ne fait pas** — et c'est l'erreur du 21/10 :

```
❌  supprimer la ligne de known_hosts pour faire taire le message
❌  ssh -o StrictHostKeyChecking=no
```

Équivalents exacts de `curl -k` : on supprime la seule vérification qui protégeait.
**Comprendre un avertissement et le contourner est pire que de ne pas le comprendre** — dans
le second cas, on va chercher.

---

## Les permissions et l'échec silencieux

```
~/.ssh                    700    (rwx------)
~/.ssh/authorized_keys    600    (rw-------)
⚠ le répertoire PERSONNEL  pas accessible en écriture au groupe ni aux autres
```

**Pourquoi :** `authorized_keys` décide **qui peut entrer**, une clé publique par ligne. S'il
est modifiable par un tiers, celui-ci **y ajoute sa propre clé** et obtient le compte. `sshd`
refuse donc de faire confiance à un fichier qu'il ne sait pas protégé.

Et le répertoire personnel compte : pouvoir écrire dans `~` permet de **remplacer `.ssh` en
entier**. D'où ⚠ **vérifier tout le chemin, pas les deux derniers éléments** :

```bash
namei -l ~/.ssh/authorized_keys     # les permissions de CHAQUE niveau
```

### Le symptôme n'est pas celui qu'on attend

> **`sshd` ne dit rien et retombe SILENCIEUSEMENT sur le mot de passe.**

Le symptôme est donc « on me demande un mot de passe », pas « clé refusée ». Le silence est
**délibéré** : annoncer « ton fichier de clés a de mauvaises permissions » renseignerait un
client **pas encore authentifié**. Le serveur ne commente jamais ses refus.

L'information est **chez lui** :

```bash
sudo journalctl -u ssh -n 30 --no-pager
# → « Authentication refused: bad ownership or modes for directory /home/achraf/.ssh »
ssh -vvv utilisateur@machine 2>&1 | grep -i 'offer\|accept\|key'
```

**Cinquième échec silencieux de la quinzaine** — `echo >>` non idempotent · le proxy WSL qui
ampute la réponse DNS · la requête HTTP bloquée faute de ligne vide · `certbot` qui réussit
sans recharger nginx · `sshd`. Ce n'est plus une anecdote, c'est une grille :

> **Quand le symptôme est « ça ne marche pas » SANS message d'erreur, la cause est chez celui
> qui a décidé de ne rien dire — et son journal, lui, parle.**

---

## Les tunnels et l'écoute locale

### ⚠ Le mécanisme à tenir en entier

```
$ ss -tlnp
LISTEN  0  244  127.0.0.1:5432   users:(("postgres",…))   ← inatteignable du réseau
LISTEN  0  511  0.0.0.0:443      users:(("nginx",…))      ← joignable
```

Tu ouvres le port 5432 au pare-feu et tu tentes `psql -h 10.0.0.20`. Déroulé complet :

```
1. le pare-feu AUTORISE et laisse passer le paquet              ✅
2. le paquet arrive avec DESTINATION = 10.0.0.20:5432
3. le noyau cherche un socket en écoute pour 10.0.0.20:5432
4. il n'en trouve AUCUN — PostgreSQL écoute sur 127.0.0.1
5. le paquet est jeté
```

> ⚠ **Le pare-feu n'est jamais entré en jeu.** Il a fait exactement ce qu'on lui demandait.
> C'est le noyau, après, qui n'avait personne à qui remettre le paquet.

Et un paquet venu de l'extérieur **ne peut pas** porter `127.0.0.1` en destination : les noyaux
rejettent ces paquets à l'entrée d'une interface réseau.

- `127.0.0.1` ne désigne pas **une** machine : elle désigne **« la machine qui l'utilise »**.
  Adresse **relative à celui qui la prononce**.
- un en-tête IP contient **DEUX** adresses : ⚠ **source** (d'où ça vient) et **destination**
  (où ça va). Les confondre est l'erreur classique.

> **Un service lié à `127.0.0.1` est inatteignable depuis le réseau par CONSTRUCTION, pas par
> configuration.** Aucune règle ne peut le rendre joignable, aucune règle oubliée ne peut
> l'exposer par accident.

### Le tunnel

```bash
ssh -L 15432:127.0.0.1:5432 utilisateur@10.0.0.20
```

> « ouvre le port **15432 sur MA machine** ; tout ce qui y arrive, fais-le ressortir **depuis
> la VM** vers `127.0.0.1:5432` »

```
ton client → 127.0.0.1:15432 ══ tunnel SSH chiffré ══► VM → 127.0.0.1:5432
                                                           émis PAR la VM
```

La connexion finale est émise **par la VM**, donc avec `127.0.0.1` en destination : la
contrainte est **respectée**, pas contournée. PostgreSQL reçoit une connexion locale normale.

| | `-L` **local** | `-R` **remote** |
|---|---|---|
| Port ouvert | **sur ta machine** | **sur la machine distante** |
| Usage | atteindre une base interne | exposer ton serveur local à quelqu'un |

Moyen mnémotechnique : **la lettre dit où le port s'ouvre.**

> **Modèle recommandé pour toute base de données : écoute locale + tunnel.** Jamais un port de
> base exposé. Une base sur `0.0.0.0:5432` dépend entièrement du pare-feu ; sur `127.0.0.1`,
> elle ne peut pas être exposée par erreur.

Sur GCP : **IAP TCP forwarding** — même rôle, sans IP publique sur la VM, avec contrôle IAM.

---

## Durcir `sshd` sans se verrouiller dehors

```bash
sudo sshd -t      # valide la SYNTAXE sans rien recharger   ← analogue de systemd-analyze verify
sudo sshd -T      # affiche la configuration EFFECTIVE, défauts inclus
sudo sshd -T | grep -iE 'permitrootlogin|passwordauth|port|allowusers'
```

Le `-T` est le plus utile en diagnostic : il montre la configuration **telle que `sshd` la
comprend**, pas telle qu'on croit l'avoir écrite — utile car `sshd_config` contient souvent des
`Include`, et un fragment de `/etc/ssh/sshd_config.d/` peut écraser le fichier principal.

### La discipline en trois temps

```
1. sauvegarder le fichier  PUIS  sshd -t
2. GARDER la session en cours ouverte  →  en ouvrir une SECONDE pour tester
3. ne fermer la première qu'une fois la seconde confirmée
```

> **Redémarrer `sshd` ne tue pas les sessions établies** — chaque session est servie par un
> processus enfant. C'est la session en cours qui est le **canal de réparation** :

```bash
sudo cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
sudo sshd -t && sudo systemctl restart ssh
```

Ce qui suppose la **sauvegarde faite avant** — sinon on a un canal et rien à restaurer.

### Les directives, et le piège de chacune

| Directive | Effet | Piège |
|---|---|---|
| `PermitRootLogin no` | pas de root direct | — |
| `PasswordAuthentication no` | **clés uniquement** | ⚠ **vérifier que la clé MARCHE avant** |
| `AllowGroups ssh-users` | liste blanche | ⚠ se mettre dans le groupe **d'abord** |
| `MaxAuthTries 3` | limite les essais | — |
| `Port 2222` | déplace le port | ⚠ **ne réduit PAS la surface d'attaque** |

### ⚠ La vérification obligatoire avant `PasswordAuthentication no`

Ne pas vérifier les permissions — **vérifier le résultat** (le principe en tête de fiche) :

```bash
ssh -o PasswordAuthentication=no -o PubkeyAuthentication=yes utilisateur@machine
```

Cette commande simule l'état **futur** du serveur. Si elle passe, tu survivras au durcissement.

Sinon : mot de passe désactivé **et** clé qui échoue = **aucune voie d'entrée**. Seule la
session ouverte sauve, et le jour où elle se ferme, il reste la console série (GCP) ou le
déplacement physique.

### Sur le changement de port — être honnête

> **Déplacer SSH sur un autre port n'est pas une mesure de sécurité.** Un balayage de ports le
> trouve en quelques secondes.

Ce qu'il apporte réellement : des **journaux lisibles**. Le port 22 est balayé en permanence,
`journalctl` est noyé. Sur 2222 il ne reste que le trafic légitime, donc une tentative
suspecte **se voit**. Gain d'**exploitabilité**, pas de sécurité — et il ne faut pas vendre
l'un pour l'autre, sinon on ne met pas les vraies protections.

---

## Pare-feu — l'état, l'ordre, les verdicts

### ⚠ Pourquoi une politique d'entrée `DROP` casse les connexions SORTANTES

Dispositif : entrée `DROP`, sortie `ACCEPT`, 22 et 443 autorisés en entrée. SSH marche.
`apt update`, `curl` et `dig` échouent tous en **timeout**.

```
          SOURCE                 DESTINATION
SYN       ta-VM:54321    ────►   example.com:443        sortie → ACCEPT ✅
SYN-ACK   example.com:443 ◄───   ta-VM:54321            entrée → DROP   ❌
```

> **Une connexion sortante a besoin que son trafic de RETOUR soit autorisé en entrée.** Et ce
> retour arrive sur le **port source éphémère**, pas sur 443 : dans le paquet qui revient, le
> `443` est le port **source**, et une règle d'entrée porte sur le port de **destination**.

La poignée de main ne se termine jamais → **timeout, pas erreur**. Encore le silence.

- le port source **doit** varier : c'est lui qui distingue deux connexions vers la même
  destination dans le **quadruplet** `(IP src, port src, IP dst, port dst)`
- plage éphémère mesurée : **32768 – 60999**, soit **28 231** ports → impossible à lister

### La solution : le suivi de connexions

```
-m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
```

Le noyau tient une table des connexions vues s'établir. La question devient :

> **« ce paquet appartient-il à une connexion que CETTE machine a initiée ? »**

```
ESTABLISHED   fait partie d'une connexion en cours
RELATED       lié à une connexion en cours sans en faire partie (erreur ICMP la concernant…)
```

| | Pare-feu **sans état** | Pare-feu **à état** |
|---|---|---|
| Décide sur | chaque paquet, isolément | le paquet **et** sa connexion |
| Autoriser une sortie | ouvrir **tous** les ports de retour | **une seule règle** |
| Sécurité | ports ouverts en permanence | le retour n'est accepté **que s'il a été demandé** |

Strictement meilleur sur les deux plans. Tous les pare-feu modernes sont à état, **y compris
celui de GCP**.

> **C'est la règle que tout le monde oublie à son premier pare-feu**, et le symptôme est
> toujours le même : « l'entrée est bien fermée, et plus rien ne sort ».

### L'ordre des règles — la règle morte

> **La PREMIÈRE règle qui correspond décide. Les suivantes ne sont pas évaluées.**

```
JEU A  (cassé)                          JEU B  (correct)
1. DROP   tout en entrée                1. ACCEPT tcp/22 depuis 203.0.113.0/24
2. ACCEPT tcp/22 depuis 203.0.113.0/24  2. DROP   tout en entrée
   ↑ règle MORTE : jamais évaluée
```

Insidieux parce que **la configuration a l'air correcte** : la règle qu'on cherche est bien là.

> **Règle d'écriture : du plus spécifique au plus général.** Et le `DROP` fourre-tout s'exprime
> comme **politique par défaut** plutôt que comme règle — ce qui le sort de la liste et
> supprime tout risque d'ordonnancement.

### Les trois verdicts

| Verdict | Comportement | Déjà vu comme |
|---|---|---|
| `ACCEPT` | laisse passer | — |
| `REJECT` | **répond** un `RST` ou un ICMP *unreachable* | `REFUSED` du DNS |
| `DROP` | **silence total** | *timeout* du DNS |

```
face à INTERNET  →  DROP     ne rien renvoyer ne CONFIRME PAS que la machine existe
en INTERNE       →  REJECT   échec immédiat et lisible, plutôt que 30 s d'attente
```

### Ne pas se verrouiller dehors

```bash
echo "iptables-restore < /etc/iptables/rules.v4.bak" | sudo at now + 5 minutes
```

> **On programme la réparation AVANT d'appliquer la règle risquée.** Si l'accès se coupe, la
> machine se répare seule dans cinq minutes.

`cron` ne rattrape pas une exécution manquée, mais `at` suffit ici : on reste devant la machine.

### Quel outil

```
nftables (nft)    le sous-système ACTUEL du noyau          ← ce qu'on ÉCRIT
iptables          couche de compatibilité par-dessus       ← ce qu'on LIT dans la doc
ufw / firewalld   interfaces simplifiées                   ← ce qu'on TROUVE installé
```

Trois noms, un seul moteur depuis le noyau 3.13.

---

## Le pare-feu GCP

### Une règle s'applique à une CIBLE

```
toutes les instances du réseau            le plus large
instances portant une ÉTIQUETTE RÉSEAU    ex. « ssh-autorise »
instances utilisant un COMPTE DE SERVICE  le plus fin, et le plus sûr
```

> ⚠ **Une règle ciblant une étiquette que la VM ne porte pas ne s'applique à AUCUNE
> instance.** Elle reste **valide** — et sans effet.

```
pare-feu Linux    la règle s'applique à LA machine où elle est écrite
pare-feu GCP      la règle s'applique aux instances qu'elle CIBLE explicitement
```

La console ne peut pas avertir : préparer des règles **avant** les machines est légitime.
D'où la paire **valide / applicable**, même famille que la règle morte sous Linux.

L'étiquetage est aussi ce qui rend le modèle puissant : une règle « autoriser 443 vers les
instances `web` » protège correctement **toute VM créée plus tard** avec cette étiquette, sans
toucher au pare-feu. Infrastructure déclarative.

### La priorité

```
0 ───────────────────────────► 65535      le plus PETIT nombre GAGNE
```

Un `deny` de priorité 1000 l'emporte sur un `allow` de priorité 2000, **quel que soit l'ordre
d'affichage** dans la console.

### Les deux règles implicites

Non modifiables, non supprimables, priorité **65535** — donc toujours consultées en dernier.

```
ENTRÉE   deny  tout      ← une VM neuve n'est joignable sur aucun port
SORTIE   allow tout      ← une VM neuve peut faire apt update
```

On ne peut que poser des règles **plus prioritaires devant**. Et comme les règles GCP sont
**à état**, le trafic de retour revient **sans règle d'entrée supplémentaire** : la règle
implicite `deny` ne bloque que le trafic **non sollicité**.

### Les deux pare-feu s'additionnent

```
paquet ──► pare-feu du VPC ──► pare-feu de la VM (nft/ufw) ──► le service
           (Google, hors VM)    (dans la VM)
```

> **Un paquet doit franchir les DEUX.** Un port « ouvert » dans la console mais fermé par `nft`
> sur la machine reste **fermé**.

Ordre de vérification quand un port ne répond pas : d'abord la console (plus rapide), puis
`sudo nft list ruleset` sur la VM.

| | Pare-feu local | Pare-feu VPC |
|---|---|---|
| S'exécute | **sur** la machine | **avant** la machine, chez Google |
| Si la VM est compromise | l'attaquant le désactive | **il tient toujours** |
| Portée | cette machine | toutes les instances ciblées |

Le VPC **survit à la compromission de la machine** : c'est la couche qui compte, le local est
un complément.

### IAP TCP forwarding

SSH vers une VM **sans IP publique et sans ouvrir le port 22**, le trafic passant par
l'infrastructure Google après contrôle IAM. C'est le tunnel de la partie 3 à l'échelle du
fournisseur : au lieu d'ouvrir un port, **on authentifie l'accès**. Modèle recommandé.

---

## Commandes

```bash
# SSH
ssh-keygen -t ed25519                        # générer une paire
ssh-copy-id utilisateur@machine              # déposer la publique avec les bonnes permissions
ssh -vvv utilisateur@machine                 # diagnostic verbeux côté client
namei -l ~/.ssh/authorized_keys              # permissions de CHAQUE niveau du chemin
ssh -o PasswordAuthentication=no u@m         # tester l'état FUTUR avant de durcir
ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub   # empreinte d'une clé d'hôte

# sshd (sur le serveur)
sudo sshd -t                                 # valider la syntaxe sans recharger
sudo sshd -T                                 # configuration EFFECTIVE, défauts inclus
sudo journalctl -u ssh -n 30 --no-pager      # pourquoi une clé a été refusée

# tunnels
ssh -L 15432:127.0.0.1:5432 u@vm             # port 15432 chez MOI → base distante
ssh -R 8080:127.0.0.1:3000 u@vm              # port 8080 LÀ-BAS → mon serveur local
ssh -J bastion u@cible                       # rebond par un bastion (ProxyJump)

# pare-feu
sudo nft list ruleset                        # le jeu de règles complet
sudo ss -tlnp                                # ce qui écoute, et SUR QUELLE ADRESSE
echo "iptables-restore < /etc/iptables/rules.v4.bak" | sudo at now + 5 minutes

# GCP
gcloud compute firewall-rules list
gcloud compute instances describe VM --format='value(tags.items)'    # les étiquettes portées
```
