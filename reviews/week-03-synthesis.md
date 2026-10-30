# Semaine 3 — Synthèse (23/10 → 30/10)

> Écrite à partir des **mesures** : QCM, labs, commandes. Pas d'auto-évaluation.

## Les scores de la semaine

| Date | QCM | Score |
|---|---|---|
| 23/10 | fondations GCP | 80 % |
| 27/10 | IAM | **100 %** |
| 27/10 | conditions IAM, gcloud | 75 % |
| 28/10 | Compute Engine | 85 % |
| 29/10 | lab GSP001 + bastion | 90 % |
| 30/10 | lab GSP087, groupes d'instances | **95 %** |
| 30/10 | **QCM global n° 1, semaine entière** | **70 %** → 6 lacunes, toutes réenseignées le jour même |
| 30/10 | **QCM global n° 2, questions nouvelles** | _à reporter_ |

Les QCM du jour mesurent ce qui est **frais** ; le QCM global, sujets mélangés, mesure ce qui est **retenu**.

| Lab Google Skills | Score |
|---|---|
| GSP001 · Create a Virtual Machine (1 crédit) | 100/100 |
| GSP087 · Autoscaling Managed Instance Groups (5 crédits) | 100/100 |

## Ce que je sais faire maintenant (prouvé par une mesure)

| Notion | La preuve |
|---|---|
| Choisir IaaS / PaaS / SaaS, régions et zones | QCM global Q1, Q2 |
| Hiérarchie et héritage des autorisations | QCM global Q3 |
| Créer un compte de service au moindre privilège | `logs-reader`, 26/10 |
| Lire l'ordre d'évaluation IAM | Policy Troubleshooter, 26/10 |
| Poser une condition d'expiration et la vérifier | `--request-time` : `CAN_ACCESS` puis `CANNOT_ACCESS`, 27/10 |
| Distinguer agent de service et compte par défaut | QCM global Q10 ; `roles/editor` mesuré, 28/10 |
| Choisir une famille de machines sur une mesure | 55,8 Mio (`docker stats`) → usage général |
| Disque persistant, SSD local, instantané, image | QCM global Q12, Q13 ; instantané de 695 Mo, 28/10 |
| Script de démarrage par métadonnée | `startup-script-url`, 3 Ko, `nodeapp: available`, 29/10 |
| Construire un bastion et un saut SSH | `~/.ssh/config` + `ProxyJump`, 28/10 |
| Créer un modèle d'instance et un groupe avec autoscaling | GSP087, 100/100 |
| Découper un CIDR et le vérifier | LAB-05 : `/18` puis `/20`, vérifié avec `ipaddress`, 30/10 |
| *Scopes* et OS Login | 30/10 — **à confirmer au prochain QCM** |

## Les paires que je confonds encore (QCM global du 30/10)

| Paire | Ma réponse | La bonne | Réenseignée par |
|---|---|---|---|
| gratuit ↔ sans compte de facturation | « créer une `e2-micro` gratuite » | facturation obligatoire, même pour le Free Tier | le dépassement doit pouvoir être facturé |
| connaître l'ID ↔ avoir un rôle | « oui, s'il connaît l'ID » | refus par défaut | `logs-reader` sans rôle, 26/10 |
| `config set` ↔ `--project` | `config set` | `--project=` | script planté au 3ᵉ projet |
| `-i` ↔ le saut | « la cible a refusé la clé » | `-i` ne vaut que pour la destination | `~/.ssh/config` |
| étiquette ↔ IP externe | « elle donne une IP externe » | elle **sélectionne** les VM d'une règle | `gcelab2` : IP externe sans étiquette |
| prudence ↔ coût (Spot) | « standard, par prudence » | Spot pour un traitement tolérant aux pannes | ce qu'on perd vraiment à la préemption |

Et toujours en surveillance : **compte par défaut ↔ agent de service** (deux ratés au QCM, juste à l'oral).

## Ce que j'ai mesuré moi-même (les 5 mesures qui m'ont le plus appris)

1. **`gcloud config set project`** laisse la configuration sur le mauvais projet, sans avertissement.
2. **`roles/editor`** sur le compte par défaut de Compute Engine, attaché à toutes mes VM.
3. **La même empreinte** sur le bastion et la cible : une clé d'hôte générée dans l'image est copiée partout.
4. **Mon groupe passé seul de 1 à 2 VM**, et `builtin-igm` qui ne réduit pas un creux de quelques minutes.
5. **7 lignes « Error » dues à `set -v`** : la gravité d'un journal est une étiquette, pas un diagnostic.

## Les trous qui restent

| Trou | Prévu |
|---|---|
| *scopes*, OS Login, CIDR : à mesurer au QCM du lendemain | début de S4 |
| les 6 lacunes du QCM global : à confirmer en reprise | 31/10, 1/11, 6/11 |
| agent SSH (`ssh-agent`) | non étudié |
| lab DNS « casser et réparer » (trou n° 3 de la semaine 2) | à planifier |
| LAB-02 (saturations 3, 4, 5) | à planifier |

**Fermé cette semaine** : trou n° 1 de la semaine 2 (bastion SSH, 28/10) · trou n° 4 (CIDR, LAB-05, 30/10).
