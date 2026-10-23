# GCP — fondations : modèles de service, régions, hiérarchie, facturation

> Fiche du 23/10 (semaine 3, jour 1).
> ⚠ = raté réel du jour · ⚠⚠ = erreur à coût réel. Les constats viennent de ma console.

---

## Les paires à ne pas inverser

⚠ **Le noyau** (QCM Q2 raté : « Google, puisque le noyau fait partie de l'infrastructure ») :

| | Conteneur | Machine virtuelle |
|---|---|---|
| Noyau | **celui de l'hôte**, partagé | **le sien** : l'OS invité installé dans la VM |
| Sur GCP, qui le met à jour | Google, pour les machines qui exécutent Cloud Run | **moi**, sur Compute Engine |

> Une VM a deux noyaux : celui de l'hyperviseur (Google) et celui de l'OS invité (**moi**).
> Ne pas recycler « le conteneur partage le noyau de l'hôte » sur une VM : c'est l'inverse.

| | **Zone** | **Région** |
|---|---|---|
| Ce que c'est | un domaine de panne isolé (bâtiments, énergie, réseau) | un groupe de zones dans la même zone géographique |
| Exemple | `europe-west1-b` | `europe-west1` (Belgique) · `europe-west9` (Paris) |
| Protège contre | la perte d'un centre de données | la perte d'une région entière |
| Usage | **haute disponibilité** | **reprise après sinistre** |

⚠ **Groupe et dossier** (oral : « ajouter les projets dans le groupe dev ») :

| | **Groupe** | **Dossier** |
|---|---|---|
| Contient | des **personnes** (ou comptes de service) | des **projets** (ou d'autres dossiers) |
| Répond à | **qui** reçoit le droit | **où** le droit s'applique |

| | **Projet** | **Compte de facturation** |
|---|---|---|
| Ce que c'est | le conteneur des ressources, API et droits | **qui paie** |
| Relation | lié à **zéro ou un** compte | peut payer pour **plusieurs** projets |
| Mon cas | `pfe-hti-2018` existe toujours | `014993-…` **clôturé** |

| | **Quota** | **Budget** |
|---|---|---|
| Ce que c'est | une **limite technique** | un **montant** suivi dans le temps |
| Vu chez moi | « Il vous reste 21 projets dans votre quota » | — |
| Quand on l'atteint | la création **échoue** | une **alerte**, et la consommation **continue** |

⚠⚠ **Le plafond de dépenses** (QCM Q11 raté : « les VM sont arrêtées immédiatement ») :

| | Budget « alertes » | Budget avec **plafond** (*spend cap*, en préversion) |
|---|---|---|
| Effet | e-mails aux seuils | met en pause **certains services éligibles**, par projet |
| Sur Compute Engine et le stockage | rien | ⚠⚠ **rien non plus** : les ressources persistantes continuent de tourner et d'être facturées |
| Application | — | pas instantanée : les dépassements sont facturés |

> Pour des VM, un budget reste **une alerte, pas un plafond**.

---

## 1. Les modèles de service et la responsabilité partagée

| | Modèle | Je loue… | Toujours à moi |
|---|---|---|---|
| Compute Engine | **IaaS** | une machine | OS invité et noyau, runtime, code, **données, accès** |
| Cloud Run | **PaaS** | une plateforme qui exécute mon image | l'image **entière** (Debian compris), code, **données, accès** |
| logiciel fini | **SaaS** | un logiciel | **données, accès** |

> Plus on monte vers le SaaS, plus le fournisseur prend en charge.
> **Les données et les accès restent toujours à moi.**

Sur Cloud Run, une faille dans une bibliothèque Debian de `node:24-slim` = **à moi** de
reconstruire l'image, la pousser, redéployer. Google ne touche pas à mon image.

---

## 2. Régions et zones

Répliquer entre la Belgique et les États-Unis coûte trois choses :

```
latence ENTRE mes deux sites   chaque écriture traverse l'Atlantique  ⚠ pas seulement pour l'utilisateur
transfert inter-régions        facturé
RGPD                           des données hébergées hors de l'UE
```

---

## 3. La hiérarchie des ressources

```
Organisation          ← la racine : n'existe que pour un domaine (Workspace ou Cloud Identity)
   └── Dossier         ← son parent : une organisation ou un autre dossier
         └── Projet    ← unité de base : ressources, API activées, facturation
               └── Ressources
```

- Les droits **s'héritent** vers le bas et **s'additionnent** : l'absence d'autorisation sur un
  projet ne retire rien. Seule une **stratégie de refus** (onglet « Refuser ») bloque un droit hérité.
- Bonne pratique : le rôle au **groupe**, sur le **dossier** → les futurs projets héritent seuls.
- Rôle de lecture des journaux : `roles/logging.viewer`.

⚠ **Avec un compte Google personnel : « Aucune organisation » → aucun dossier possible.**
Seulement des projets isolés, à la racine. (oral : « oui, au niveau de l'organisation »)

**L'ID d'un projet est définitif** ; seul le nom affiché peut changer.

Rôles de base : `Propriétaire` (*Owner*), `Éditeur`, `Lecteur`. Je suis `Propriétaire` de
`week3-sandbox`. En entreprise, on leur préfère des **rôles prédéfinis**, plus étroits.

---

## 4. Facturation et API — mesuré sur ma console

```
projet sans facturation   ✅ créé            week3-sandbox, aucun champ « facturation »
IAM                       ✅ utilisable       je suis Propriétaire
dossiers                  ✗ impossible       pas d'organisation
Compute Engine            ✗ « Facturation obligatoire » : l'API exige un compte de facturation lié au projet
```

**Chaque service est une API à activer, projet par projet** (`compute.googleapis.com`).

---

## 5. Ma situation gratuite — vérifiée dans la documentation le 23/10

| | Condition | Moi |
|---|---|---|
| **Essai gratuit** (300 $, 90 jours) | jamais payant · jamais inscrit à l'essai | ✗ utilisé de 12/2018 à 12/2019 |
| **Free Tier** (`e2-micro` dans 3 régions US, Cloud Run, Cloud Shell…) | un compte de facturation **actif et en règle** | ✗ compte clôturé |
| **Labs Google Skills** (offre Starter, 35 crédits par mois) | compte Google + profil développeur | ⏳ bloqué par la vérification reCAPTCHA |

> Les labs donnent un **projet temporaire** : aucun risque pour ma facturation.
> À essayer : adhérer au **Google Developer Program** depuis la page d'accueil de la console.

⚠ Ne pas ouvrir un autre compte Google pour obtenir un nouvel essai : ce serait contourner les
conditions d'éligibilité.

Sources : [Free Google Cloud features and trial offer](https://docs.cloud.google.com/free/docs/free-cloud-features) ·
[Manage spend cap budgets](https://docs.cloud.google.com/billing/docs/how-to/budgets-spend-caps) ·
[Google Skills — abonnements](https://support.google.com/qwiklabs/answer/9139481?hl=en)
