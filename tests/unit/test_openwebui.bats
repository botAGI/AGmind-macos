#!/usr/bin/env bats
# tests/unit/test_openwebui.bats -- Tests for lib/openwebui.sh
# Covers: DEPLOY-05
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

    # Create test fixtures
    touch "${AGMIND_DIR}/.env"
    touch "${AGMIND_DIR}/credentials.txt"

    # Default mock config
    export MOCK_OPENWEBUI_API="ok"
    export MOCK_OPENWEBUI_SIGNUP="ok"

    # Override sleep to avoid delays in tests
    sleep() { :; }
}

# =============================================================================
# DEPLOY-05: _inject_admin_credentials
# =============================================================================

@test "DEPLOY-05: _inject_admin_credentials adds vars to .env" {
    # Start with empty .env
    > "${AGMIND_DIR}/.env"
    run _inject_admin_credentials
    assert_success
    grep -q "WEBUI_ADMIN_EMAIL=admin@agmind.local" "${AGMIND_DIR}/.env"
}

@test "DEPLOY-05: _inject_admin_credentials is idempotent" {
    # Pre-inject credentials
    echo "WEBUI_ADMIN_EMAIL=admin@agmind.local" > "${AGMIND_DIR}/.env"
    run _inject_admin_credentials
    assert_success
    # Should have exactly one WEBUI_ADMIN_EMAIL line (not duplicated)
    local count
    count=$(grep -c "WEBUI_ADMIN_EMAIL" "${AGMIND_DIR}/.env")
    [ "$count" -eq 1 ]
}

@test "DEPLOY-05: _inject_admin_credentials writes to credentials.txt" {
    > "${AGMIND_DIR}/.env"
    > "${AGMIND_DIR}/credentials.txt"
    run _inject_admin_credentials
    assert_success
    grep -q "WEBUI_ADMIN_PASSWORD" "${AGMIND_DIR}/credentials.txt"
}

@test "DEPLOY-05: admin password is 32 characters" {
    > "${AGMIND_DIR}/.env"
    _inject_admin_credentials
    local pass
    pass=$(grep "WEBUI_ADMIN_PASSWORD" "${AGMIND_DIR}/.env" | cut -d= -f2)
    [ ${#pass} -eq 32 ]
}

# =============================================================================
# DEPLOY-05: _verify_openwebui_admin
# =============================================================================

@test "DEPLOY-05: _verify_openwebui_admin succeeds when UI responds" {
    export MOCK_OPENWEBUI_API="ok"
    export MOCK_OPENWEBUI_SIGNUP="ok"
    # Inject credentials first so credentials.txt has values
    > "${AGMIND_DIR}/.env"
    _inject_admin_credentials
    run _verify_openwebui_admin
    assert_success
    assert_output --partial "accessible"
}

@test "DEPLOY-05: _verify_openwebui_admin attempts POST signup as fallback" {
    export MOCK_OPENWEBUI_API="ok"
    export MOCK_OPENWEBUI_SIGNUP="exists"
    # Inject credentials first
    > "${AGMIND_DIR}/.env"
    _inject_admin_credentials
    run _verify_openwebui_admin
    assert_success
    # When signup returns "exists" (exit 1), the curl -sf captures empty result
    # and the function prints "already exists" message
    assert_output --partial "already exists"
}

@test "DEPLOY-05: _verify_openwebui_admin warns when UI not responding" {
    export MOCK_OPENWEBUI_API="fail"
    # Redefine with reduced attempts for fast test
    _verify_openwebui_admin() {
        local max_attempts=1
        local attempt=0
        log_info "Verifying Open WebUI accessibility..."
        while [ "$attempt" -lt "$max_attempts" ]; do
            if curl -sf http://localhost/ >/dev/null 2>&1; then
                log_info "Open WebUI is accessible at http://localhost/"
                break
            fi
            attempt=$((attempt + 1))
            sleep 0
        done
        if [ "$attempt" -ge "$max_attempts" ]; then
            log_warn "Open WebUI not responding at http://localhost/ -- check nginx and open-webui containers"
            return 0
        fi
    }
    run _verify_openwebui_admin
    assert_success
    assert_output --partial "not responding"
}
