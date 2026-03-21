#!/bin/bash
# lib/health.sh -- AGMind container and Ollama health verification
# Sourced by install.sh for Phase 7 (Health)
# Compatible with /bin/bash 3.2.57 (stock macOS)
#
# Provides: Container health polling and Ollama API verification
# Exports: phase_7_health
#
# Depends on: lib/common.sh (log_info, die, AGMIND_DIR)

set -eEuo pipefail

# =============================================================================
# Container Health Polling (healthcheck-aware)
# =============================================================================
# Polls containers that have Docker healthcheck definitions.
# Uses docker inspect to check .State.Health.Status for "healthy".
# Counter-based loop (no GNU timeout).

_wait_for_container_health() {
    local service="$1"
    local max_attempts="${2:-24}"
    local attempt=0

    local container_id
    container_id=$(cd "$AGMIND_DIR" && docker compose ps -q "$service" 2>/dev/null) || true

    if [ -z "$container_id" ]; then
        die "Service ${service} not found in Docker Compose" \
            "Check: cd ${AGMIND_DIR} && docker compose ps"
    fi

    log_info "Waiting for ${service} to become healthy..."

    while [ "$attempt" -lt "$max_attempts" ]; do
        local status
        status=$(docker inspect --format '{{.State.Health.Status}}' "$container_id" 2>/dev/null) || true

        if [ "$status" = "healthy" ]; then
            log_info "[PASS] ${service} is healthy"
            return 0
        fi

        attempt=$((attempt + 1))
        sleep 5
    done

    die "${service} failed health check after $((max_attempts * 5))s" \
        "Check: docker logs \$(cd ${AGMIND_DIR} && docker compose ps -q ${service})"
}

# =============================================================================
# Container Running State Check (no healthcheck)
# =============================================================================
# For containers without Docker healthcheck definitions, verify they are
# at least in "running" state.

_wait_for_running() {
    local service="$1"
    local max_attempts="${2:-12}"
    local attempt=0

    local container_id
    container_id=$(cd "$AGMIND_DIR" && docker compose ps -q "$service" 2>/dev/null) || true

    if [ -z "$container_id" ]; then
        die "Service ${service} not found in Docker Compose" \
            "Check: cd ${AGMIND_DIR} && docker compose ps"
    fi

    while [ "$attempt" -lt "$max_attempts" ]; do
        local status
        status=$(docker inspect --format '{{.State.Status}}' "$container_id" 2>/dev/null) || true

        if [ "$status" = "running" ]; then
            log_info "[PASS] ${service} is running"
            return 0
        fi

        attempt=$((attempt + 1))
        sleep 5
    done

    die "${service} not running after $((max_attempts * 5))s" \
        "Check: docker logs \$(cd ${AGMIND_DIR} && docker compose ps -q ${service})"
}

# =============================================================================
# Ollama API Health Check
# =============================================================================
# Polls Ollama API at localhost:11434/api/tags (same pattern as wait_for_ollama
# in lib/ollama.sh). Counter-based: 30 attempts x 2s = 60s.

_check_ollama_health() {
    local max_attempts=30
    local attempt=0

    log_info "Checking Ollama API health..."

    while [ "$attempt" -lt "$max_attempts" ]; do
        if curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
            log_info "[PASS] Ollama API is healthy"
            return 0
        fi

        attempt=$((attempt + 1))
        sleep 2
    done

    die "Ollama API not responding after 60s" \
        "Check: brew services list | grep ollama"
}

# =============================================================================
# Phase 7 Entry Point
# =============================================================================
# Checks health of all containers (healthcheck-aware and running-state)
# and verifies Ollama API is responding.

phase_7_health() {
    # Services with Docker healthcheck definitions
    local healthcheck_services="api db_postgres redis"

    # Conditionally add weaviate if selected in COMPOSE_PROFILES
    local profiles
    profiles=$(grep '^COMPOSE_PROFILES=' "${AGMIND_DIR}/.env" 2>/dev/null | cut -d= -f2) || true
    case "$profiles" in
        *weaviate*) healthcheck_services="$healthcheck_services weaviate" ;;
    esac

    # Poll healthcheck services
    local svc
    for svc in $healthcheck_services; do
        _wait_for_container_health "$svc"
    done

    # Get all running service names and check remaining for "running" state
    local all_services
    all_services=$(cd "$AGMIND_DIR" && docker compose ps --services 2>/dev/null) || true

    local remaining_svc
    for remaining_svc in $all_services; do
        # Skip services already checked via healthcheck
        local already_checked=0
        local checked_svc
        for checked_svc in $healthcheck_services; do
            if [ "$remaining_svc" = "$checked_svc" ]; then
                already_checked=1
                break
            fi
        done
        if [ "$already_checked" -eq 1 ]; then
            continue
        fi
        _wait_for_running "$remaining_svc"
    done

    # Check Ollama API (native, not in Docker)
    _check_ollama_health

    log_info "All services healthy"
}
