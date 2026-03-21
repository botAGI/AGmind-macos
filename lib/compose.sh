#!/bin/bash
# lib/compose.sh -- AGMind Docker Compose orchestration
# Sourced by install.sh for Phase 6 (Start)
# Compatible with /bin/bash 3.2.57 (stock macOS)
#
# Provides: Docker Compose start with idempotent skip
# Exports: phase_6_start
#
# Depends on: lib/common.sh (log_info, die, AGMIND_DIR)
#             lib/openwebui.sh (_inject_admin_credentials)

set -eEuo pipefail

# =============================================================================
# Docker Compose Start (idempotent)
# =============================================================================
# Starts the Docker Compose stack from /opt/agmind/ so .env is auto-loaded.
# Skips if containers are already running (idempotent for re-runs).

_start_compose() {
    local compose_file="${AGMIND_DIR}/docker-compose.yml"

    if [ ! -f "$compose_file" ]; then
        die "docker-compose.yml not found at ${compose_file}" \
            "Run Phase 5 (Configuration) first"
    fi

    # Idempotent: skip if containers already running
    local running
    running=$(cd "$AGMIND_DIR" && docker compose ps --status running -q 2>/dev/null | wc -l | tr -d ' ') || true
    if [ "$running" -gt 0 ]; then
        log_info "Containers already running (${running} active) -- skipping compose up"
        return 0
    fi

    log_info "Starting Docker Compose stack..."
    # Run from AGMIND_DIR so .env and versions.env are auto-loaded
    (cd "$AGMIND_DIR" && docker compose up -d)
    log_info "Docker Compose stack started"
}

# =============================================================================
# Phase 6 Entry Point
# =============================================================================
# Injects Open WebUI admin credentials into .env (before first startup),
# then starts Docker Compose.

phase_6_start() {
    # Inject admin credentials BEFORE compose up so env vars are present on first startup
    _inject_admin_credentials

    # Start Docker Compose stack
    _start_compose

    log_info "Docker Compose stack started"
}
