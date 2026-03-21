#!/usr/bin/env bats
# tests/unit/test_detect.bats -- Tests for lib/detect.sh
# Covers: DETECT-01 through DETECT-09
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

    # Default mock config: qualifying system
    export MOCK_OS_VERSION="14.2"
    export MOCK_ARCH="arm64"
    export MOCK_RAM_BYTES="34359738368"        # 32GB
    export MOCK_DISK_AVAIL_KB="356279404"      # ~339GB
    export MOCK_PORTS_IN_USE=""                 # no port conflicts
    export MOCK_DOCKER_SOCKET="none"
    export MOCK_OLLAMA_API="ok"
    export NON_INTERACTIVE="1"                  # prevent read prompts in tests

    # Ensure DOCKER_RUNTIME is not set (so auto-detection runs)
    unset DOCKER_RUNTIME
    # Ensure SKIP_PREFLIGHT is not set
    unset SKIP_PREFLIGHT
}

# =============================================================================
# Group 1: detect_os (DETECT-01)
# =============================================================================

@test "detect_os exports DETECTED_OS as macos" {
    detect_os
    [ "$DETECTED_OS" = "macos" ]
}

@test "detect_os exports DETECTED_OS_VERSION from sw_vers" {
    detect_os
    [ "$DETECTED_OS_VERSION" = "14.2" ]
}

@test "detect_os exports DETECTED_ARCH from uname" {
    detect_os
    [ "$DETECTED_ARCH" = "arm64" ]
}

@test "detect_os handles high version numbers" {
    export MOCK_OS_VERSION="26.3"
    detect_os
    [ "$DETECTED_OS_VERSION" = "26.3" ]
}

@test "detect_os detects x86_64 architecture" {
    export MOCK_ARCH="x86_64"
    detect_os
    [ "$DETECTED_ARCH" = "x86_64" ]
}

# =============================================================================
# Group 2: detect_ram (DETECT-02)
# =============================================================================

@test "detect_ram exports DETECTED_RAM_GB as integer" {
    detect_ram
    [ "$DETECTED_RAM_GB" = "32" ]
}

@test "detect_ram handles 8GB system" {
    export MOCK_RAM_BYTES="8589934592"
    detect_ram
    [ "$DETECTED_RAM_GB" = "8" ]
}

@test "detect_ram handles 192GB system" {
    export MOCK_RAM_BYTES="206158430208"
    detect_ram
    [ "$DETECTED_RAM_GB" = "192" ]
}

# =============================================================================
# Group 3: detect_disk (DETECT-03)
# =============================================================================

@test "detect_disk exports DETECTED_DISK_FREE_GB" {
    detect_disk
    # 356279404 / 1024 / 1024 = 339
    [ "$DETECTED_DISK_FREE_GB" = "339" ]
}

@test "detect_disk handles low disk space" {
    export MOCK_DISK_AVAIL_KB="20971520"
    detect_disk
    # 20971520 / 1024 / 1024 = 20 (integer truncation okay, 20971520/1048576=19.99... -> 19)
    [ "$DETECTED_DISK_FREE_GB" = "19" ] || [ "$DETECTED_DISK_FREE_GB" = "20" ]
}

# =============================================================================
# Group 4: detect_ports / _check_port (DETECT-04)
# =============================================================================

@test "_check_port returns 1 when port is free" {
    export MOCK_PORTS_IN_USE=""
    run _check_port 80
    assert_failure
}

@test "_check_port returns 0 and echoes process info when port in use" {
    export MOCK_PORTS_IN_USE="80:nginx:1234"
    run _check_port 80
    assert_success
    assert_output --partial "nginx"
    assert_output --partial "1234"
}

@test "_check_port returns 1 for unmatched port" {
    export MOCK_PORTS_IN_USE="80:nginx:1234"
    run _check_port 3000
    assert_failure
}

@test "detect_ports populates PORT_CONFLICTS for occupied ports" {
    export MOCK_PORTS_IN_USE="80:nginx:1234,3000:node:5678"
    detect_ports
    echo "$PORT_CONFLICTS" | grep -q "80:"
    echo "$PORT_CONFLICTS" | grep -q "3000:"
}

@test "detect_ports leaves PORT_CONFLICTS empty when no conflicts" {
    export MOCK_PORTS_IN_USE=""
    detect_ports
    [ -z "$PORT_CONFLICTS" ]
}

# =============================================================================
# Group 5: detect_docker (DETECT-05)
# =============================================================================

@test "detect_docker sets DOCKER_RUNTIME=none when no runtime found" {
    export MOCK_DOCKER_SOCKET="none"
    detect_docker
    [ "$DOCKER_RUNTIME" = "none" ]
}

@test "detect_docker respects DOCKER_RUNTIME env override" {
    export DOCKER_RUNTIME="colima"
    detect_docker
    [ "$DOCKER_RUNTIME" = "colima" ]
}

@test "detect_docker respects DOCKER_RUNTIME desktop override" {
    export DOCKER_RUNTIME="desktop"
    detect_docker
    [ "$DOCKER_RUNTIME" = "desktop" ]
}

# =============================================================================
# Group 6: detect_ollama (DETECT-06)
# =============================================================================

@test "detect_ollama sets OLLAMA_RUNNING=0 when port 11434 is free" {
    export MOCK_PORTS_IN_USE=""
    detect_ollama
    [ "$OLLAMA_RUNNING" = "0" ]
}

@test "detect_ollama sets OLLAMA_RUNNING=1 when Ollama is responding" {
    export MOCK_PORTS_IN_USE="11434:ollama:923"
    export MOCK_OLLAMA_API="ok"
    detect_ollama
    [ "$OLLAMA_RUNNING" = "1" ]
}

@test "detect_ollama sets OLLAMA_RUNNING=1 when port in use but API fails" {
    export MOCK_PORTS_IN_USE="11434:ollama:923"
    export MOCK_OLLAMA_API="fail"
    detect_ollama
    [ "$OLLAMA_RUNNING" = "1" ]
}

# =============================================================================
# Group 7: detect_homebrew (DETECT-07)
# =============================================================================

@test "detect_homebrew sets BREW_INSTALLED=1 when brew exists" {
    detect_homebrew
    [ "$BREW_INSTALLED" = "1" ]
}

@test "detect_homebrew sets correct BREW_PREFIX for arm64" {
    detect_homebrew
    [ "$BREW_PREFIX" = "/opt/homebrew" ]
}

# =============================================================================
# Group 8: preflight_checks (DETECT-08, DETECT-09)
# =============================================================================

@test "preflight_checks passes on qualifying system" {
    run preflight_checks
    assert_success
    assert_output --partial "[PASS]"
}

@test "preflight_checks fails on macOS version too low" {
    export MOCK_OS_VERSION="12.0"
    run preflight_checks
    assert_failure
    assert_output --partial "[FAIL]"
    assert_output --partial "macOS 12.0"
}

@test "preflight_checks fails on insufficient RAM" {
    export MOCK_RAM_BYTES="4294967296"
    run preflight_checks
    assert_failure
    assert_output --partial "[FAIL]"
    assert_output --partial "4GB"
}

@test "preflight_checks fails on insufficient disk" {
    export MOCK_DISK_AVAIL_KB="20971520"
    run preflight_checks
    assert_failure
    assert_output --partial "[FAIL]"
}

@test "preflight_checks fails on port 80 conflict" {
    export MOCK_PORTS_IN_USE="80:httpd:999"
    run preflight_checks
    assert_failure
    assert_output --partial "[FAIL]"
    assert_output --partial "Port 80"
}

@test "preflight_checks fails on port 3000 conflict" {
    export MOCK_PORTS_IN_USE="3000:node:888"
    run preflight_checks
    assert_failure
    assert_output --partial "[FAIL]"
    assert_output --partial "Port 3000"
}

@test "preflight_checks warns on port 443 conflict" {
    export MOCK_PORTS_IN_USE="443:apache:777"
    run preflight_checks
    assert_success
    assert_output --partial "[WARN]"
    assert_output --partial "443"
}

@test "preflight_checks warns on port 11434 conflict" {
    export MOCK_PORTS_IN_USE="11434:ollama:923"
    run preflight_checks
    assert_success
    assert_output --partial "[WARN]"
    assert_output --partial "Ollama"
}

@test "preflight_checks warns when no Docker runtime found" {
    export MOCK_DOCKER_SOCKET="none"
    run preflight_checks
    assert_success
    assert_output --partial "[WARN]"
    assert_output --partial "Docker"
}

@test "SKIP_PREFLIGHT=1 bypasses all checks" {
    export SKIP_PREFLIGHT="1"
    run preflight_checks
    assert_success
    assert_output --partial "skip"
}

@test "preflight_checks shows remediation hint for port conflict" {
    export MOCK_PORTS_IN_USE="80:nginx:1234"
    run preflight_checks
    assert_output --partial "nginx"
    assert_output --partial "1234"
    assert_output --partial "PID"
}

@test "preflight_checks passes with all checks clean" {
    # Set up a fully passing system: good OS, RAM, disk, no port conflicts, docker available
    export MOCK_OS_VERSION="14.2"
    export MOCK_RAM_BYTES="34359738368"
    export MOCK_DISK_AVAIL_KB="356279404"
    export MOCK_PORTS_IN_USE=""
    export DOCKER_RUNTIME="desktop"
    run preflight_checks
    assert_success
    assert_output --partial "All preflight checks passed"
}
