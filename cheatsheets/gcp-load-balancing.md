# GCP — Équilibreurs de charge

> Fiche du 04/11 (semaine 4, jour 3), écrite après le QCM du 05/11 (20/20).
> Lab **GSP007** *Configure a Passthrough Network Load Balancer* : 100/100.
> ⚠ = raté réel à l'oral du 04/11.

---

## Pourquoi

Un groupe géré **ajoute, retire et recrée** ses VM : aucune adresse de VM n'est stable ni suffisante.
→ **une adresse stable devant le groupe**, qui répartit le trafic entre les VM **saines**.

## Les trois axes

| Axe | | |
|---|---|---|
| Couche | **Application** = couche 7, HTTP(S), lit l'URL (comme mon nginx) | **Network** = couche 4, TCP/UDP, IP + port |
| Connexion | **proxy** : termine la connexion, en ouvre une autre | **passthrough** : transmet sans terminer |
| Clients | **externe** : Internet | **interne** : dans Google Cloud |
| Backends | **global** : plusieurs régions | **régional** : une seule région |

> ⚠ global ≠ externe : « global » parle des **backends**, « externe » des **clients**.

## Proxy ou passthrough

| | **Proxy** | **Passthrough** |
|---|---|---|
| Connexion du client | terminée, une nouvelle vers le backend | transmise telle quelle |
| ⚠ L'aller | passe par lui | **passe aussi par lui** (il choisit le backend) |
| Le retour | repasse par lui | **direct** du backend au client |
| Le backend voit | l'IP du **proxy** | l'IP du **client** (mesuré : Cloud Shell) |
| Pare-feu des VM | autoriser le proxy | autoriser **les clients** |

> ⚠ Derrière un proxy, sans `trust proxy` : `req.ip` = **le proxy seul**.
> L'IP du client n'est que dans l'**en-tête** `X-Forwarded-For`, ignoré.

## La vérification de l'état

- elle teste le **chemin configuré** — au lab : port **80**, chemin **`/`** (⚠ j'ai dit « /health »)
- journal Apache : `GET / 200 "GoogleHC/1.0"`, plusieurs fois par seconde
- même vérification, trois usages :

| | Que fait-il d'une VM malade ? |
|---|---|
| Autohealing | la **recrée** |
| Équilibreur | l'**écarte** du trafic jusqu'à ce qu'elle soit saine |
| Autoscaling | rien : il suit la **charge**, pas la santé |

## Mon choix pour `task-manager-api`

HTTP → **Application** · utilisateurs sur Internet → **externe** · backends dans us-central1 → **régional**.

## Lab GSP007 — les ressources, dans l'ordre

```bash
gcloud compute addresses create network-lb-ip-1 --region us-central1          # IP statique régionale
gcloud compute http-health-checks create basic-check                          # port 80, chemin /
gcloud compute target-pools create www-pool --region us-central1 \
  --http-health-check basic-check                                             # VM de la MÊME région
gcloud compute target-pools add-instances www-pool --instances www1,www2,www3
gcloud compute forwarding-rules create www-rule --region us-central1 \
  --ports 80 --address network-lb-ip-1 --target-pool www-pool                 # IP + port → pool
```

| Mesuré | Ce que ça montre |
|---|---|
| 13 timeouts au début, puis des réponses | rien n'arrive tant que les VM ne sont pas vues saines |
| ⚠ curl **directs** OK avant l'équilibreur | ce n'était **pas** l'installation d'Apache |
| répartition sans ordre fixe (4 / 5 / 1 sur 10) | pas un tour de rôle strict (algorithme non lu) |
| Apache voit `35.195.249.49` = Cloud Shell | **passthrough** : IP du client conservée |
| règle tcp:80 **sans source** → `0.0.0.0/0` | chaque VM restait joignable **en direct** |
| `--no-service-account --no-scopes` | moindre privilège : aucune API appelée |

```bash
# voir ce que voit le backend, sans les vérifications de l'état
gcloud compute ssh www1 --zone us-central1-a \
  --command "sudo grep -v GoogleHC /var/log/apache2/access.log | tail -n 5"
```

---

Sources : [Cloud Load Balancing overview](https://docs.cloud.google.com/load-balancing/docs/load-balancing-overview) ·
[Use VPC firewall rules](https://docs.cloud.google.com/vpc/docs/using-firewalls)
