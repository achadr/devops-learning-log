# GCP — Compute Engine : machines, disques, instantanés, images, démarrage

> Fiche du 27/10 (semaine 3, jour 4), écrite après le QCM du 28/10 (17/20).
> Tout vient de la documentation officielle **lue par moi**, et d'une mesure de mon backend.
> ⚠ = raté réel (oral du 27/10 et QCM du 28/10).

---

## Les paires à ne pas inverser

⚠ **Le profil `highmem` et la famille optimisée pour la mémoire** (QCM Q2 ; oral : « highmem = le type ») :

| | Profil `highmem` | Famille **optimisée pour la mémoire** |
|---|---|---|
| Ce que c'est | un **profil** de la famille à **usage général** | une **famille** à part |
| Mémoire | 7 à 12 Go par vCPU (8 en général) | des **téraoctets** : série M3, de 1 à 4 To |
| Exemple | `n2-highmem-4` | série M3 |
| Pour | une application qui veut plus de mémoire par vCPU | SAP HANA, très grosses bases en mémoire |

⚠ **L'image et le script de démarrage** (QCM Q11 : « une métadonnée » pour 10 VM identiques) :

| | **Image** | **Script de démarrage** (métadonnée) |
|---|---|---|
| Ce que c'est | un disque de démarrage **complet** | des commandes exécutées **à chaque démarrage** |
| Porte | ce qui change **peu** : système, Node | ce qui change **souvent** : récupérer la dernière version de l'app |
| Pour 10 VM identiques | ✅ **le modèle** | le complément |

| | **Mémoire (RAM)** | **Stockage (disque)** |
|---|---|---|
| Sert à | ce que l'application manipule **en tournant** | ce qui doit **durer** |
| Mon backend | **55,8 Mio** mesurés (`docker stats`) | la base SQLite |
| Dimensionné par | le type de machine | le disque, choisi à part |

| | **Disque persistant** | **SSD local** |
|---|---|---|
| Où il vit | à part, sur le stockage réseau de Google | fixé au serveur physique |
| Vitesse | rapide | **le plus rapide** : pas de réseau |
| À l'arrêt de la VM | données **conservées** | données **jetées**, sauf `--discard-local-ssd=False` (**facturé**) |
| Usage | ma base | caches, données temporaires |

| | **Instantané** | **Image** |
|---|---|---|
| Sert à | **sauvegarder** un disque et y revenir | **créer** des VM identiques |
| Contenu | **incrémental** : seulement les changements depuis le précédent | complet |

---

## 1. Familles, séries, types

⚠ **Six familles** (QCM Q3 et oral : « trois ») — la phrase de définition n'en citait que trois **en exemple** :

```
usage général          N4, N4A, N4D, N2, N2D, N1 · C4, C4A, C4D, C3, C3D · E2 · Tau T2D, T2A
+ « Optimized workloads » :
stockage   Z3, Z4D, Z4M        calcul       H4D, H3, C2, C2D      réseau   C4N, M4N
mémoire    X5, X4, M4, M4N, M3, M2, M1                            accélérateurs (GPU)  A4X Max, A4X, A4, A3, A2, G4, G2
```

```
famille      à usage général · stockage · calcul · réseau · mémoire · accélérateurs
  série      n2, e2, c4…              génération et plateforme
    type     n2-standard-4            = série - profil - nombre de vCPU  → 4 vCPU, 16 Go
```

| Profil | Mémoire par vCPU (typique) |
|---|---|
| `highcpu` | 1 à 3 Go (2) |
| `standard` | 3 à 7 Go (4) |
| `highmem` | 7 à 12 Go (8) |

> **On choisit sur une mesure.** Mon backend : 55,8 Mio → **usage général, `standard`**.
> L'`e2-micro` du Free Tier appartient à cette famille.

## 2. Le script de démarrage, par les métadonnées

| Clé | Script | Taille |
|---|---|---|
| `startup-script` | passé directement | ≤ 256 Ko |
| `startup-script-url` | dans Cloud Storage | > 256 Ko |

- chaque valeur de métadonnée ≤ **256 Ko**, toutes ensemble ≤ **512 Ko**
- un script défini sur la **VM** l'emporte sur celui du **projet**
- lu au démarrage par l'environnement invité, préinstallé dans les images publiques

Question ouverte : un petit script dans Cloud Storage via `startup-script-url` → aucune phrase trouvée, à tester en lab.

## 3. Le compte de service d'une VM

| | |
|---|---|
| **Qui** | un compte de service **géré par moi**, dédié, attaché à la VM |
| **Quoi** | `roles/secretmanager.secretAccessor` |
| **Où** | sur **ce seul secret** |
| **À éviter** | le compte par défaut (peut avoir `Éditeur`) |

---

## 4. Lab GSP001 « Create a Virtual Machine » — mesuré le 28/10 (100/100)

| Observé | Ce que ça montre |
|---|---|
| onglets *General purpose, Compute, Memory, Network, Storage, GPUs, TPUs* | les familles, dans la console |
| `e2-medium` : 2 vCPU, 4 Go, « 1 shared core » | série E2, famille à usage général |
| « Balanced persistent disk », 10 Go · calendrier d'instantanés par défaut | disque persistant |
| cocher « Allow HTTP traffic » → étiquette **`http-server`** | une étiquette **sélectionne** la VM |
| `default-allow-http` : `tcp:80` → cible `http-server` · ssh, rdp, icmp, internal : sans cible | la règle s'applique aux VM étiquetées |
| `gcelab2` créée par `gcloud` : **aucune étiquette** | son port 80 ne serait pas ouvert |
| nginx : maître **root**, 2 workers **`www-data`** | moindre privilège, un worker par vCPU |
| IP interne `10.128.0.3`, externe `34.66.21.47` | l'externe est traduite en amont |
| ⚠ compte attaché aux deux VM : **compte par défaut** `…-compute@developer…`, avec **`roles/editor`** | ce qu'il faut éviter, mesuré (QCM Q4 : ⚠ « agent de service ») |
| instantané `gcelab-snap` : emplacement **`us`**, **695,34 Mo** pour 10 Go | multirégion · seuls les blocs utilisés |

```bash
gcloud compute instances describe gcelab --zone=$ZONE --format="yaml(tags,serviceAccounts)"
gcloud compute firewall-rules list --format="table(name,allowed,targetTags)"
```

⚠⚠ **Dans un lab, aucune ressource hors manuel** : l'aide de Google Skills prévient qu'au-delà, le
lab s'arrête et le compte peut être bloqué. Les commandes de **lecture** restent sûres.

---

Sources : [Types de machines](https://docs.cloud.google.com/compute/docs/machine-types) ·
[Machines à mémoire optimisée](https://docs.cloud.google.com/compute/docs/memory-optimized-machines?hl=fr) ·
[gcloud compute instances stop](https://docs.cloud.google.com/sdk/gcloud/reference/compute/instances/stop) ·
[Instantanés](https://docs.cloud.google.com/compute/docs/disks/snapshots) ·
[Scripts de démarrage Linux](https://docs.cloud.google.com/compute/docs/instances/startup-scripts/linux?hl=fr) ·
[Métadonnées personnalisées](https://docs.cloud.google.com/compute/docs/metadata/setting-custom-metadata?hl=fr) ·
[Comptes de service de Compute Engine](https://docs.cloud.google.com/compute/docs/access/service-accounts)
