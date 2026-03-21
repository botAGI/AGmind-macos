#!/usr/bin/env bats
# tests/unit/test_health.bats -- Tests for lib/health.sh
# Covers: DEPLOY-02, DEPLOY-03
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
    source "${PROJECT_ROOT}/lib/health.sh"
    trap - ERR

    # Default mock config
    export MOCK_DOCKER_SOCKET="desktop"
    export MOCK_CONTAINER_HEALTH_STATUS="healthy"
    export MOCK_CONTAINER_STATE_STATUS="running"
    export MOCK_COMPOSE_CONTAINER_ID="mock_container_abc123"
    export MOCK_COMPOSE_SERVICES="api db_postgres redis"
    export MOCK_OLLAMA_API="ok"

    # Create .env for phase_7_health
    echo "COMPOSE_PROFILES=postgresql,weaviate" > "${AGMIND_DIR}/.env"

    # Override sleep to avoid delays in tests
    sleep() { :; }
}

# =============================================================================
# DEPLOY-02: _wait_for_container_health
# =============================================================================

@test "DEPLOY-02: _wait_for_container_health succeeds for healthy container" {
    export MOCK_CONTAINER_HEALTH_STATUS="healthy"
    run _wait_for_container_health "api" 2
    assert_success
    assert_output --partial "PASS"
}

@test "DEPLOY-02: _wait_for_container_health fails for unhealthy container" {
    export MOCK_CONTAINER_HEALTH_STATUS="unhealthy"
    run _wait_for_container_health "api" 1
    assert_failure
}

@test "DEPLOY-02: _wait_for_running succeeds for running container" {
    export MOCK_CONTAINER_STATE_STATUS="running"
    run _wait_for_running "nginx" 2
    assert_success
    assert_output --partial "PASS"
}

@test "DEPLOY-02: _wait_for_running fails for exited container" {
    export MOCK_CONTAINER_STATE_STATUS="exited"
    run _wait_for_running "nginx" 1
    assert_failure
}

@test "DEPLOY-02: phase_7_health checks all services" {
    export MOCK_CONTAINER_HEALTH_STATUS="healthy"
    export MOCK_CONTAINER_STATE_STATUS="running"
    export MOCK_COMPOSE_SERVICES="api db_postgres redis nginx"
    export MOCK_OLLAMA_API="ok"
    run phase_7_health
    assert_success
    assert_output --partial "All services healthy"
}

@test "DEPLOY-02: phase_7_health includes weaviate when in COMPOSE_PROFILES" {
    export MOCK_CONTAINER_HEALTH_STATUS="healthy"
    export MOCK_CONTAINER_STATE_STATUS="running"
    export MOCK_COMPOSE_SERVICES="api db_postgres redis weaviate nginx"
    export MOCK_OLLAMA_API="ok"
    echo "COMPOSE_PROFILES=postgresql,weaviate" > "${AGMIND_DIR}/.env"
    run phase_7_health
    assert_success
    assert_output --partial "weaviate"
}

# =============================================================================
# DEPLOY-03: _check_ollama_health
# =============================================================================

@test "DEPLOY-03: _check_ollama_health succeeds when API responds" {
    export MOCK_OLLAMA_API="ok"
    # Redefine with reduced attempts for fast test
    _check_ollama_health() {
        local max_attempts=2
        local attempt=0
        log_info "Checking Ollama API health..."
        while [ "$attempt" -lt "$max_attempts" ]; do
            if curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
                log_info "[PASS] Ollama API is healthy"
                return 0
            fi
            attempt=$((attempt + 1))
            sleep 0
        done
        die "Ollama API not responding after 60s" "Check: brew services list | grep ollama"
    }
    run _check_ollama_health
    assert_success
    assert_output --partial "PASS"
}

@test "DEPLOY-03: _check_ollama_health fails when API down" {
    export MOCK_OLLAMA_API="fail"
    # Redefine with reduced attempts for fast test
    _check_ollama_health() {
        local max_attempts=1
        local attempt=0
        log_info "Checking Ollama API health..."
        while [ "$attempt" -lt "$max_attempts" ]; do
            if curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
                log_info "[PASS] Ollama API is healthy"
                return 0
            fi
            attempt=$((attempt + 1))
            sleep 0
        done
        die "Ollama API not responding after 60s" "Check: brew services list | grep ollama"
    }
    run _check_ollama_health
    assert_failure
}
