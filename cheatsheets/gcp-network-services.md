# GCP — Services réseau : NAT, DNS, Shared VPC, VPN

> Fiche du 05/11 au soir (semaine 4), écrite après le QCM du 10/11 (13/13).
> Niveau visé : **savoir lequel choisir et pourquoi** (examen ACE). Pas de lab.

---

## Quel besoin, quel service

| Besoin | Service | À retenir |
|---|---|---|
| VM **sans IP externe** qui doivent **sortir** vers Internet | **Cloud NAT** | sortie seulement · **aucune connexion entrante non sollicitée** · régional · sur un Cloud Router, sans VM proxy |
| trouver un service **par son nom** | **Cloud DNS** | zone **publique** = Internet · zone **privée** = les VPC choisis |
| **plusieurs projets** dans **un seul réseau** | **Shared VPC** | 1 VPC dans le projet **hôte** · projets **de service** rattachés · même organisation |
| relier un **réseau hors de Google** | **Cloud VPN** | IPsec, chiffré · **HA VPN 99,99 %** (BGP) · Classic 99,9 % (statique) |

## Pourquoi NAT

Une VM sans IP externe n'a **aucune adresse publique** à mettre en source : ses paquets ne peuvent pas aller
sur Internet. NAT lui prête des IP externes **partagées** et ne laisse revenir que les **réponses**,
comme le pare-feu à état (`ESTABLISHED,RELATED`).

| | IP externe par VM | Cloud NAT |
|---|---|---|
| La VM sort | ✅ | ✅ |
| Internet ouvre une connexion vers la VM | possible | ❌ jamais |

## DNS : traduire n'est pas protéger

- `db.taskmanager.internal` → zone **privée** · `api.taskmanager.com` → zone **publique**
- ⚠ une zone privée **cache un nom**, elle ne protège pas la donnée :
  ce sont le **pare-feu**, l'**absence d'IP publique** et **IAM** qui protègent

## Shared VPC

```
Projet HÔTE tm-network ── VPC tm-vpc (sous-réseaux front / back / data, pare-feu)
      ▲               ▲               ▲
tm-frontend      tm-backend       tm-data        ← projets de SERVICE
```

- **un seul** VPC, pas d'appairage · un projet n'est **jamais** hôte et service à la fois
- les équipes produit créent des VM, **pas** le réseau → **moindre privilège**, audit à un seul endroit
- Network Admins : tout le réseau **sauf** les règles de pare-feu et les certificats SSL

## VPN

- trafic **chiffré entre les deux passerelles** (Google ↔ bureau), même s'il traverse Internet
- ⚠ « You cannot use Cloud VPN to route traffic to the public internet » → pour sortir sur Internet : **NAT**

---

Sources : [Cloud NAT overview](https://docs.cloud.google.com/nat/docs/overview?hl=en) ·
[Cloud DNS overview](https://docs.cloud.google.com/dns/docs/overview) ·
[Shared VPC](https://docs.cloud.google.com/vpc/docs/shared-vpc?hl=en) ·
[Cloud VPN overview](https://docs.cloud.google.com/vpn/docs/concepts/overview)
