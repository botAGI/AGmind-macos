#!/bin/bash
# scripts/health-gen.sh -- AGMind health check (called by LaunchAgent)
# Checks Docker container status and Ollama API availability.
# Results are appended to the health log file.
# Compatible with /bin/bash 3.2.57 (stock macOS)

set -euo pipefail

AGMIND_DIR="${AGMIND_DIR:-/opt/agmind}"
LOG_FILE="${AGMIND_DIR}/logs/health.log"

# Ensure log directory exists
mkdir -p "${AGMIND_DIR}/logs"

_ts() { date "+%Y-%m-%d %H:%M:%S"; }

# =============================================================================
# Check Docker containers
# =============================================================================
_check_containers() {
    local compose_file="${AGMIND_DIR}/docker-compose.yml"
    if [ ! -f "$compose_file" ]; then
        echo "[$(_ts)] [FAIL] docker-compose.yml not found" >> "$LOG_FILE"
        return 0
    fi

    local exited
    exited=$(cd "$AGMIND_DIR" && docker compose ps --status exited -q 2>/dev/null | wc -l | tr -d ' ') || true
    if [ "$exited" -gt 0 ]; then
        echo "[$(_ts)] [WARN] ${exited} containers exited" >> "$LOG_FILE"
    else
        echo "[$(_ts)] [PASS] All containers running" >> "$LOG_FILE"
    fi
}

# =============================================================================
# Check Ollama API
# =============================================================================
_check_ollama() {
    if curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
        echo "[$(_ts)] [PASS] Ollama API responding" >> "$LOG_FILE"
    else
        echo "[$(_ts)] [FAIL] Ollama API not responding" >> "$LOG_FILE"
    fi
}

_check_containers
_check_ollama
