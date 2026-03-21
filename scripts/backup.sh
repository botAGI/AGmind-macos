#!/bin/bash
# scripts/backup.sh -- AGMind daily backup (called by LaunchAgent)
# Creates timestamped backups of /opt/agmind/ config files.
# Keeps the last 7 backups and prunes older ones.
# Compatible with /bin/bash 3.2.57 (stock macOS)

set -euo pipefail

AGMIND_DIR="${AGMIND_DIR:-/opt/agmind}"
BACKUP_BASE="${HOME}/Library/Application Support/AGMind/backups"

_ts() { date "+%Y-%m-%d_%H%M%S"; }

# Create backup directory
mkdir -p "$BACKUP_BASE"

# Create timestamped backup
BACKUP_DIR="${BACKUP_BASE}/agmind-$(_ts)"
mkdir -p "$BACKUP_DIR"

# Copy config files (ignore missing files gracefully)
cp "${AGMIND_DIR}/.env" "${BACKUP_DIR}/" 2>/dev/null || true
cp "${AGMIND_DIR}/credentials.txt" "${BACKUP_DIR}/" 2>/dev/null || true
cp "${AGMIND_DIR}/docker-compose.yml" "${BACKUP_DIR}/" 2>/dev/null || true
cp "${AGMIND_DIR}/nginx.conf" "${BACKUP_DIR}/" 2>/dev/null || true
cp "${AGMIND_DIR}/versions.env" "${BACKUP_DIR}/" 2>/dev/null || true

# Log result
mkdir -p "${AGMIND_DIR}/logs"
echo "[$(_ts)] Backup completed: ${BACKUP_DIR}" >> "${AGMIND_DIR}/logs/backup.log"

# Prune old backups (keep last 7)
count=$(ls -1d "${BACKUP_BASE}"/agmind-* 2>/dev/null | wc -l | tr -d ' ')
if [ "$count" -gt 7 ]; then
    ls -1d "${BACKUP_BASE}"/agmind-* | sort | head -n "$((count - 7))" | while read -r old; do
        rm -rf "$old"
    done
fi
