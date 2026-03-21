#!/usr/bin/env bats
# tests/unit/test_backup.bats -- Tests for lib/backup.sh (LaunchAgent management)
# Covers: LAUNCH-01 through LAUNCH-04
# Must be Bash 3.2 compatible -- no declare -A, mapfile, ${var,,}

load "../helpers/setup"

setup() {
    # Standard test isolation (from setup.bash pattern)
    export AGMIND_DIR="${BATS_TEST_TMPDIR}/agmind"
    export AGMIND_LOG_DIR="${AGMIND_DIR}/logs"
    export LOG_FILE="${AGMIND_LOG_DIR}/install.log"
    export STATE_FILE="${AGMIND_DIR}/.install-state"
    mkdir -p "$AGMIND_DIR" "$AGMIND_LOG_DIR" "${AGMIND_DIR}/scripts"
    touch "$LOG_FILE" "$STATE_FILE"

    # Override HOME so LaunchAgents go to tmpdir (don't touch real ~/Library)
    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "${HOME}/Library/LaunchAgents"

    # SCRIPT_DIR for template paths
    export SCRIPT_DIR="${PROJECT_ROOT}"

    # Disable ERR trap before sourcing
    trap - ERR
    source "${PROJECT_ROOT}/lib/common.sh"
    trap - ERR
    source "${PROJECT_ROOT}/lib/backup.sh"
    trap - ERR

    # Default mock config
    export MOCK_PLUTIL_LINT="ok"
    export MOCK_LAUNCHCTL_LOADED=""
    export MOCK_LAUNCHCTL_BOOTSTRAP="ok"
    export MOCK_LAUNCHCTL_LOAD="ok"
}

# =============================================================================
# LAUNCH-01: _install_plist copies backup plist to LaunchAgents
# =============================================================================

@test "LAUNCH-01: _install_plist copies backup plist to LaunchAgents" {
    run _install_plist "${PROJECT_ROOT}/templates/launchd/com.agmind.backup.plist.template" "com.agmind.backup.plist"
    assert_success
    [ -f "${HOME}/Library/LaunchAgents/com.agmind.backup.plist" ]
}

@test "LAUNCH-01: backup plist contains StartCalendarInterval with Hour 3" {
    _install_plist "${PROJECT_ROOT}/templates/launchd/com.agmind.backup.plist.template" "com.agmind.backup.plist"
    grep -q "<key>Hour</key>" "${HOME}/Library/LaunchAgents/com.agmind.backup.plist"
    grep -q "<integer>3</integer>" "${HOME}/Library/LaunchAgents/com.agmind.backup.plist"
}

# =============================================================================
# LAUNCH-02: _install_plist copies health plist to LaunchAgents
# =============================================================================

@test "LAUNCH-02: _install_plist copies health plist to LaunchAgents" {
    run _install_plist "${PROJECT_ROOT}/templates/launchd/com.agmind.health.plist.template" "com.agmind.health.plist"
    assert_success
    [ -f "${HOME}/Library/LaunchAgents/com.agmind.health.plist" ]
}

@test "LAUNCH-02: health plist contains StartInterval 60" {
    _install_plist "${PROJECT_ROOT}/templates/launchd/com.agmind.health.plist.template" "com.agmind.health.plist"
    grep -q "<key>StartInterval</key>" "${HOME}/Library/LaunchAgents/com.agmind.health.plist"
    grep -q "<integer>60</integer>" "${HOME}/Library/LaunchAgents/com.agmind.health.plist"
}

# =============================================================================
# LAUNCH-03: Plist PATH includes /opt/homebrew/bin
# =============================================================================

@test "LAUNCH-03: backup plist includes /opt/homebrew/bin in PATH" {
    _install_plist "${PROJECT_ROOT}/templates/launchd/com.agmind.backup.plist.template" "com.agmind.backup.plist"
    grep -q "/opt/homebrew/bin" "${HOME}/Library/LaunchAgents/com.agmind.backup.plist"
}

@test "LAUNCH-03: health plist includes /opt/homebrew/bin in PATH" {
    _install_plist "${PROJECT_ROOT}/templates/launchd/com.agmind.health.plist.template" "com.agmind.health.plist"
    grep -q "/opt/homebrew/bin" "${HOME}/Library/LaunchAgents/com.agmind.health.plist"
}

# =============================================================================
# LAUNCH-04: _load_launch_agent bootstrap, fallback, and idempotency
# =============================================================================

@test "LAUNCH-04: _load_launch_agent uses bootstrap when available" {
    export MOCK_LAUNCHCTL_LOADED=""
    export MOCK_LAUNCHCTL_BOOTSTRAP="ok"
    # Install the plist first so the file exists
    _install_plist "${PROJECT_ROOT}/templates/launchd/com.agmind.backup.plist.template" "com.agmind.backup.plist"
    run _load_launch_agent "${HOME}/Library/LaunchAgents/com.agmind.backup.plist"
    assert_success
    assert_output --partial "bootstrap"
}

@test "LAUNCH-04: _load_launch_agent falls back to load when bootstrap fails" {
    export MOCK_LAUNCHCTL_LOADED=""
    export MOCK_LAUNCHCTL_BOOTSTRAP="fail"
    export MOCK_LAUNCHCTL_LOAD="ok"
    _install_plist "${PROJECT_ROOT}/templates/launchd/com.agmind.backup.plist.template" "com.agmind.backup.plist"
    run _load_launch_agent "${HOME}/Library/LaunchAgents/com.agmind.backup.plist"
    assert_success
    assert_output --partial "legacy"
}

@test "LAUNCH-04: _load_launch_agent skips when already loaded" {
    export MOCK_LAUNCHCTL_LOADED="com.agmind.backup"
    _install_plist "${PROJECT_ROOT}/templates/launchd/com.agmind.backup.plist.template" "com.agmind.backup.plist"
    run _load_launch_agent "${HOME}/Library/LaunchAgents/com.agmind.backup.plist"
    assert_success
    assert_output --partial "already loaded"
}

@test "LAUNCH-04: _install_launch_agents installs both plists" {
    # Create stub scripts that _install_launch_agents copies
    echo '#!/bin/bash' > "${PROJECT_ROOT}/scripts/backup.sh"
    echo '#!/bin/bash' > "${PROJECT_ROOT}/scripts/health-gen.sh"

    export MOCK_LAUNCHCTL_LOADED=""
    export MOCK_LAUNCHCTL_BOOTSTRAP="ok"

    run _install_launch_agents
    assert_success
    [ -f "${HOME}/Library/LaunchAgents/com.agmind.backup.plist" ]
    [ -f "${HOME}/Library/LaunchAgents/com.agmind.health.plist" ]
}
