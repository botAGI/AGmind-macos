#!/bin/bash
# lib/openwebui.sh -- AGMind Open WebUI admin initialization
# Sourced by install.sh for Phase 6 and Phase 9
# Compatible with /bin/bash 3.2.57 (stock macOS)
#
# Provides: Admin credential injection (env vars) and verification (POST signup fallback)
# Exports: _inject_admin_credentials, _verify_openwebui_admin
#
# Depends on: lib/common.sh (log_info, log_warn, AGMIND_DIR)
#             lib/config.sh (_generate_secret)

set -eEuo pipefail

# =============================================================================
# Admin Credential Injection (called BEFORE docker compose up)
# =============================================================================
# Appends WEBUI_ADMIN_EMAIL, WEBUI_ADMIN_PASSWORD, WEBUI_ADMIN_NAME to .env
# so Open WebUI auto-creates the admin on first startup.
# Also records credentials in credentials.txt.
# Idempotent: skips if WEBUI_ADMIN_EMAIL already present in .env.

_inject_admin_credentials() {
    local env_file="${AGMIND_DIR}/.env"
    local creds_file="${AGMIND_DIR}/credentials.txt"

    # Idempotent: skip if already injected
    if grep -q "WEBUI_ADMIN_EMAIL" "$env_file" 2>/dev/null; then
        log_info "Open WebUI admin credentials already in .env -- skipping injection"
        return 0
    fi

    # Generate admin password
    local admin_pass
    admin_pass=$(_generate_secret)
    local admin_email="admin@agmind.local"

    # Append to .env
    printf "\n# Open WebUI Admin (auto-created on first startup)\nWEBUI_ADMIN_EMAIL=%s\nWEBUI_ADMIN_PASSWORD=%s\nWEBUI_ADMIN_NAME=AGMind Admin\n" \
        "$admin_email" "$admin_pass" >> "$env_file"

    # Append to credentials.txt
    printf "\n# Open WebUI Admin\nWEBUI_ADMIN_EMAIL=%s\nWEBUI_ADMIN_PASSWORD=%s\n" \
        "$admin_email" "$admin_pass" >> "$creds_file"

    log_info "Open WebUI admin credentials injected into .env"
}

# =============================================================================
# Admin Verification (called by phase_9_complete)
# =============================================================================
# Step 1: Check that Open WebUI is accessible via nginx (port 80).
# Step 2: POST signup fallback -- attempt to create admin via API as
#          belt-and-suspenders verification (per locked CONTEXT.md decision).
# Non-fatal in all cases (log_warn, not die).

_verify_openwebui_admin() {
    # Step 1: Accessibility check (primary)
    local max_attempts=10
    local attempt=0

    log_info "Verifying Open WebUI accessibility..."

    while [ "$attempt" -lt "$max_attempts" ]; do
        if curl -sf http://localhost/ >/dev/null 2>&1; then
            log_info "Open WebUI is accessible at http://localhost/"
            break
        fi
        attempt=$((attempt + 1))
        sleep 3
    done

    if [ "$attempt" -ge "$max_attempts" ]; then
        log_warn "Open WebUI not responding at http://localhost/ -- check nginx and open-webui containers"
        return 0
    fi

    # Step 2: POST signup fallback verification (per locked CONTEXT.md decision)
    local creds_file="${AGMIND_DIR}/credentials.txt"
    local admin_email
    local admin_pass

    admin_email=$(grep "WEBUI_ADMIN_EMAIL" "$creds_file" 2>/dev/null | cut -d= -f2) || true
    admin_pass=$(grep "WEBUI_ADMIN_PASSWORD" "$creds_file" 2>/dev/null | cut -d= -f2) || true

    if [ -z "$admin_email" ] || [ -z "$admin_pass" ]; then
        log_warn "Could not read admin credentials from ${creds_file} -- skipping signup verification"
        return 0
    fi

    local payload
    payload=$(printf '{"email":"%s","password":"%s","name":"AGMind Admin"}' "$admin_email" "$admin_pass")

    local signup_result
    signup_result=$(curl -sf -X POST \
        -H "Content-Type: application/json" \
        -d "$payload" \
        http://localhost:3000/api/v1/auths/signup 2>/dev/null) || true

    if [ -n "$signup_result" ]; then
        log_info "Admin account created via signup API"
    else
        log_info "Admin account already exists (signup API returned non-success -- expected for idempotent re-run)"
    fi
}
