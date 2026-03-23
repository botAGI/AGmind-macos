#!/usr/bin/env bats
# tests/unit/test_agmind.bats -- Tests for scripts/agmind.sh CLI
# Covers: CLI-01, CLI-02, CLI-03, CLI-04, CLI-05, CLI-06, CLI-07, CLI-08
# Must be Bash 3.2 compatible -- no declare -A, mapfile, ${var,,}

load "../helpers/setup"

setup() {
    # Standard test isolation
    export AGMIND_DIR="${BATS_TEST_TMPDIR}/agmind"
    export AGMIND_LOG_DIR="${AGMIND_DIR}/logs"
    export LOG_FILE="${AGMIND_LOG_DIR}/install.log"
    export STATE_FILE="${AGMIND_DIR}/.install-state"
    mkdir -p "$AGMIND_DIR" "$AGMIND_LOG_DIR" "${AGMIND_DIR}/scripts" "${AGMIND_DIR}/lib"
    touch "$LOG_FILE" "$STATE_FILE"

    # Create minimal fixtures the CLI expects
    touch "${AGMIND_DIR}/docker-compose.yml"
    touch "${AGMIND_DIR}/.env"

    # Copy lib modules so source paths resolve
    cp "${PROJECT_ROOT}/lib/common.sh" "${AGMIND_DIR}/lib/"
    cp "${PROJECT_ROOT}/lib/detect.sh" "${AGMIND_DIR}/lib/"
    cp "${PROJECT_ROOT}/lib/ollama.sh" "${AGMIND_DIR}/lib/"

    # Create backup.sh stub in scripts/ (cmd_backup calls this)
    cat > "${AGMIND_DIR}/scripts/backup.sh" << 'STUB'
#!/bin/bash
echo "mock: backup executed"
STUB
    chmod +x "${AGMIND_DIR}/scripts/backup.sh"

    # Default mock config
    export MOCK_DOCKER_SOCKET="desktop"
    export MOCK_COMPOSE_RUNNING_COUNT=3
    export MOCK_IP_ADDR="192.168.1.100"
    export MOCK_BREW_SERVICES_OUTPUT="ollama started $(whoami) ~/Library/LaunchAgents/homebrew.mxcl.ollama.plist"
    export MOCK_LAUNCHCTL_LIST_EXIT=0
    export MOCK_LAUNCHCTL_LOADED="com.agmind.backup,com.agmind.health"
    export MOCK_OLLAMA_API="ok"
    export MOCK_COMPOSE_PS_FORMAT_OUTPUT=""

    # CLI script path
    CLI="${PROJECT_ROOT}/scripts/agmind.sh"
}

# =============================================================================
# CLI-01: Usage and help
# =============================================================================

@test "CLI-01: agmind --help shows usage with all commands" {
    run "$CLI" --help
    assert_success
    assert_output --partial "Usage:"
    assert_output --partial "status"
    assert_output --partial "doctor"
    assert_output --partial "stop"
    assert_output --partial "start"
    assert_output --partial "restart"
    assert_output --partial "logs"
    assert_output --partial "backup"
    assert_output --partial "uninstall"
}

@test "CLI-01: agmind with no args shows usage" {
    run "$CLI"
    assert_success
    assert_output --partial "Usage:"
}

@test "CLI-01: unknown command prints error and exits 1" {
    run "$CLI" foobar
    assert_failure
    assert_output --partial "Unknown command: foobar"
}

# =============================================================================
# CLI-02: Status command
# =============================================================================

@test "CLI-02: status shows Docker container states" {
    export MOCK_COMPOSE_PS_FORMAT_OUTPUT="$(printf 'api\trunning\tUp 5 minutes')"
    run "$CLI" status
    assert_success
    assert_output --partial "api"
    assert_output --partial "[UP]"
}

@test "CLI-02: status shows Ollama brew service status" {
    run "$CLI" status
    assert_success
    assert_output --partial "[UP]"
    assert_output --partial "ollama"
}

@test "CLI-02: status shows LAN IP and service URLs" {
    run "$CLI" status
    assert_success
    assert_output --partial "192.168.1.100"
    assert_output --partial "Open WebUI"
    assert_output --partial "Dify Console"
    assert_output --partial "Ollama API"
}

# =============================================================================
# CLI-03: Doctor command
# =============================================================================

@test "CLI-03: doctor shows PASS for healthy system" {
    export MOCK_DOCKER_SOCKET="desktop"
    export MOCK_COMPOSE_RUNNING_COUNT=3
    export MOCK_OLLAMA_API="ok"
    run "$CLI" doctor
    assert_success
    assert_output --partial "[PASS]"
    assert_output --partial "All checks passed"
}

@test "CLI-03: doctor shows FAIL for Docker socket unavailable" {
    export MOCK_DOCKER_SOCKET="none"
    run "$CLI" doctor
    assert_failure
    assert_output --partial "[FAIL]"
    assert_output --partial "Docker socket"
}

# =============================================================================
# CLI-04: Stop command
# =============================================================================

@test "CLI-04: stop calls compose down then brew services stop" {
    run "$CLI" stop
    assert_success
    assert_output --partial "Docker Compose stack stopped"
    assert_output --partial "Ollama service stopped"
    # Verify compose down appears before Ollama stop (order matters)
    local compose_line
    local ollama_line
    compose_line=$(echo "$output" | grep -n "Docker Compose stack stopped" | head -1 | cut -d: -f1)
    ollama_line=$(echo "$output" | grep -n "Ollama service stopped" | head -1 | cut -d: -f1)
    [ "$compose_line" -lt "$ollama_line" ]
}

@test "CLI-04: stop without docker-compose.yml warns and continues" {
    rm "${AGMIND_DIR}/docker-compose.yml"
    run "$CLI" stop
    assert_success
    assert_output --partial "skipping compose down"
}

# =============================================================================
# CLI-05: Start command
# =============================================================================

@test "CLI-05: start runs brew services first then compose up" {
    run "$CLI" start
    assert_success
    assert_output --partial "Docker Compose stack started"
    # Verify brew services restart appears before compose up
    local brew_line
    local compose_line
    brew_line=$(echo "$output" | grep -n "brew services restart" | head -1 | cut -d: -f1)
    compose_line=$(echo "$output" | grep -n "Docker Compose stack started" | head -1 | cut -d: -f1)
    [ "$brew_line" -lt "$compose_line" ]
}

@test "CLI-05: start fails without docker-compose.yml" {
    rm "${AGMIND_DIR}/docker-compose.yml"
    run "$CLI" start
    assert_failure
}

# =============================================================================
# CLI-06: Logs command
# =============================================================================

@test "CLI-06: logs with no service shows all logs with --tail 50" {
    run "$CLI" logs
    assert_success
    assert_output --partial "docker compose logs --tail 50"
}

@test "CLI-06: logs with service name follows specific service" {
    run "$CLI" logs api
    assert_success
    assert_output --partial "docker compose logs -f api"
}

# =============================================================================
# CLI-07: Backup command
# =============================================================================

@test "CLI-07: backup calls backup.sh script" {
    run "$CLI" backup
    assert_success
    assert_output --partial "mock: backup executed"
}

# =============================================================================
# CLI-08: Uninstall command
# =============================================================================

@test "CLI-08: uninstall aborts on N response" {
    run bash -c "echo 'N' | AGMIND_DIR='${AGMIND_DIR}' AGMIND_LOG_DIR='${AGMIND_LOG_DIR}' LOG_FILE='${LOG_FILE}' STATE_FILE='${STATE_FILE}' PATH='${PATH}' '$CLI' uninstall"
    assert_success
    assert_output --partial "cancelled"
}

@test "CLI-08: uninstall proceeds on y response" {
    # Create fake LaunchAgent plists for removal test
    local la_dir="${BATS_TEST_TMPDIR}/LaunchAgents"
    mkdir -p "$la_dir"
    touch "$la_dir/com.agmind.backup.plist"
    touch "$la_dir/com.agmind.health.plist"
    export HOME="${BATS_TEST_TMPDIR}"
    run bash -c "echo 'y' | HOME='${BATS_TEST_TMPDIR}' AGMIND_DIR='${AGMIND_DIR}' AGMIND_LOG_DIR='${AGMIND_LOG_DIR}' LOG_FILE='${LOG_FILE}' STATE_FILE='${STATE_FILE}' PATH='${PATH}' MOCK_DOCKER_SOCKET='${MOCK_DOCKER_SOCKET}' MOCK_BREW_SERVICES_OUTPUT='${MOCK_BREW_SERVICES_OUTPUT}' '$CLI' uninstall"
    assert_success
    assert_output --partial "uninstalled"
}

@test "CLI-08: uninstall removes docker volumes with -v flag" {
    run bash -c "echo 'y' | HOME='${BATS_TEST_TMPDIR}' AGMIND_DIR='${AGMIND_DIR}' AGMIND_LOG_DIR='${AGMIND_LOG_DIR}' LOG_FILE='${LOG_FILE}' STATE_FILE='${STATE_FILE}' PATH='${PATH}' MOCK_DOCKER_SOCKET='${MOCK_DOCKER_SOCKET}' MOCK_BREW_SERVICES_OUTPUT='${MOCK_BREW_SERVICES_OUTPUT}' '$CLI' uninstall"
    assert_success
    assert_output --partial "docker compose down -v"
}
