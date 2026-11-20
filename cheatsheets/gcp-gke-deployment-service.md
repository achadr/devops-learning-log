# GKE — Deployment et Service (lab 164380)

> Fiche du 19/11 (semaine 6, jour 2), écrite après le QCM du 20/11 : **19/20 (95 %)**. Le seul raté (Q5, paire Deployment ↔ Service
> inversée) est un clic confirmé à l'oral sur un cas nouveau ; 3 questions ouvertes sans options : **3/3**.
> ⚠ = raté ou imprécision réels du 19/11 · ⚠⚠ = erreur qui coupe le trafic ou expose ce qui ne devait pas l'être.
> Chiffres : mes sorties du lab 164380 (1 crédit, 100/100). Sources : kubernetes.io (Deployments, Service), lues par moi ;
> GKE · LoadBalancer Services (lue par Claude, donnée à lire sur la page Fil S6).

---

## Les paires à ne pas inverser

| | | |
|---|---|---|
| **Deployment** : garde N copies en vie (état voulu, `.spec.replicas`) | ↔ | **Service** : adresse stable devant elles ; **ne crée aucun Pod** |
| **Label Kubernetes** (`app: backend`) : sélectionne des **Pods** | ↔ | **Étiquette réseau GCP** (`http-server`) : sélectionne des **VM** (pare-feu) · aucun des deux ne donne d'IP |
| **ClusterIP** : adresse interne au cluster, type par défaut | ↔ | **LoadBalancer** : exposé à l'extérieur (sur GKE : équilibreur **pass-through**) |
| **`port`** : l'entrée du Service (80) | ↔ | **`targetPort`** : le port du conteneur (80 pour nginx, 3000 pour mon backend) |
| **CLUSTER-IP** : joignable depuis le cluster | ↔ | **EXTERNAL-IP** : joignable depuis Internet · un Service LoadBalancer a **les deux** |
| **« created »** : l'état voulu est **enregistré** | ↔ | **`get pods`** : l'état **réel** (Pending → ContainerCreating → Running) |

---

## 1. Qui fait quoi

```
Deployment (image + replicas)
   └─ crée un ReplicaSet ──> qui crée les Pods
   le CONTRÔLEUR compare en continu le réel au voulu, et corrige l'écart

Service backend (nom stable + sélecteur app: backend)
   └─ cherche EN CONTINU les Pods qui portent app: backend
   le nom « backend » est résolu par le SERVEUR DNS DU CLUSTER (ex. CoreDNS)
```

- ⚠ « Kubernetes agit » → non : c'est le **contrôleur du Deployment** (lu : « You describe a desired state in a Deployment »).
- ⚠ « Le Service crée des enregistrements DNS » → non : c'est le **serveur DNS du cluster** qui en crée pour chaque Service (lu par moi, Ctrl+F `DNS records`).
- ⚠ « L'IP d'un Pod change à chaque redémarrage » → ce qui est lu : un Pod remplacé est un **nouveau** Pod, avec une autre adresse (« create and destroy Pods dynamically »). Ce qui se passe à un simple redémarrage : non lu.
- ⚠⚠ Viser l'IP d'un Pod (dans nginx, dans une liste écrite à la main) : après remplacement, plus personne n'écoute à cette adresse.
- ⚠⚠ Une faute dans le sélecteur (`app: back-end` contre `app: backend`) : les Pods tournent, le Service ne les voit pas.
- ⚠⚠ Exposer le backend en LoadBalancer : il devient joignable depuis Internet. Backend interne → ClusterIP.

## 2. Lab 164380 — mes commandes et mes sorties

Cluster **Autopilot** fourni par le lab (« Google manages the cluster infrastructure, including nodes, scaling, and security »).

| Commande (manuel) | Ma sortie | Ce que ça prouve |
|---|---|---|
| `kubectl create deployment nginx-server --image=nginx` | `created` · avertissement Autopilot « defaulted unspecified cpu » · **1 Pod** | sans `--replicas`, l'état voulu = 1 copie |
| `kubectl scale deployment nginx-server --replicas=5` | **4 Pods** à 48 s + le premier à 71 s | le contrôleur corrige l'écart, il ne recrée pas tout |
| `kubectl get pods` | `Pending` → `ContainerCreating` → `Running` · **2/5** Running à 87 s | « created » ≠ « tourne » |
| `kubectl expose deployment nginx-server --type=LoadBalancer --port=80 --target-port=80` | Service créé | nginx écoute sur 80 dans son conteneur |
| `kubectl get service nginx-server` | CLUSTER-IP `34.118.233.131` · EXTERNAL-IP `<pending>` puis `35.185.99.139` (< 49 s) · `80:30162/TCP` | deux adresses ; l'externe arrive après |
| `curl` vers l'EXTERNAL-IP | « Welcome to nginx! » | vérifier le **résultat**, pas le message |

⚠⚠ Labs Google Skills : encadré « Do not deviate from instructions… automatic account block » → **seulement les commandes du
manuel, dans l'ordre**. Aucune commande de lecture en plus (`get nodes`, `describe`…).

## 3. Mon backend sur GKE (application, non déployé)

- Deployment `backend` : 3 copies, label `app: backend`.
- Service `backend` de type **ClusterIP**, `port: 80`, `targetPort: 3000`. nginx vise `http://backend`.
- Frontend : Service **LoadBalancer**.
- Le développeur passe le backend sur 8080 → changer `targetPort` en 8080 (le `port` 80 ne bouge pas).
- Service supprimé, Deployment gardé → les Pods restent, mais `backend` ne mène plus nulle part.

## 4. Non lu (ne pas affirmer)

- Le `30162` de `80:30162/TCP` · pourquoi `Pending` sur Autopilot · le CPU « defaulted » · les *node pools* → **S6 J3 (lab 72688)**.
- La méthode de répartition du Service · l'adresse vers laquelle pointe le nom DNS · le terme « endpoint ».
- Le coût d'un LoadBalancer sur GKE · l'IP source vue par le Pod sur GKE.
