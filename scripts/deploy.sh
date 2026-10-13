#!/usr/bin/env bash
set -Eeuo pipefail

trap 'echo "[ERREUR] ligne $LINENO : code de sortie $?" >&2' ERR

SOURCE="$HOME/labs/velocite-build/server.js"
CIBLE="/opt/velocite/server.js"
NODE_BIN="/usr/bin/node"

# --- verrou : un seul deploiement a la fois ---
VERROU="/tmp/velocite-deploy.lock"
exec 9>"$VERROU"
if ! flock -n 9; then
    echo "[ERREUR] Un deploiement est deja en cours." >&2
    exit 1
fi

# --- confirmation en production ---
ENVIRONNEMENT="${ENVIRONNEMENT:-dev}"
AUTO_OUI=0
if [[ "${1:-}" == "--yes" ]]; then
    AUTO_OUI=1
fi

if [[ "$ENVIRONNEMENT" == "prod" && "$AUTO_OUI" -ne 1 ]]; then
    if [[ ! -t 0 ]]; then
        echo "[ERREUR] Deploiement en prod sans terminal et sans --yes. Abandon." >&2
        exit 1
    fi
    read -r -p "Deploiement en PRODUCTION. Tape 'velocite-prod' pour confirmer : " reponse
    if [[ "$reponse" != "velocite-prod" ]]; then
        echo "Confirmation incorrecte, deploiement annule." >&2
        exit 1
    fi
fi

# 1. la source existe-t-elle ?
if [[ ! -f "$SOURCE" ]]; then
    echo "[ERREUR] Source introuvable : $SOURCE" >&2
    exit 1
fi

# 2. le code est-il valide ?
if ! "$NODE_BIN" --check "$SOURCE"; then
    echo "[ERREUR] Code JavaScript invalide, deploiement annule." >&2
    exit 1
fi

# 3. y a-t-il quelque chose a deployer ?
if sudo cmp -s "$SOURCE" "$CIBLE"; then
    echo "Aucun changement, rien a deployer."
    exit 0
fi

echo "Changement detecte, deploiement en cours."

# 4. sauvegarde horodatee
HORODATAGE=$(date '+%Y%m%d-%H%M%S')
SAUVEGARDES="/var/backups/velocite"
sudo install -d -m 0750 -o root -g root "$SAUVEGARDES"
SAUVEGARDE="${SAUVEGARDES}/server.js.${HORODATAGE}"
sudo cp -p "$CIBLE" "$SAUVEGARDE"
echo "Sauvegarde : $SAUVEGARDE"

# 5. installation du nouveau fichier
sudo install -m 0644 -o root -g root "$SOURCE" "$CIBLE"
echo "Fichier installe."

# 6. redemarrage du service
sudo systemctl restart velocite
echo "Service redemarre."
# 7. verification de sante
echo "Verification de la sante du service..."
SANTE_OK=0
for i in 1 2 3 4 5; do
    sleep 1
    if curl -fsS --max-time 3 http://localhost:3000/health >/dev/null 2>&1; then
        SANTE_OK=1
        echo "Service sain apres ${i}s."
        break
    fi
done

# 8. retour arriere si la sante n'est pas confirmee
if [[ "$SANTE_OK" -ne 1 ]]; then
    echo "[ERREUR] Service non sain apres 5 tentatives. Retour arriere." >&2
    sudo install -m 0644 -o root -g root "$SAUVEGARDE" "$CIBLE"
    sudo systemctl restart velocite
    echo "[INFO] Version precedente restauree." >&2
    exit 1
fi

echo "Deploiement reussi."
