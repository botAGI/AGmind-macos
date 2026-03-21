#!/bin/bash
# lib/ollama.sh -- AGMind native Ollama management
# Sourced by install.sh for Phase 4 (Ollama Setup)
# Compatible with /bin/bash 3.2.57 (stock macOS)
#
# IMPORTANT: Ollama is NEVER run inside Docker on macOS.
# It runs natively via Homebrew to access Metal GPU acceleration.
#
# Provides: Ollama installation, service management, readiness polling
# Exports: install_ollama, start_ollama, wait_for_ollama
#
# Depends on: lib/common.sh (log_info, log_warn, log_error, log_debug, die)
#             lib/detect.sh (OLLAMA_RUNNING, BREW_PREFIX globals)

set -eEuo pipefail

# =============================================================================
# Ollama Installation
# =============================================================================
# Installs Ollama via Homebrew if not already present.
# Idempotent: skips if Ollama is already running or installed.

install_ollama() {
    # Skip if Ollama is already running (detected in Phase 1)
    if [ "${OLLAMA_RUNNING:-0}" = "1" ]; then
        log_info "Ollama already running -- skipping install"
        return 0
    fi

    # Check if ollama is installed via brew
    if brew list --formula ollama >/dev/null 2>&1; then
        log_info "Ollama already installed"
        return 0
    fi

    # Install ollama via Homebrew
    brew install ollama
    log_info "Ollama installed via Homebrew"
}

# =============================================================================
# Ollama Service Start
# =============================================================================
# Starts Ollama via brew services. Uses restart instead of start for robustness
# (handles case where plist is loaded but process crashed).
# Calls wait_for_ollama to confirm readiness after starting.

start_ollama() {
    # Skip if Ollama is already running
    if [ "${OLLAMA_RUNNING:-0}" = "1" ]; then
        log_info "Ollama already running on port 11434 -- skipping start"
        return 0
    fi

    # Use restart instead of start for robustness (handles crashed process)
    brew services restart ollama
    log_info "Ollama service started"

    # Wait for API readiness
    wait_for_ollama
}

# =============================================================================
# Ollama Readiness Polling
# =============================================================================
# Counter-based polling loop (Bash 3.2 compatible, no external timer).
# Polls localhost:11434/api/tags every 2 seconds, up to 30 attempts (60s).

wait_for_ollama() {
    local max_attempts=30
    local attempt=0

    log_info "Waiting for Ollama API..."

    while [ "$attempt" -lt "$max_attempts" ]; do
        if curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
            log_info "Ollama is ready"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 2
    done

    die "Ollama failed to start within 60 seconds" "Check: brew services list | grep ollama"
}
