#!/usr/bin/env bats
# tests/unit/test_docker.bats -- Tests for lib/docker.sh
# Covers: DOCKER-01 through DOCKER-06
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
    source "${PROJECT_ROOT}/lib/docker.sh"
    trap - ERR

    # Default mock config
    export MOCK_DOCKER_SOCKET="none"
    export MOCK_COLIMA_STATUS="stopped"
    export MOCK_BREW_INSTALLED="colima,docker,docker-compose,ollama"
    export MOCK_COMPOSE_VERSION="Docker Compose version v2.32.4"
    export MOCK_OLLAMA_API="ok"
    export DETECTED_ARCH="arm64"
    export BREW_PREFIX="/opt/homebrew"
    export NON_INTERACTIVE="1"

    # Ensure DOCKER_RUNTIME is not set (so auto-detection runs)
    unset DOCKER_RUNTIME
}

# =============================================================================
# DOCKER-01: detect_docker_runtime
# =============================================================================

@test "DOCKER-01: detect_docker_runtime detects Desktop" {
    export MOCK_DOCKER_SOCKET="desktop"
    detect_docker_runtime
    [ "$DOCKER_RUNTIME" = "desktop" ]
}

@test "DOCKER-01: detect_docker_runtime detects Colima" {
    export MOCK_DOCKER_SOCKET="colima"
    detect_docker_runtime
    [ "$DOCKER_RUNTIME" = "colima" ]
}

@test "DOCKER-01: detect_docker_runtime returns none when no runtime" {
    export MOCK_DOCKER_SOCKET="none"
    detect_docker_runtime
    [ "$DOCKER_RUNTIME" = "none" ]
}

@test "DOCKER-01: detect_docker_runtime prefers Desktop when both available" {
    export MOCK_DOCKER_SOCKET="both"
    detect_docker_runtime
    [ "$DOCKER_RUNTIME" = "desktop" ]
}

# =============================================================================
# DOCKER-06: DOCKER_RUNTIME env override
# =============================================================================

@test "DOCKER-06: DOCKER_RUNTIME env override skips detection" {
    export MOCK_DOCKER_SOCKET="desktop"
    export DOCKER_RUNTIME="colima"
    detect_docker_runtime
    [ "$DOCKER_RUNTIME" = "colima" ]
}

@test "DOCKER-06: DOCKER_RUNTIME override preserves value unchanged" {
    export DOCKER_RUNTIME="desktop"
    detect_docker_runtime
    [ "$DOCKER_RUNTIME" = "desktop" ]
}

# =============================================================================
# DOCKER-02: install_colima
# =============================================================================

@test "DOCKER-02: install_colima skips when all packages installed" {
    export MOCK_BREW_INSTALLED="colima,docker,docker-compose"
    export HOME="${BATS_TEST_TMPDIR}"
    run install_colima
    assert_success
    assert_output --partial "already installed"
}

@test "DOCKER-02: install_colima installs missing packages" {
    export MOCK_BREW_INSTALLED=""
    export HOME="${BATS_TEST_TMPDIR}"
    run install_colima
    assert_success
    assert_output --partial "Installing"
}

@test "DOCKER-02: install_colima installs only missing packages" {
    export MOCK_BREW_INSTALLED="docker"
    export HOME="${BATS_TEST_TMPDIR}"
    run install_colima
    assert_success
    assert_output --partial "Installing"
    assert_output --partial "docker already installed"
}

# =============================================================================
# DOCKER-03: start_colima
# =============================================================================

@test "DOCKER-03: start_colima skips when already running" {
    export MOCK_COLIMA_STATUS="running"
    run start_colima
    assert_success
    assert_output --partial "already running"
}

@test "DOCKER-03: start_colima maps arm64 to aarch64" {
    export DETECTED_ARCH="arm64"
    export MOCK_COLIMA_STATUS="stopped"
    export MOCK_DOCKER_SOCKET="colima"
    run start_colima
    assert_success
    assert_output --partial "aarch64"
}

@test "DOCKER-03: start_colima maps x86_64 to x86_64" {
    export DETECTED_ARCH="x86_64"
    export MOCK_COLIMA_STATUS="stopped"
    export MOCK_DOCKER_SOCKET="colima"
    run start_colima
    assert_success
    assert_output --partial "x86_64"
}

@test "DOCKER-03: start_colima uses resource overrides" {
    export DETECTED_ARCH="arm64"
    export MOCK_COLIMA_STATUS="stopped"
    export MOCK_DOCKER_SOCKET="colima"
    export COLIMA_CPU=4
    export COLIMA_MEMORY=8
    export COLIMA_DISK=40
    run start_colima
    assert_success
    assert_output --partial "cpu=4"
    assert_output --partial "memory=8"
    assert_output --partial "disk=40"
}

@test "DOCKER-03: start_colima uses default resources when env not set" {
    export DETECTED_ARCH="arm64"
    export MOCK_COLIMA_STATUS="stopped"
    export MOCK_DOCKER_SOCKET="colima"
    unset COLIMA_CPU COLIMA_MEMORY COLIMA_DISK 2>/dev/null || true
    run start_colima
    assert_success
    assert_output --partial "cpu=8"
    assert_output --partial "memory=16"
    assert_output --partial "disk=60"
}

# =============================================================================
# DOCKER-04: fix_docker_socket
# =============================================================================

@test "DOCKER-04: fix_docker_socket dies when Desktop socket missing" {
    export HOME="${BATS_TEST_TMPDIR}"
    export DOCKER_RUNTIME="desktop"
    export MOCK_DOCKER_SOCKET="desktop"
    # HOME is overridden to tmpdir, so socket file won't exist
    run fix_docker_socket
    assert_failure
    assert_output --partial "socket not found"
}

@test "DOCKER-04: fix_docker_socket dies when socket missing for colima" {
    export HOME="${BATS_TEST_TMPDIR}"
    export DOCKER_RUNTIME="colima"
    run fix_docker_socket
    assert_failure
    assert_output --partial "socket not found"
}

@test "DOCKER-04: _get_socket_path returns desktop path" {
    export DOCKER_RUNTIME="desktop"
    run _get_socket_path
    assert_success
    assert_output --partial ".docker/run/docker.sock"
}

@test "DOCKER-04: _get_socket_path returns colima path" {
    export DOCKER_RUNTIME="colima"
    run _get_socket_path
    assert_success
    assert_output --partial ".colima/default/docker.sock"
}

@test "DOCKER-04: _get_socket_path dies on unknown runtime" {
    export DOCKER_RUNTIME="unknown"
    run _get_socket_path
    assert_failure
    assert_output --partial "Cannot determine socket path"
}

# =============================================================================
# DOCKER-05: verify_compose
# =============================================================================

@test "DOCKER-05: verify_compose succeeds with v2" {
    export MOCK_COMPOSE_VERSION="Docker Compose version v2.32.4"
    run verify_compose
    assert_success
    assert_output --partial "v2.32.4"
}

@test "DOCKER-05: verify_compose fails without Compose" {
    export MOCK_COMPOSE_VERSION="none"
    run verify_compose
    assert_failure
    assert_output --partial "not available"
}

@test "DOCKER-05: verify_compose shows remediation hint on failure" {
    export MOCK_COMPOSE_VERSION="none"
    run verify_compose
    assert_failure
    assert_output --partial "brew install docker-compose"
}

# =============================================================================
# setup_compose_plugin tests
# =============================================================================

@test "setup_compose_plugin creates config.json when missing" {
    export HOME="${BATS_TEST_TMPDIR}"
    # Ensure no config exists
    rm -rf "${HOME}/.docker"
    run setup_compose_plugin
    assert_success
    [ -f "${HOME}/.docker/config.json" ]
    grep -q "cliPluginsExtraDirs" "${HOME}/.docker/config.json"
}

@test "setup_compose_plugin preserves existing config content" {
    export HOME="${BATS_TEST_TMPDIR}"
    mkdir -p "${HOME}/.docker"
    printf '{"auths": {"registry.example.com": {}}}\n' > "${HOME}/.docker/config.json"
    run setup_compose_plugin
    assert_success
    grep -q "auths" "${HOME}/.docker/config.json"
    grep -q "cliPluginsExtraDirs" "${HOME}/.docker/config.json"
}

@test "setup_compose_plugin is idempotent" {
    export HOME="${BATS_TEST_TMPDIR}"
    rm -rf "${HOME}/.docker"
    setup_compose_plugin
    # Run again -- should skip
    run setup_compose_plugin
    assert_success
    # Count occurrences of cliPluginsExtraDirs -- should be exactly 1
    local count
    count=$(grep -c "cliPluginsExtraDirs" "${HOME}/.docker/config.json")
    [ "$count" -eq 1 ]
}
