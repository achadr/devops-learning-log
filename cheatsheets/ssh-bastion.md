# SSH — bastion, saut (`ProxyJump`) et clés d'hôte

> Fiche du 28/10 (semaine 3, jour 4), écrite après le QCM du 29/10 (18/20).
> Lab local : `~/projects/bastion-lab`. ⚠ = raté réel du 28/10.

---

## Les paires à ne pas inverser

| | **Bastion** (*jump host*) | **Cible** |
|---|---|---|
| Exposée à Internet | **oui**, une seule porte d'entrée | **non** |
| Dans le lab | `-p 2222:22` | aucun `-p` (seulement `22/tcp`) |
| Sur GCP | VM avec IP externe, port 22 ouvert | VM **sans IP externe**, pare-feu qui n'autorise que le bastion |

| | **Clé privée** | **Clé publique** |
|---|---|---|
| Fichier | `lab_key` — `600` | `lab_key.pub` — `644` |
| Où | **ne quitte jamais ma machine** | déposée dans `authorized_keys` des serveurs |
| ⚠ Sur le bastion | **jamais** : la machine la plus exposée livrerait la clé de tout le réseau interne | oui |

⚠ **La clé d'hôte : image ou démarrage ?** (oral du 28/10 : « dans l'image, ça ne change pas ») :

| | **Image** | **Démarrage de chaque machine** |
|---|---|---|
| Ce qui y va | ce qui est **commun** et **stable** : système, Node | ce qui **change souvent** ou qui est **propre à chaque machine** |
| Clé d'hôte SSH | ✗ copiée à l'identique partout | ✅ unique |

> Mesuré : `ssh-keygen -A` au build → bastion et cible avec **la même empreinte**
> (`root@buildkitsandbox`), et SSH qui signale « *known by the following other names* ».

| Message SSH | Signifie | Réaction |
|---|---|---|
| `The authenticity of host … can't be established` | **première** connexion : rien en mémoire | vérifier l'empreinte par un canal indépendant |
| `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!` | une clé était connue et **ne correspond plus** | ⚠⚠ ne jamais contourner : vérifier d'abord |

---

## 1. L'architecture

```
ton PC ──Internet──▶ bastion :22 (public) ──réseau interne──▶ cible :22 (privé)
```

## 2. Vérifier l'empreinte en la collant

À la question `(yes/no/[fingerprint])`, **coller l'empreinte** au lieu de `yes` :
SSH compare ; identique → accepté, différente → refusé (OpenSSH 8.0 et plus).

L'empreinte collée doit venir **d'un autre canal** — dans le lab, l'équivalent local de la console série :

```bash
docker exec bastion ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

## 3. Le saut

⚠ Depuis le bastion, `ssh admin@cible` → **mot de passe demandé** : la clé privée est restée sur le PC,
SSH retombe silencieusement sur le mot de passe.

⚠ `ssh -i ./lab_key -J admin@localhost:2222 admin@cible` → mot de passe demandé **par le bastion** :
d'après `man ssh`, les options de la ligne de commande s'appliquent à la **destination**, pas aux
machines de saut. Les sauts se configurent dans `~/.ssh/config`.

```
Host bastion-lab
    HostName     localhost
    Port         2222
    User         admin
    IdentityFile ~/projects/bastion-lab/lab_key

Host cible-lab
    HostName     cible                      # le nom vu DEPUIS le bastion
    User         admin
    IdentityFile ~/projects/bastion-lab/lab_key   # ⚠ chemin complet, pas ./lab_key
    ProxyJump    bastion-lab
```

```bash
ssh cible-lab        # traverse le bastion ; la clé privée reste sur le PC
```

## 4. La limite du lab local

```bash
nc -vz -w 3 172.19.0.3 22      # depuis l'hôte WSL → succeeded
```

Sans `-p`, la cible n'est publiée sur **aucun port de l'hôte**. Mais l'hôte Docker est **la passerelle**
du réseau Docker : lui la voit. Le vrai cloisonnement viendra du VPC (semaine 4) : VM sans IP externe
+ règle de pare-feu dont la source est le bastion. Équivalent géré sur GCP : **IAP TCP forwarding**.

## 5. Session SSH : à savoir

- **Ctrl + C** est transmis au shell **distant** : il annule la ligne, il ne coupe pas la connexion.
- Couper une session figée : **Entrée, `~`, `.`** (séquence d'échappement ; à vérifier sur clavier AZERTY).
- Ne pas brancher `| tail` sur une session interactive : `tail` attend la fin de `ssh`.

## Non élucidé

La toute première tentative vers le bastion s'est terminée par « Connection closed », non reproduite.
