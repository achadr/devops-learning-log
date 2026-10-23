# Semaine 2 — la liste de trous

> Établie le 23/10, à partir de mon auto-évaluation (0 à 2) **confrontée aux mesures** :
> QCM, ratés, reprise espacée. Un trou n'est fermé que par un **cas inédit réussi sans fiche**.

## Le principe

```
auto-évaluation  ≠  mesure
un 2 ne compte que s'il tient sur un cas que je n'ai jamais vu, sans notes
```

Deux sujets sur lesquels je me suis noté 2 ont les mesures les plus fragiles (A et D) :
ils sont **à vérifier**, pas acquis.

---

## Les trous, par priorité

| Priorité | Trou | Moi | Preuve | Action | Quand | Fermé quand |
|---|---|---|---|---|---|---|
| **1** | **SSH avec bastion** (`ProxyJump`) | 0 | jamais pratiqué | lab local : 2 conteneurs `sshd`, un bastion, une cible non exposée | S3 J6 (révision) | je joins la cible via le bastion, avec `~/.ssh/config`, sans aide |
| **2** | **Arrêt du conteneur en < 2 s** | 1 | 3 Ctrl+C le 22/10 | PID 1 et `SIGTERM` | **23/10** | `time docker compose stop backend` < 2 s |
| **3** | **DNS** | 1 | QCM 19/10 : **56 %**, le plus bas | lab « casser et réparer » (résolveur injoignable, `/etc/hosts` parasite, `search`) | devoir + S3 J6 | les 3 pannes diagnostiquées **dans l'ordre**, sans fiche |
| **4** | **CIDR** — à vérifier | 2 | 2 recyclages d'adresses le 16/10 | **LAB-05** : découper `10.50.0.0/16` pour prod, staging, dev, management (app + base + 100 % de marge) | devoir avant S4 J1 | tableau complet, juste, fait de tête · **réutilisé tel quel pour le VPC en S4** |
| **5** | **Image < 200 Mo** | 1 | backend **985 MB / 252 MB** | revoir l'image de base après la migration PostgreSQL (le binaire natif de `@libsql` exige glibc) | S4, avec PostgreSQL | mesuré par `docker images` |
| **6** | **TLS** — à vérifier | 2 | items 4 et 6 ratés le 20/10, réussis depuis | un cas inédit sur la chaîne de confiance | S3 J6 | réponse juste sans fiche |
| **7** | **Docker sans modèle** | 1 | vocabulaire du `Dockerfile` demandé le 22/10 | réécrire `Dockerfile` + `compose.yaml` **de zéro, sans notes** | S3 J6 | la pile remonte, données comprises |
| **8** | **HTTP brut** | 1 | ligne vide ratée 3 fois · 308 avec indice | reprise espacée | **27/10** (J+7) | item réussi à J+7 |
| **9** | **Pare-feu à état** | 1 | item 9 raté 2 fois, réenseigné le 23/10 | reprise espacée | **28/10** (J+7) | item réussi à J+7 |
| **10** | **Diagnostic par couches** | 1 | item 2 raté 3 fois, réenseigné le 23/10 | reprise espacée | **27/10** (J+7) | item réussi à J+7 |

---

## Les pièges récurrents de la semaine

```
inverser les deux éléments d'une paire          /api/tasks ↔ /tasks · fin de requête ↔ fin de connexion
recycler un mécanisme hors de son contexte      « étiquette réseau » invoquée 3 fois pour des cas sans rapport
faire confiance à un instantané                 origin/main · volume nommé · nginx qui résout au démarrage
faire confiance au message plutôt qu'à l'effet  « All migrations have been successfully applied »
```

Les deux questions à me poser :

> *Est-ce que ce mécanisme parle bien de ce qu'on me demande ?*
> *Ce que je regarde est-il frais, ou mémorisé ?*

---

## Devoirs en retard

- [ ] **LAB-05** — découpage de `10.50.0.0/16` (trou 4)
- [ ] **Lab DNS « casser et réparer »** (trou 3)
- [ ] **LAB-02**, saturations 3, 4, 5 (disque, inodes, fichier supprimé mais ouvert)
- [ ] commiter `cheatsheets/ssh-firewall.md`
- [ ] ajouter à `cidr.md` : « diffusion » est relative à un préfixe (`192.168.1.255` : diffusion en `/24`, ordinaire en `/16`)
- [ ] écrire au support de Google Skills (vérification reCAPTCHA par code, services Google Play 26.41.31)
