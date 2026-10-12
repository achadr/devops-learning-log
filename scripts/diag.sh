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
    echo "[AVERTISSEMENT] Ni root ni sudo disponible : les sections RESEAU et LOGS seront incomplètes." >&2
fi

main() {
    echo "Diagnostic systeme - $(hostname) - $(date '+%Y-%m-%d %H:%M:%S')" 

section " CHARGE "
uptime

section " MEMOIRE "
free -h

section " DISQUE "
df -hT -t ext4 -t xfs -t btrfs 2>/dev/null || echo "(aucun système de fichiers local détecté)"

section " RESEAU "
$SUDO ss -tulpn


section " INODES "
df -i -t ext4 -t xfs -t btrfs 2>/dev/null || echo "(aucun système de fichiers local détecté)"

section " PROCESSUS "
ps -eo pid,user,%cpu,%mem,cmd --sort=-%cpu | head

section " LOGS " 
journalctl -k -n 50 --no-pager
}


RAPPORT="${1:-}"

if [[ -n "$RAPPORT" ]]; then
    main | tee "$RAPPORT"
    echo "Rapport ecrit dans : $RAPPORT" >&2
else
    main
fi