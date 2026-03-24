#!/bin/bash
# lib/config.sh -- AGMind configuration file generation
# Sourced by install.sh for Phase 5 (Configuration)
# Compatible with /bin/bash 3.2.57 (stock macOS)
#
# Provides: Template rendering, secret generation, config assembly
# Exports: phase_5_configuration
#
# Internal: _generate_secret, _load_or_generate_secrets, _write_credentials_file,
#           _render_env_file, _render_nginx_conf, _render_compose_file,
#           _build_compose_profiles, _get_docker_socket_volume
#
# Depends on: lib/common.sh (_atomic_sed, die, log_info, ensure_directory, AGMIND_DIR)
#             lib/wizard.sh (WIZARD_* exports)
#             lib/docker.sh (DOCKER_RUNTIME)

set -eEuo pipefail

# =============================================================================
# Secret Generation
# =============================================================================

# Generate a 32-character alphanumeric secret from /dev/urandom
_generate_secret() {
    # Read a bounded chunk from urandom, filter to alnum, take 32 chars.
    # Uses dd to read a fixed block (48 bytes gives ~36 alnum on average),
    # then tr filters + printf truncates. Avoids tr|head SIGPIPE (exit 141)
    # that occurs under set -o pipefail when head closes before tr finishes.
    local raw
    raw=$(dd if=/dev/urandom bs=256 count=1 2>/dev/null | LC_ALL=C tr -dc 'A-Za-z0-9')
    printf "%.32s" "$raw"
}

# =============================================================================
# Credential Management (idempotent)
# =============================================================================

# Load existing secrets from credentials.txt, or generate new ones.
# On re-install, reuses existing secrets to avoid breaking running services.
_load_or_generate_secrets() {
    local creds_file="${AGMIND_DIR}/credentials.txt"

    if [[ -f "$creds_file" ]]; then
        log_info "Reusing existing secrets from ${creds_file}"
        while IFS='=' read -r key value; do
            # SEC-03: whitelist allowed credential keys
            case "$key" in
                DB_PASSWORD|REDIS_PASSWORD|DIFY_SECRET_KEY|OPENWEBUI_SECRET|\
SANDBOX_API_KEY|WEAVIATE_API_KEY|QDRANT_API_KEY|\
PLUGIN_DAEMON_KEY|DIFY_INNER_API_KEY|\
OPEN_NOTEBOOK_ENCRYPTION_KEY|SURREAL_PASSWORD|\
WEBUI_ADMIN_EMAIL|WEBUI_ADMIN_PASSWORD)
                    # SEC-09: set as shell variable, not exported, to avoid leaking secrets to child processes
                    eval "$key=\$value"
                    ;;
                \#*|"")
                    continue
                    ;;
                *)
                    log_warn "Ignoring unknown key in credentials.txt: ${key}"
                    continue
                    ;;
            esac
        done < "$creds_file"
    else
        log_info "Generating new secrets..."
        DB_PASSWORD=$(_generate_secret)
        REDIS_PASSWORD=$(_generate_secret)
        DIFY_SECRET_KEY=$(_generate_secret)
        OPENWEBUI_SECRET=$(_generate_secret)
        SANDBOX_API_KEY=$(_generate_secret)
        WEAVIATE_API_KEY=$(_generate_secret)
        QDRANT_API_KEY=$(_generate_secret)
        PLUGIN_DAEMON_KEY=$(_generate_secret)
        DIFY_INNER_API_KEY=$(_generate_secret)
        OPEN_NOTEBOOK_ENCRYPTION_KEY=$(_generate_secret)
        SURREAL_PASSWORD=$(_generate_secret)
        # SEC-09: secrets are set as shell variables only, not exported,
        # to avoid leaking them to child processes via environment.
        # They are used within this shell session by _render_env_file and _write_credentials_file.
        _write_credentials_file
    fi
}

# Write credentials.txt with all 9 secrets and service URLs for reference.
# File is owner-readable only (mode 600) for security.
_write_credentials_file() {
    local creds_file="${AGMIND_DIR}/credentials.txt"
    local ts
    ts=$(date "+%Y-%m-%d %H:%M:%S")

    sudo tee "$creds_file" > /dev/null <<EOF
# AGMind Credentials - Generated ${ts}
# Keep this file safe. chmod 600.
DB_PASSWORD=${DB_PASSWORD}
REDIS_PASSWORD=${REDIS_PASSWORD}
DIFY_SECRET_KEY=${DIFY_SECRET_KEY}
OPENWEBUI_SECRET=${OPENWEBUI_SECRET}
SANDBOX_API_KEY=${SANDBOX_API_KEY}
WEAVIATE_API_KEY=${WEAVIATE_API_KEY}
QDRANT_API_KEY=${QDRANT_API_KEY}
PLUGIN_DAEMON_KEY=${PLUGIN_DAEMON_KEY}
DIFY_INNER_API_KEY=${DIFY_INNER_API_KEY}
OPEN_NOTEBOOK_ENCRYPTION_KEY=${OPEN_NOTEBOOK_ENCRYPTION_KEY}
SURREAL_PASSWORD=${SURREAL_PASSWORD}

# Service URLs (for quick reference)
# Dify Console: http://<host-ip>:80/apps/
# Open WebUI:   http://<host-ip>:80/
# Ollama API:   http://localhost:11434

# Optional Tools (if installed):
# Open Notebook: http://<host-ip>:80/notebook/
# DB-GPT:        http://<host-ip>:80/dbgpt/
EOF

    sudo chown "$(whoami)" "$creds_file"
    chmod 600 "$creds_file"
    log_info "Credentials written to ${creds_file} (mode 600)"
}

# =============================================================================
# COMPOSE_PROFILES Builder
# =============================================================================

# Build comma-separated COMPOSE_PROFILES string from wizard choices.
# Always includes postgresql. Conditionally adds vector DB, ETL, monitoring.
_build_compose_profiles() {
    local profiles="postgresql"

    # Vector DB (one of weaviate or qdrant)
    profiles="${profiles},${WIZARD_VECTOR_DB}"

    # ETL extended mode adds the unstructured service
    # NOTE: Compose profile name is "etl-extended" (per user decision in CONTEXT.md)
    #       but Dify's ETL_TYPE env var uses "unstructured" -- these are distinct
    if [ "${WIZARD_ETL_MODE}" = "extended" ]; then
        profiles="${profiles},etl-extended"
    fi

    # Monitoring adds Portainer
    if [ "${WIZARD_MONITORING_MODE}" = "local" ]; then
        profiles="${profiles},monitoring"
    fi

    # Optional tools (v1.1)
    if [ "${WIZARD_OPEN_NOTEBOOK}" = "1" ]; then
        profiles="${profiles},opennotebook"
    fi
    if [ "${WIZARD_DBGPT}" = "1" ]; then
        profiles="${profiles},dbgpt"
    fi

    echo "$profiles"
}

# =============================================================================
# Docker Socket Path
# =============================================================================

# Get Docker socket path for volume mount based on DOCKER_RUNTIME.
# Used to substitute {{DOCKER_SOCKET_PATH}} in docker-compose.yml.
_get_docker_socket_volume() {
    case "${DOCKER_RUNTIME}" in
        desktop) echo "${HOME}/.docker/run/docker.sock" ;;
        colima)  echo "${HOME}/.colima/default/docker.sock" ;;
        *)       echo "/var/run/docker.sock" ;;
    esac
}

# =============================================================================
# Sed Escape Helper
# =============================================================================

# SEC-01: Escape sed special characters in replacement values.
# Handles: backslash, pipe (delimiter), ampersand, forward slash.
# Compatible with Bash 3.2 (no ${var//} with special chars issues).
_sed_escape() {
    local val="$1"
    # Order matters: escape backslash first, then other specials
    val=$(printf '%s' "$val" | sed -e 's/\\/\\\\/g' -e 's/|/\\|/g' -e 's/&/\\&/g' -e 's|/|\\/|g')
    printf '%s' "$val"
}

# =============================================================================
# Template Rendering
# =============================================================================

# Render .env from the profile-specific template.
# Substitutes all {{PLACEHOLDER}} markers with actual values.
_render_env_file() {
    local profile="${WIZARD_DEPLOY_PROFILE}"
    local template="${SCRIPT_DIR}/templates/env.${profile}.template"
    local output="${AGMIND_DIR}/.env"

    if [[ ! -f "$template" ]]; then
        die "Template not found: ${template}" "Check templates/ directory for env.${profile}.template"
    fi

    sudo cp "$template" "$output"
    sudo chown "$(whoami)" "$output"

    # Substitute secrets (9 placeholders)
    _atomic_sed "s|{{DB_PASSWORD}}|${DB_PASSWORD}|g" "$output"
    _atomic_sed "s|{{REDIS_PASSWORD}}|${REDIS_PASSWORD}|g" "$output"
    _atomic_sed "s|{{DIFY_SECRET_KEY}}|${DIFY_SECRET_KEY}|g" "$output"
    _atomic_sed "s|{{OPENWEBUI_SECRET}}|${OPENWEBUI_SECRET}|g" "$output"
    _atomic_sed "s|{{SANDBOX_API_KEY}}|${SANDBOX_API_KEY}|g" "$output"
    _atomic_sed "s|{{WEAVIATE_API_KEY}}|${WEAVIATE_API_KEY}|g" "$output"
    _atomic_sed "s|{{QDRANT_API_KEY}}|${QDRANT_API_KEY}|g" "$output"
    _atomic_sed "s|{{PLUGIN_DAEMON_KEY}}|${PLUGIN_DAEMON_KEY}|g" "$output"
    _atomic_sed "s|{{DIFY_INNER_API_KEY}}|${DIFY_INNER_API_KEY}|g" "$output"

    # Substitute wizard choices (SEC-01: escape user-supplied values)
    _atomic_sed "s|{{WIZARD_LLM_MODEL}}|$(_sed_escape "${WIZARD_LLM_MODEL}")|g" "$output"
    _atomic_sed "s|{{WIZARD_EMBED_MODEL}}|$(_sed_escape "${WIZARD_EMBED_MODEL}")|g" "$output"
    _atomic_sed "s|{{WIZARD_VECTOR_DB}}|$(_sed_escape "${WIZARD_VECTOR_DB}")|g" "$output"

    # Build and substitute COMPOSE_PROFILES
    local profiles
    profiles=$(_build_compose_profiles)
    _atomic_sed "s|{{COMPOSE_PROFILES}}|${profiles}|g" "$output"

    # Determine ETL_TYPE from wizard choice
    # Dify env var: "dify" (standard) or "unstructured" (extended)
    local etl_type="dify"
    if [ "${WIZARD_ETL_MODE}" = "extended" ]; then
        etl_type="unstructured"
    fi
    _atomic_sed "s|{{ETL_TYPE}}|${etl_type}|g" "$output"

    chmod 600 "$output"
    log_info "Generated ${output} (profile: ${profile}, mode 600)"
}

# Render nginx.conf from template.
# No substitutions needed for v1 (all values are static Docker service names).
_render_nginx_conf() {
    local template="${SCRIPT_DIR}/templates/nginx.conf.template"
    local output="${AGMIND_DIR}/nginx.conf"

    if [[ ! -f "$template" ]]; then
        die "Template not found: ${template}" "Check templates/ directory for nginx.conf.template"
    fi

    sudo cp "$template" "$output"
    sudo chown "$(whoami)" "$output"

    log_info "Generated ${output}"
}

# Render docker-compose.yml from template.
# Only substitution: {{DOCKER_SOCKET_PATH}} for the correct Docker socket.
_render_compose_file() {
    local template="${SCRIPT_DIR}/templates/docker-compose.yml"
    local output="${AGMIND_DIR}/docker-compose.yml"

    if [[ ! -f "$template" ]]; then
        die "Template not found: ${template}" "Check templates/ directory for docker-compose.yml"
    fi

    sudo cp "$template" "$output"
    sudo chown "$(whoami)" "$output"

    # Substitute Docker socket path
    local socket_path
    socket_path=$(_get_docker_socket_volume)
    _atomic_sed "s|{{DOCKER_SOCKET_PATH}}|${socket_path}|g" "$output"

    log_info "Generated ${output}"
}

# =============================================================================
# Phase 5 Entry Point
# =============================================================================

# Main phase function wired into install.sh orchestrator.
# Generates all config files from templates and wizard choices.
phase_5_configuration() {
    log_info "Generating configuration files..."

    _load_or_generate_secrets
    _render_env_file
    _render_nginx_conf
    _render_compose_file

    # Copy versions.env for Docker Compose env_file reference
    sudo cp "${SCRIPT_DIR}/templates/versions.env" "${AGMIND_DIR}/versions.env"
    sudo chown "$(whoami)" "${AGMIND_DIR}/versions.env"

    log_info "Configuration complete -- files written to ${AGMIND_DIR}"
}
