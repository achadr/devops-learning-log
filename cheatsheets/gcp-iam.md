# GCP — IAM : membres, rôles, moindre privilège, refus par défaut

> Fiche du 26/10 (semaine 3, jour 2), écrite après le QCM du 27/10 (20/20).
> ⚠ = raté oral réel du 26/10. Tous les constats viennent de ma console, projet `week3-sandbox`.

---

## Les paires à ne pas inverser

⚠ **Personne et programme** (oral : « le prestataire = un compte de service ») :

| Membre (*principal*) | Représente | Exemple |
|---|---|---|
| **Compte Google** | **une personne** | le prestataire, moi |
| **Groupe Google** | un ensemble de personnes | `equipe-dev@…` |
| **Compte de service** | **un programme** | `logs-reader@week3-sandbox.iam.gserviceaccount.com` |
| **Domaine** | tous les comptes d'une organisation | `entreprise.fr` |

> Un programme en production n'utilise **jamais** le compte d'une personne : s'il est compromis,
> il donne tous ses droits ; si la personne part, son compte est désactivé et le programme tombe.

| | **De base** | **Prédéfini** | **Personnalisé** |
|---|---|---|---|
| Exemples | `Propriétaire`, `Éditeur`, `Lecteur` | `roles/logging.viewer`, `roles/secretmanager.secretAccessor`, `roles/compute.viewer` | celui que je crée |
| Portée | **tous** les services du projet | un service, une tâche | exactement les permissions choisies |
| Maintenu par | Google | Google | **moi** |
| Usage | ⚠ à éviter en production | **par défaut** | quand aucun prédéfini n'est assez étroit |

⚠ Réflexe (oral : « je choisis le rôle personnalisé ») : **chercher d'abord un prédéfini.**
⚠ `Lecteur` ne lit pas le contenu des bases : il lit **la configuration de tout le projet**.

⚠ **Pas d'autorisation et règle de refus** (oral : « il faut une règle de refus pour la facturation ») :

| | **Pas d'autorisation** | **Règle de refus** |
|---|---|---|
| Ce que c'est | l'état par défaut : rien n'a été donné | une interdiction écrite exprès |
| Étape dans l'outil de dépannage | **Autoriser** : « interdit l'accès » | **Refuser** |
| Sert à | presque tous les « ne jamais » | bloquer un droit **hérité** d'un niveau supérieur |

| Ce qui décide | Question |
|---|---|
| le **rôle** | **QUOI** : quelles permissions |
| le **lieu** où on le pose | **OÙ** : projet, ou une seule ressource (un secret, un bucket) |
| le **membre** | **QUI** |

> Le même rôle posé sur le projet ou sur un seul secret ne donne pas le même accès.

---

## 1. Refus par défaut — mesuré

> **Une identité n'a que les permissions qu'on lui a explicitement données.**

```
création de logs-reader, sans rôle      → existe, mais n'apparaît PAS dans la page IAM
                                          (la page liste les AUTORISATIONS, il n'en a aucune)
rôle « Lecteur de journaux » ajouté      → apparaît, avec ce rôle
```

Un rôle = un **ensemble de permissions**. Unité élémentaire : la permission (`logging.logEntries.list`).

## 2. Vérifier le résultat : l'outil de dépannage des stratégies

Voir le rôle dans la liste = vérifier **la configuration**. L'outil vérifie **ce que l'identité peut faire**.
Il fonctionne **sans compte de facturation**.

```
logs-reader · logging.logEntries.list          → Accès autorisé
logs-reader · resourcemanager.projects.delete  → Accès impossible, à l'étape « Autoriser »
```

Ordre d'évaluation (⚠ oral : « bloqué à la limite d'accès ») :

```
Limite d'accès des principaux  →  Refuser  →  Autoriser  →  Résultat
```

Les refus passent **avant** les autorisations : c'est pour ça qu'un refus bloque un droit hérité.

## 3. Le compte de service est aussi une ressource

On peut donner à une personne le droit d'**agir en tant que** compte de service.
Conséquence : elle obtient **ses** permissions. C'est un droit puissant, à donner avec le même soin.

## 4. Le moindre privilège — LAB-06

Contrainte : aucun rôle `Propriétaire` ou `Éditeur`.

| Besoin | Qui | Rôle | Où |
|---|---|---|---|
| déployer en dev | groupe des développeurs | déploiement | projet `app-dev` |
| lire les journaux de prod | groupe des développeurs | `roles/logging.viewer` | projet `app-prod` |
| ne jamais modifier la prod | — | **rien à donner** | — |
| ne jamais voir la facturation | — | **rien à donner** (la facturation vit dans le compte de facturation) | — |
| prestataire : déposer des fichiers | **son compte Google** | création d'objets | **le bucket** |

⚠ Avec mon compte personnel : pas d'organisation, donc pas de dossiers ni de groupes rattachés à
une organisation. La partie « bucket » se fait sur papier : Cloud Storage exige la facturation.
