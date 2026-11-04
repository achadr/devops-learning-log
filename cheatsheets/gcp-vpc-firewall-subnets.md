# GCP — VPC, sous-réseaux, routes et pare-feu

> Fiche du 02/11 (semaine 4, jour 1), écrite après le QCM du 03/11 (20/20).
> Lab **GSP016** « Implement VPC Networking Fundamentals » : 50/50.
> ⚠ = raté réel à l'oral du 02/11 (aucun au QCM du lendemain : les corrections ont tenu).

---

## Les paires à ne pas inverser

| | **Réseau VPC** | **Sous-réseau** |
|---|---|---|
| Portée | **global** | **régional** |
| Mes labs | `default` (mode auto) | `10.128.0.0/20` (us-central1) · `10.142.0.0/20` (us-east1) |

| | **Mode auto** | **Mode personnalisé** |
|---|---|---|
| Sous-réseaux | un par région, créés par Google (`default` : 24) | aucun ; c'est moi qui les crée |
| Plages | `/20` par région, dans `10.128.0.0/9` | choisies par moi |
| Deux réseaux de ce type | **non appairables** : plages identiques | appairables si sans chevauchement |
| Production | ✗ | ✅ recommandé |

| | **Route** | **Pare-feu** |
|---|---|---|
| Donne | le **chemin** | le **droit** |
| Création | automatique : `0.0.0.0/0` → passerelle Internet + une par sous-réseau | `default` : 4 règles · réseau créé à la main : **aucune** |

| | **Réseau `default`** | **Mon réseau personnalisé** |
|---|---|---|
| Règles à la création | `allow-internal`, `-ssh`, `-rdp`, `-icmp` (priorité 65534) | **aucune** |
| dev → prod | autorisé par `default-allow-internal` | ⚠ **refusé** par la règle implicite d'entrée |
| SSH depuis Internet | **ouvert à toutes les VM** (`0.0.0.0/0`, sans cible) | fermé, sauf règle explicite |

> ⚠ Oral du 02/11 : « par défaut, toutes les instances communiquent ». Vrai **seulement** dans `default`,
> grâce à `default-allow-internal`.

⚠ **Saturation d'un sous-réseau** (oral du 02/11 : « on ajoute une plage secondaire ») :

| | **Plage principale** | **Plage secondaire** |
|---|---|---|
| Sert à | l'adresse **principale** des VM | **uniquement** les plages d'alias IP |
| Évolution | **agrandissable**, jamais réduite ni remplacée | — |
| Prod saturée | ✅ l'agrandir, **si l'espace contigu est libre** | ✗ n'ajoute aucune adresse de VM |

⚠ **L'écart entre deux plages ne protège rien** (oral du 02/11 : « tampon de sécurité ») : c'est le
**pare-feu** qui isole. L'écart ne sert qu'à la **réserve** d'adresses.

---

## 1. Les adresses

- **4 adresses inutilisables** par plage principale : réseau, passerelle, avant-dernière (réservée), diffusion
  → `/24` = **252** utilisables · `/20` = **4 092**
- pas de chevauchement entre plages d'un même VPC, ni entre réseaux appairés

## 2. Le pare-feu VPC

- **sans cible** → s'applique à **toutes les instances** du réseau
- **implicites** : entrée **refusée**, sortie **autorisée**
- **à état** : le retour d'une connexion autorisée est autorisé — mon `ESTABLISHED,RELATED` de la semaine 2, intégré
- **étiquette** = sélectionne les VM visées par une règle (pas d'IP, pas d'ouverture de port en soi)
- priorité par défaut : **1000** (mesuré au lab)

## 3. Mon plan `task-manager-vpc` (mode personnalisé, `10.50.0.0/16`)

| Environnement | Plage | Utilisables | Peut grandir jusqu'à |
|---|---|---|---|
| dev | `10.50.0.0/24` | 252 | — |
| test | `10.50.1.0/24` | 252 | — |
| staging | `10.50.2.0/24` | 252 | — |
| prod | `10.50.16.0/24` | 252 | `10.50.16.0/20` (4 092) |

Réserve : `10.50.3.0` → `10.50.15.255`, puis `10.50.32.0` → fin. Compromis assumé : hors-prod non extensibles.

## 4. Lab GSP016 — mesuré

| Observé | Ce que ça montre |
|---|---|
| `default` : Auto, 24 sous-réseaux, 4 règles | le réseau livré avec chaque projet |
| `taw-custom-network` : Custom, 3 sous-réseaux `/16`, **0 règle** | tout fermé à la création |
| MTU **1460** | encapsulation du réseau de Google |
| 4 routes : `0.0.0.0/0` → `default-internet-gateway` + 3 de sous-réseau | le chemin existe toujours |
| `nw101-allow-rdp` : toutes les VM, depuis Internet | ⚠ mauvaise pratique, recréée pour l'exercice |

```bash
gcloud compute networks list
gcloud compute routes list --filter="network=<réseau>" --format="table(name,destRange,nextHopGateway,priority)"
gcloud compute firewall-rules list --format="table(name,allowed,targetTags)"
```

---

Sources : [VPC networks](https://docs.cloud.google.com/vpc/docs/vpc) ·
[Subnets](https://docs.cloud.google.com/vpc/docs/subnets) ·
[VPC firewall rules](https://docs.cloud.google.com/firewall/docs/firewalls) ·
[VPC Network Peering](https://docs.cloud.google.com/vpc/docs/vpc-peering)

---

## 5. Priorités et règles de sortie (03/11)

> QCM du 04/11 : **19/20**. ⚠ = raté réel.
> Lab *Configuring VPC Firewalls* (GSP, catalogue 1430) : **100/100**.

### L'ordre d'évaluation

| | |
|---|---|
| Plage | **0 à 65535** · défaut **1000** |
| Ordre | le **plus petit numéro** est évalué en premier · la première règle qui correspond s'applique |
| allow contre deny | deny l'emporte **seulement à priorité égale** |
| Règles implicites | tout en bas : **65535** (`default-allow-*` : 65534) |
| Construire | règle générale **en bas** (grand nombre), exceptions **au-dessus** (plus petit) |

> C'est l'inverse du `z-index` : le plus **petit** gagne.
> « Much higher priority of 10,000 » (manuel) = **très basse** priorité. Lire le nombre, pas le mot.

### Entrée et sortie

| | **Entrée** | **Sortie** |
|---|---|---|
| ⚠ La cible est la VM qui… | **reçoit** | **envoie** |
| Implicite | refusée | **autorisée** |
| Autre extrémité | source | destination (défaut `0.0.0.0/0`) |

- Un trafic passe seulement si **la sortie de l'expéditeur ET l'entrée du destinataire** l'autorisent.
- Les priorités d'entrée et de sortie **ne se comparent pas** : deux listes séparées.
- À état : la **réponse** d'une connexion autorisée ne peut pas être refusée.

### Lab — les 4 règles de `mynetwork`, mesurées

| Règle | Sens | Priorité | Effet observé |
|---|---|---|---|
| `allow-ssh-from-cs` (tcp:22, source = IP de Cloud Shell, cible `lab-ssh`) | entrée | 1000 | SSH depuis Cloud Shell ✅ · bouton SSH de la console ✗ |
| `allow-icmp-internal` (source `10.128.0.0/9`, sans cible) | entrée | 1000 | ping interne ✅ (25 ms, us-central1 ↔ us-east4) |
| `deny-icmp-all` | entrée | 500 → **2000** | à 500 : ping ✗ · à 2000 : ping ✅ |
| `egress-deny-icmp-all` | **sortie** | 10000 | ping ✗ malgré l'allow d'entrée |

Autres mesures :
- réseau sans règle → SSH **en attente** : paquet **jeté**, aucune réponse (comme `DROP`)
- ping de l'adresse **externe** ✗ : la source devient l'**IP externe de l'expéditeur**, hors de `10.128.0.0/9`
- deux VM de deux VPC avec la **même** adresse `10.128.0.2` → deux réseaux auto ne s'appairent pas
- `mynetwork` (auto) : **2 sous-réseaux** seulement, le projet n'autorisant que 2 régions (`gcp.resourceLocations`)
- `gcloud` sur la VM → *insufficient authentication scopes* : **7 scopes par défaut, aucun pour Compute Engine**

```bash
gcloud compute firewall-rules create <nom> --network <réseau> --action DENY --direction EGRESS \
  --rules icmp --priority 10000
gcloud compute firewall-rules update <nom> --priority 2000
gcloud compute firewall-rules list --filter="network:<réseau>"
gcloud compute instances add-tags <VM> --zone=<zone> --tags lab-ssh
gcloud compute instances describe <VM> --zone=<zone> --format="yaml(serviceAccounts)"
```

Source : [VPC firewall rules](https://docs.cloud.google.com/firewall/docs/firewalls)
