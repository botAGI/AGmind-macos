#!/usr/bin/env bats
# tests/unit/test_compose.bats -- Tests for lib/compose.sh
# Covers: DEPLOY-01, DEPLOY-06
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
    source "${PROJECT_ROOT}/lib/config.sh"
    trap - ERR
    source "${PROJECT_ROOT}/lib/openwebui.sh"
    trap - ERR
    source "${PROJECT_ROOT}/lib/compose.sh"
    trap - ERR

    # Create minimal test fixtures
    touch "${AGMIND_DIR}/docker-compose.yml"
    touch "${AGMIND_DIR}/.env"
    touch "${AGMIND_DIR}/credentials.txt"

    # Default mock config
    export MOCK_DOCKER_SOCKET="desktop"
    export MOCK_COMPOSE_RUNNING_COUNT=0
    export SCRIPT_DIR="${PROJECT_ROOT}"

    # Override sleep to avoid delays in tests
    sleep() { :; }
}

# =============================================================================
# DEPLOY-01: _start_compose
# =============================================================================

@test "DEPLOY-01: _start_compose runs docker compose up -d" {
    export MOCK_COMPOSE_RUNNING_COUNT=0
    run _start_compose
    assert_success
    assert_output --partial "started"
}

@test "DEPLOY-01: _start_compose skips when containers already running" {
    export MOCK_COMPOSE_RUNNING_COUNT=3
    run _start_compose
    assert_success
    assert_output --partial "already running"
}

@test "DEPLOY-01: _start_compose fails without docker-compose.yml" {
    rm "${AGMIND_DIR}/docker-compose.yml"
    run _start_compose
    assert_failure
    assert_output --partial "not found"
}

@test "DEPLOY-01: phase_6_start calls _inject_admin_credentials before compose" {
    export MOCK_COMPOSE_RUNNING_COUNT=0
    run phase_6_start
    assert_success
    # Verify admin credentials were injected into .env
    grep -q "WEBUI_ADMIN_EMAIL" "${AGMIND_DIR}/.env"
}

# =============================================================================
# DEPLOY-06: phase_9_complete (structural verification)
# =============================================================================

@test "DEPLOY-06: install.sh syntax is valid" {
    run /bin/bash -n "${PROJECT_ROOT}/install.sh"
    assert_success
}

@test "DEPLOY-06: install.sh defines phase_9_complete" {
    grep -q "phase_9_complete()" "${PROJECT_ROOT}/install.sh"
}
