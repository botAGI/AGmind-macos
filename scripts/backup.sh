#!/bin/bash
# scripts/backup.sh -- AGMind backup script
# Invoked by LaunchAgent com.agmind.backup (daily at 03:00) or via `agmind backup`
# Compatible with /bin/bash 3.2.57 (stock macOS)
#
# Creates timestamped backup of:
#   - Docker volumes (postgres, redis, weaviate/qdrant data)
#   - Configuration files (.env, docker-compose.yml, nginx.conf, credentials.txt)
#
# Backup destination: ~/Library/Application Support/AGMind/backups/

set -euo pipefail

# =============================================================================
# Constants
# =============================================================================

AGMIND_DIR="${AGMIND_DIR:-/opt/agmind}"
BACKUP_BASE="${HOME}/Library/Application Support/AGMind/backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="${BACKUP_BASE}/agmind-backup-${TIMESTAMP}"
MAX_BACKUPS=7

# =============================================================================
# Logging (standalone -- does not depend on lib/common.sh)
# =============================================================================

_log() {
    printf "[%s] [%s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" "$2"
}

log_info()  { _log "INFO"  "$1"; }
log_warn()  { _log "WARN"  "$1"; }
log_error() { _log "ERROR" "$1"; }

# =============================================================================
# Preflight
# =============================================================================

if [ ! -d "$AGMIND_DIR" ]; then
    log_error "AGMind directory not found: ${AGMIND_DIR}"
    exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
    log_error "docker command not found -- is Docker installed?"
    exit 1
fi

# =============================================================================
# Create backup directory
# =============================================================================

mkdir -p "$BACKUP_DIR"
log_info "Starting backup to ${BACKUP_DIR}"

# =============================================================================
# Backup configuration files
# =============================================================================

log_info "Backing up configuration files..."
mkdir -p "${BACKUP_DIR}/config"

for file in .env docker-compose.yml nginx.conf credentials.txt versions.env; do
    if [ -f "${AGMIND_DIR}/${file}" ]; then
        cp "${AGMIND_DIR}/${file}" "${BACKUP_DIR}/config/"
    fi
done

# =============================================================================
# Backup Docker volumes
# =============================================================================

log_info "Backing up Docker volumes..."
mkdir -p "${BACKUP_DIR}/volumes"

# Get list of agmind-related volumes
volumes=$(docker volume ls --format '{{.Name}}' 2>/dev/null | grep -E "agmind|dify|weaviate|qdrant|postgres|redis" || true)

if [ -z "$volumes" ]; then
    log_warn "No AGMind-related Docker volumes found -- skipping volume backup"
else
    for vol in $volumes; do
        log_info "  Backing up volume: ${vol}"
        docker run --rm \
            -v "${vol}:/source:ro" \
            -v "${BACKUP_DIR}/volumes:/backup" \
            alpine:latest \
            tar czf "/backup/${vol}.tar.gz" -C /source . 2>/dev/null || {
                log_warn "  Failed to backup volume: ${vol}"
            }
    done
fi

# =============================================================================
# Create backup manifest
# =============================================================================

cat > "${BACKUP_DIR}/manifest.txt" <<MANIFEST
AGMind Backup
=============
Date: $(date)
Host: $(hostname)
AGMind Version: $(grep "AGMIND_VERSION" "${AGMIND_DIR}/.env" 2>/dev/null | cut -d= -f2 || echo "unknown")

Config files:
$(ls -la "${BACKUP_DIR}/config/" 2>/dev/null || echo "  (none)")

Volume archives:
$(ls -la "${BACKUP_DIR}/volumes/" 2>/dev/null || echo "  (none)")
MANIFEST

# =============================================================================
# Compress backup
# =============================================================================

log_info "Compressing backup..."
tar czf "${BACKUP_DIR}.tar.gz" -C "${BACKUP_BASE}" "agmind-backup-${TIMESTAMP}" 2>/dev/null
rm -rf "$BACKUP_DIR"

# =============================================================================
# Rotate old backups (keep MAX_BACKUPS most recent)
# =============================================================================

backup_count=$(ls -1 "${BACKUP_BASE}"/agmind-backup-*.tar.gz 2>/dev/null | wc -l | tr -d ' ')

if [ "$backup_count" -gt "$MAX_BACKUPS" ]; then
    log_info "Rotating old backups (keeping ${MAX_BACKUPS} most recent)..."
    ls -1t "${BACKUP_BASE}"/agmind-backup-*.tar.gz | tail -n +"$((MAX_BACKUPS + 1))" | while read -r old_backup; do
        rm -f "$old_backup"
        log_info "  Removed old backup: $(basename "$old_backup")"
    done
fi

# =============================================================================
# Done
# =============================================================================

final_size=$(du -sh "${BACKUP_DIR}.tar.gz" 2>/dev/null | awk '{print $1}')
log_info "Backup complete: ${BACKUP_DIR}.tar.gz (${final_size})"
