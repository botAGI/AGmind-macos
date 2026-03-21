#!/usr/bin/env bats
# tests/unit/test_ollama.bats -- Tests for lib/ollama.sh
# Covers: OLLAMA-01 through OLLAMA-04
# Must be Bash 3.2 compatible -- no declare -A, mapfile, ${var,,}

load "../helpers/setup"

setup() {
    # Standard test isolation (from setup.bash pattern)
    export AGMIND_DIR="${BATS_TEST_TMPDIR}/agmind"
    export AGMIND_LOG_DIR="${AGMIND_DIR}/logs"
    export LOG_FILE="${AGMIND_LOG_DIR}/install.log"
    export STATE_FILE="${AGMIND_DIR}/.install-state"
    mkdir -p "$AGMIND_DIR" "$AGMIND_LOG_DIR"
    touch "$LOG_FILE" "$STATE_FILE"

    # Disable ERR trap before sourcing
    trap - ERR
    source "${PROJECT_ROOT}/lib/common.sh"
    trap - ERR
    source "${PROJECT_ROOT}/lib/detect.sh"
    trap - ERR
    source "${PROJECT_ROOT}/lib/ollama.sh"
    trap - ERR

    # Default mock config
    export MOCK_BREW_INSTALLED="colima,docker,docker-compose,ollama"
    export MOCK_OLLAMA_API="ok"
    export OLLAMA_RUNNING=0
    export NON_INTERACTIVE=1
}

# =============================================================================
# OLLAMA-01: install_ollama
# =============================================================================

@test "OLLAMA-01: install_ollama skips when Ollama already running" {
    export OLLAMA_RUNNING=1
    run install_ollama
    assert_success
    assert_output --partial "already running"
}

@test "OLLAMA-01: install_ollama skips when already installed via brew" {
    export OLLAMA_RUNNING=0
    export MOCK_BREW_INSTALLED="ollama"
    run install_ollama
    assert_success
    assert_output --partial "already installed"
}

@test "OLLAMA-01: install_ollama installs when not present" {
    export OLLAMA_RUNNING=0
    export MOCK_BREW_INSTALLED=""
    run install_ollama
    assert_success
    assert_output --partial "installed via Homebrew"
}

# =============================================================================
# OLLAMA-02: start_ollama
# =============================================================================

@test "OLLAMA-02: start_ollama skips when Ollama already running" {
    export OLLAMA_RUNNING=1
    run start_ollama
    assert_success
    assert_output --partial "already running"
}

@test "OLLAMA-02: start_ollama starts service when not running" {
    export OLLAMA_RUNNING=0
    export MOCK_OLLAMA_API=ok
    run start_ollama
    assert_success
    assert_output --partial "started"
}

# =============================================================================
# OLLAMA-03: wait_for_ollama
# =============================================================================

@test "OLLAMA-03: wait_for_ollama succeeds when API responds" {
    export MOCK_OLLAMA_API=ok
    run wait_for_ollama
    assert_success
    assert_output --partial "Ollama is ready"
}

@test "OLLAMA-03: wait_for_ollama fails on API unreachable" {
    # Redefine wait_for_ollama with reduced max_attempts for fast test
    wait_for_ollama() {
        local max_attempts=2
        local attempt=0
        log_info "Waiting for Ollama API..."
        while [ "$attempt" -lt "$max_attempts" ]; do
            if curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
                log_info "Ollama is ready"
                return 0
            fi
            attempt=$((attempt + 1))
            sleep 0
        done
        die "Ollama failed to start within 60 seconds" "Check: brew services list | grep ollama"
    }
    export MOCK_OLLAMA_API=fail
    run wait_for_ollama
    assert_failure
    assert_output --partial "failed to start"
}

# =============================================================================
# OLLAMA-04: Architectural constraint -- Ollama never in Docker
# =============================================================================

@test "OLLAMA-04: ollama.sh does not reference Docker containers" {
    run grep -iE "docker run|docker exec|docker compose.*ollama" "${PROJECT_ROOT}/lib/ollama.sh"
    assert_failure
}
