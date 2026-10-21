# Bash robuste — cheatsheet

> Jour 4 — Semaine 1. Écrire des scripts qui échouent bruyamment plutôt que silencieusement.

---

## 1. L'en-tête obligatoire

```bash
#!/usr/bin/env bash
set -Eeuo pipefail
```

### Le shebang

`#!` suivi du chemin de l'interpréteur, **sur la première ligne, colonne 1**. Le noyau le lit pour savoir quel programme doit exécuter le fichier.

| Forme | Quand |
|---|---|
| `#!/usr/bin/env bash` | **à préférer** — cherche `bash` dans le `$PATH` |
| `#!/bin/bash` | chemin fixe, casse sur les systèmes où bash est ailleurs (BSD, macOS avec Homebrew) |
| `#!/bin/sh` | shell POSIX minimal — pas de tableaux, pas de `[[ ]]`, pas de `pipefail` garanti |

**Piège** : un script avec des fins de ligne Windows (`\r\n`) fait chercher au noyau un interpréteur nommé `bash\r`, qui n'existe pas. Le message est `No such file or directory` **à propos de l'interpréteur**, pas du script.

```bash
file script.sh                  # dit "with CRLF line terminators" si c'est le cas
dos2unix script.sh              # répare
sed -i 's/\r$//' script.sh      # répare sans dos2unix
```

### Les quatre options

| Option | Nom long | Effet |
|---|---|---|
| `-e` | `errexit` | arrête le script dès qu'une commande renvoie un code non nul |
| `-u` | `nounset` | erreur si on lit une variable **non définie** |
| `-o pipefail` | — | un pipeline renvoie le code du dernier élément **en échec** |
| `-E` | `errtrace` | propage le `trap ERR` dans les fonctions et sous-shells |

**`-E` est obligatoire dès qu'il y a une fonction.** Sans lui, une erreur dans une fonction ne déclenche pas le trap.

**Ne jamais taper `set -e` dans un shell interactif** : la moindre commande en échec (un `grep` sans résultat) ferme la session.

```bash
set +e            # désactive errexit
set +u            # désactive nounset
set +o pipefail   # désactive pipefail
```

---

## 2. Pourquoi `pipefail`

Par défaut, le code de retour d'un pipeline est celui de la **dernière** commande. Les échecs en amont sont écrasés.

```bash
bash -c 'cat /inexistant | wc -l; echo $?'                    # → 0   ← faux
bash -c 'set -o pipefail; cat /inexistant | wc -l; echo $?'   # → 1   ← juste
```

Le danger réel n'est pas le crash, c'est le **résultat faux livré en silence** :

```bash
curl -s https://api/stock | jq '.total' > rapport.txt
# curl échoue → jq reçoit du vide → écrit null → code 0 → le script continue
```

---

## 3. `grep` renvoie 1 quand il ne trouve rien

Ce n'est pas une erreur, c'est son contrat : `0` = trouvé, `1` = rien trouvé, `2` = vraie erreur.

```bash
set -euo pipefail
journalctl -u velocite | grep "CRITICAL"   # aucun résultat → script mort ici
```

Deux parades, selon l'intention :

```bash
# "peu importe s'il ne trouve rien"
journalctl -u velocite | grep "CRITICAL" || true

# "j'agis différemment selon le résultat"
if journalctl -u velocite | grep -q "CRITICAL"; then
    echo "incident"
else
    echo "rien"
fi
```

**`if` et `while` désactivent temporairement `errexit`** pour la commande testée. C'est le mécanisme officiel pour dire « ici, un code non nul est une information ».

---

## 4. Variables : non définie ≠ vide

`set -u` n'attrape que les variables **non définies**. Une variable définie mais vide passe.

```bash
bash -c 'set -u; echo "[$INEXISTANTE]"'      # → erreur
bash -c 'set -u; V=""; echo "[$V]"'          # → passe, affiche []
```

### L'incident Steam (2015)

`steam.sh` contenait :

```bash
STEAMROOT="$(cd "${0%/*}" && echo $PWD)"
rm -rf "$STEAMROOT/"*
```

Si l'utilisateur déplaçait son dossier Steam, le `cd` échouait, `&&` court-circuitait, la substitution renvoyait une chaîne **vide**, et la commande devenait `rm -rf "/"*`. Effacement du `$HOME` et des disques externes montés, avec les droits de l'utilisateur.

`set -u` n'aurait pas suffi : la variable était définie, mais vide.

### Les expansions de protection

| Forme | Effet |
|---|---|
| `${VAR:?message}` | **avorte** avec le message si vide ou non définie |
| `${VAR:-défaut}` | valeur de repli si vide ou non définie |
| `${VAR-défaut}` | valeur de repli seulement si **non définie** |
| `${VAR:=défaut}` | assigne le défaut à la variable au passage |

Le `:` étend le contrôle au cas « vide ».

```bash
rm -rf "${CIBLE:?CIBLE vide, abandon}/"*       # la parade Steam
```

### Les règles

| Situation | Protection |
|---|---|
| lire une variable qui doit exister | `set -u` en tête |
| variable vide = catastrophe (chemin dans `rm`, `chown`, `mv`) | `"${VAR:?}"` au point d'usage |
| variable optionnelle | `"${VAR:-défaut}"` |
| chemin dans une commande destructrice | les deux, plus un `[[ -d "$VAR" ]]` |

### Argument optionnel

```bash
RAPPORT="${1:-}"                   # $1 ou chaîne vide — sans ça, set -u tue le script
if [[ -n "$RAPPORT" ]]; then ...   # -n = non vide
```

| Test | Vrai si |
|---|---|
| `-n "$V"` | la chaîne est non vide |
| `-z "$V"` | la chaîne est vide |
| `-f fichier` | existe et est un fichier régulier |
| `-d dossier` | existe et est un répertoire |
| `-x fichier` | est exécutable |

---

## 5. `trap` — savoir où ça casse

```bash
trap 'echo "[ERREUR] ligne $LINENO : code $?" >&2' ERR
```

- **guillemets simples obligatoires** : `$LINENO` doit être évalué au déclenchement, pas à l'installation
- `>&2` envoie sur stderr, pour ne pas polluer la sortie utile
- nécessite `set -E` si le code est dans des fonctions

Signaux utiles :

| Signal | Déclenché par |
|---|---|
| `ERR` | une commande en échec (même condition que `set -e`) |
| `EXIT` | la fin du script, quelle qu'en soit la cause — **le nettoyage va là** |
| `INT` | `Ctrl+C` |
| `TERM` | `kill`, ou `systemctl stop` |

```bash
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT      # le temporaire disparaît même en cas de crash
```

---

## 6. Fonctions

```bash
section() {
    echo
    echo "=============================="
    echo "  $1"
    echo "=============================="
}

section "CHARGE"
```

- `$1`, `$2`… sont les arguments **de la fonction**, pas du script
- `$#` le nombre d'arguments, `"$@"` tous les arguments
- une variable est globale par défaut → utiliser `local` dans une fonction
- **définir ≠ exécuter** : `main() { … }` ne fait rien tant qu'on n'écrit pas `main`

### Le motif `main`

```bash
main() {
    # tout le corps
}

RAPPORT="${1:-}"
if [[ -n "$RAPPORT" ]]; then
    main | tee "$RAPPORT"
else
    main
fi
```

Ce qui est **dans** `main` traverse le `tee` ; ce qui est au-dessus part directement au terminal.

---

## 7. Détecter ses privilèges

```bash
if [[ $EUID -eq 0 ]]; then
    SUDO=""
elif command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
else
    SUDO=""
    echo "[AVERTISSEMENT] ni root ni sudo : sections incomplètes." >&2
fi

$SUDO ss -tulpn
```

- `$EUID` = *effective user ID*, maintenu par bash. `0` = root. On teste l'UID, pas le nom.
- `command -v outil` teste la présence d'une commande — **pas `which`**, dont le code de retour varie
- **`$SUDO` sans guillemets** : avec `"$SUDO"` et une valeur vide, bash tenterait d'exécuter une commande nommée `""`. Sans guillemets, la variable vide disparaît de la ligne.

### Pourquoi c'est vital

`ss -tulpn` sans privilèges affiche les ports mais **laisse la colonne `Process` vide**, sans erreur ni avertissement. On lit « aucun processus sur le port 3000 », on conclut que le service est mort, on redémarre pour rien.

**Un script de diagnostic doit savoir quand il est aveugle, et le dire.**

---

## 8. `printf` — formater

```bash
printf "%-5s %7d %6.2f%%\n" "200" 43554 86.60
```

```
%  -   6   .2   f
│  │   │    │   └─ type
│  │   │    └──── précision (décimales)
│  │   └───────── largeur minimale
│  └───────────── aligner à gauche
└──────────────── début de marqueur
```

| Type | Pour |
|---|---|
| `%s` | chaîne |
| `%d` | entier |
| `%f` | flottant (6 décimales par défaut) |
| `%%` | un `%` littéral |

- les largeurs sont des **minimums**, jamais des troncatures
- dans `%6.2f`, le 6 est la largeur **totale** (point et décimales inclus)
- **convention** : chaînes à gauche (`%-Ns`), nombres à droite (`%Nd`) — les unités alignées rendent les ordres de grandeur lisibles
- `printf` n'ajoute **pas** de retour à la ligne : `\n` est obligatoire

Référence : `man 3 printf`. Format identique en C, Python, Java, Go, awk.

---

## 9. Sortie : stdout vs stderr

| Descripteur | Usage |
|---|---|
| `1` — stdout | la **donnée** produite par le script |
| `2` — stderr | les messages destinés à l'humain : erreurs, avertissements, progression |

```bash
echo "donnée"              # stdout
echo "avertissement" >&2   # stderr
commande 2>/dev/null       # jeter les erreurs
commande >/dev/null 2>&1   # tout jeter (ne garder que le code de retour)
```

**Règle** : si la sortie du script doit être consommée par un autre programme, tout ce qui n'est pas la donnée part sur stderr.

---

## 10. Les outils changent de format selon la destination

Beaucoup d'outils détectent si leur sortie est un terminal ou un tuyau :

| Outil | Vers un terminal | Vers un tuyau |
|---|---|---|
| `ss` | colonnes alignées sur la largeur de fenêtre | compactées, parfois collées |
| `ls` | colonnes, couleurs | une entrée par ligne, sans couleur |
| `git log` | appelle le pager | sortie brute |
| `journalctl` | appelle le pager | sortie brute (d'où `--no-pager`) |

**Conséquence** : la sortie que tu vois n'est pas forcément celle que ton script reçoit. En production, ne parse jamais du texte formaté pour l'humain quand un format machine existe — `journalctl -o json`, `ps -o champs`, `kubectl -o jsonpath`.

---

## 11. Séparer la donnée de la prose

```bash
# mauvais — les mots de liaison deviennent des colonnes
503 a 536 requettes soit 1.07% du total
#  $1 $2 $3    $4     $5   $6      $7 $8   → il faut trier sur -k3

# bon — une colonne, une valeur
503      536   1.07
#  $1      $2     $3                        → sort -k2 -rn
```

Les unités vont dans l'en-tête, pas dans les cellules : `6.60%` n'est plus un nombre pour `sort -n`.

L'en-tête ne doit pas traverser le `sort` :

```bash
{ printf "%-5s %7s %7s\n" "CODE" "NB" "PART%"; awk '…' fichier | sort -k2 -rn; }
```

---

## 12. Le script du jour

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo "[ERREUR] ligne $LINENO : code de sortie $?" >&2' ERR

section() {
    echo
    echo "=============================="
    echo "  $1"
    echo "=============================="
}

if [[ $EUID -eq 0 ]]; then
    SUDO=""
elif command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
else
    SUDO=""
    echo "[AVERTISSEMENT] Ni root ni sudo : sections RESEAU et LOGS incomplètes." >&2
fi

main() {
    echo "Diagnostic systeme - $(hostname) - $(date '+%Y-%m-%d %H:%M:%S')"

    section "CHARGE"
    uptime

    section "MEMOIRE"
    free -h

    section "DISQUE"
    df -hT -t ext4 -t xfs -t btrfs 2>/dev/null || echo "(aucun systeme de fichiers local detecte)"

    section "INODES"
    df -i -t ext4 -t xfs -t btrfs 2>/dev/null || echo "(aucun systeme de fichiers local detecte)"

    section "RESEAU"
    $SUDO ss -tulpn

    section "PROCESSUS"
    ps -eo pid,user,%cpu,%mem,cmd --sort=-%cpu | head -n 11

    section "LOGS"
    $SUDO journalctl -k -n 30 --no-pager
}

RAPPORT="${1:-}"

if [[ -n "$RAPPORT" ]]; then
    main | tee "$RAPPORT"
    echo "Rapport ecrit dans : $RAPPORT" >&2
else
    main
fi
```

### Deux décisions à retenir

**Liste blanche plutôt que liste noire** pour `df`. `-t ext4 -t xfs -t btrfs` nomme les systèmes de fichiers qui peuvent réellement se remplir, au lieu d'énumérer le bruit à exclure (`tmpfs`, `overlay`, `9p`, `rootfs`, et tous ceux qui apparaîtront demain). Même principe qu'un groupe de sécurité réseau.

**Le `|| echo` n'est pas décoratif.** Si aucun de ces types n'existe — cas courant dans un conteneur Docker où `/` est un `overlay` — GNU `df` sort avec le code 1 et `set -e` tue le script. Le `|| echo` transforme « rien trouvé » en information.

---

## 13. Exécution

```bash
chmod +x scripts/diag.sh
./scripts/diag.sh                       # le ./ est obligatoire
bash scripts/diag.sh                    # alternative, ignore le bit x
./scripts/diag.sh /tmp/rapport.txt      # avec argument
```

Le `./` est nécessaire parce que **`.` n'est pas dans le `$PATH`** — décision de sécurité délibérée. Si le répertoire courant y était, déposer un fichier nommé `ls` dans un dossier partagé suffirait à faire exécuter du code arbitraire à la prochaine personne qui y entre.

Rappel : `code fichier`, `touch fichier`, `nano fichier` résolvent le nom **par rapport au répertoire courant**. Le `pwd` est l'état invisible qui décide de tout.

---

## 14. Discipline de test

```bash
# tester une option set SANS risquer sa session
bash -c 'set -euo pipefail; …'      # sous-processus, options isolées
( set -euo pipefail; … )            # sous-shell, options isolées
```

Avant d'agréger, vérifier le filtre :

```bash
awk '$9==500' fichier | head -n 3      # mon filtre attrape-t-il les bonnes lignes ?
awk '$9==500' fichier | wc -l          # combien ?
```

Un filtre faux qui compte parfaitement donne un chiffre faux avec l'air d'être juste.

Avant tout `-i` ou toute commande destructrice :

```bash
commande fichier | head -n 20        # 1. je regarde
commande -i.bak fichier              # 2. j'applique avec sauvegarde
diff fichier.bak fichier             # 3. je vérifie
```
