#!/usr/bin/env bats
# tests/unit/test_config.bats -- Tests for lib/config.sh
# Covers: CONFIG-01 through CONFIG-07
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

    # Set SCRIPT_DIR to project root (where templates/ lives)
    export SCRIPT_DIR="${PROJECT_ROOT}"

    # Default WIZARD_* values for tests
    export WIZARD_DEPLOY_PROFILE="lan"
    export WIZARD_LLM_MODEL="qwen2.5:14b"
    export WIZARD_EMBED_MODEL="nomic-embed-text"
    export WIZARD_VECTOR_DB="weaviate"
    export WIZARD_ETL_MODE="standard"
    export WIZARD_MONITORING_MODE="none"
    export WIZARD_BACKUP_MODE="local"
    export WIZARD_OPEN_NOTEBOOK="0"
    export WIZARD_DBGPT="0"

    # Default DOCKER_RUNTIME
    export DOCKER_RUNTIME="desktop"
    export HOME="${BATS_TEST_TMPDIR}/home"
    mkdir -p "$HOME"
}

# =============================================================================
# CONFIG-01: .env generated from correct profile template
# =============================================================================

@test "CONFIG-01: generates .env from lan template" {
    # Generate secrets first (required for _render_env_file)
    _load_or_generate_secrets
    _render_env_file
    [ -f "${AGMIND_DIR}/.env" ]
}

@test "CONFIG-01: generates .env from offline template" {
    export WIZARD_DEPLOY_PROFILE="offline"
    _load_or_generate_secrets
    _render_env_file
    [ -f "${AGMIND_DIR}/.env" ]
    grep -q "Offline Profile" "${AGMIND_DIR}/.env"
}

@test "CONFIG-01: dies when template not found" {
    export WIZARD_DEPLOY_PROFILE="bogus"
    _load_or_generate_secrets
    run _render_env_file
    assert_failure
    assert_output --partial "Template not found"
}

# =============================================================================
# CONFIG-02: .env contains OLLAMA_API_BASE
# =============================================================================

@test "CONFIG-02: env contains OLLAMA_API_BASE" {
    _load_or_generate_secrets
    _render_env_file
    grep -q "OLLAMA_API_BASE=http://host.docker.internal:11434" "${AGMIND_DIR}/.env"
}

@test "CONFIG-02: env contains OLLAMA_HOST" {
    _load_or_generate_secrets
    _render_env_file
    grep -q "OLLAMA_HOST=http://host.docker.internal:11434" "${AGMIND_DIR}/.env"
}

@test "CONFIG-02: env contains OLLAMA_BASE_URL for Open WebUI" {
    _load_or_generate_secrets
    _render_env_file
    grep -q "OLLAMA_BASE_URL=http://host.docker.internal:11434" "${AGMIND_DIR}/.env"
}

# =============================================================================
# CONFIG-03: nginx.conf generated from template
# =============================================================================

@test "CONFIG-03: generates nginx.conf" {
    _render_nginx_conf
    [ -f "${AGMIND_DIR}/nginx.conf" ]
}

@test "CONFIG-03: nginx.conf contains upstream blocks" {
    _render_nginx_conf
    grep -q "upstream dify-api" "${AGMIND_DIR}/nginx.conf"
    grep -q "upstream open-webui" "${AGMIND_DIR}/nginx.conf"
}

@test "CONFIG-03: nginx.conf listens on port 80" {
    _render_nginx_conf
    grep -q "listen 80" "${AGMIND_DIR}/nginx.conf"
}

# =============================================================================
# CONFIG-04: COMPOSE_PROFILES correct for wizard choices
# =============================================================================

@test "CONFIG-04: build_compose_profiles includes postgresql" {
    run _build_compose_profiles
    assert_success
    assert_output --partial "postgresql"
}

@test "CONFIG-04: build_compose_profiles includes vector db weaviate" {
    export WIZARD_VECTOR_DB="weaviate"
    run _build_compose_profiles
    assert_success
    assert_output --partial "weaviate"
}

@test "CONFIG-04: build_compose_profiles includes qdrant when selected" {
    export WIZARD_VECTOR_DB="qdrant"
    run _build_compose_profiles
    assert_success
    assert_output --partial "qdrant"
}

@test "CONFIG-04: build_compose_profiles adds etl-extended for extended ETL" {
    export WIZARD_ETL_MODE="extended"
    run _build_compose_profiles
    assert_success
    assert_output --partial "etl-extended"
}

@test "CONFIG-04: build_compose_profiles omits etl-extended for standard ETL" {
    export WIZARD_ETL_MODE="standard"
    run _build_compose_profiles
    assert_success
    refute_output --partial "etl-extended"
}

@test "CONFIG-04: build_compose_profiles adds monitoring when local" {
    export WIZARD_MONITORING_MODE="local"
    run _build_compose_profiles
    assert_success
    assert_output --partial "monitoring"
}

@test "CONFIG-04: build_compose_profiles omits monitoring when none" {
    export WIZARD_MONITORING_MODE="none"
    run _build_compose_profiles
    assert_success
    refute_output --partial "monitoring"
}

@test "CONFIG-04: COMPOSE_PROFILES substituted in .env" {
    _load_or_generate_secrets
    _render_env_file
    grep -q "COMPOSE_PROFILES=postgresql,weaviate" "${AGMIND_DIR}/.env"
}

# =============================================================================
# CONFIG-05: extra_hosts present on Ollama-calling services
# =============================================================================

# Helper: extract a YAML service block (from "  <name>:" to next "  <name>:" at
# same indent level) and check for extra_hosts. Uses awk for reliable parsing.
# Bash 3.2 compatible -- no special features used.
_assert_service_has_extra_hosts() {
    local svc="$1"
    local compose="${SCRIPT_DIR}/templates/docker-compose.yml"
    # awk: capture lines from "^  <svc>:" until next "^  [a-z]" top-level service
    local block
    block=$(awk -v svc="  ${svc}:" '
        $0 == svc || $0 ~ "^" svc { found=1 }
        found && /^  [a-z]/ && $0 !~ "^" svc { found=0 }
        found { print }
    ' "$compose")
    echo "$block" | grep -q "host.docker.internal:host-gateway"
}

@test "CONFIG-05: compose template has extra_hosts on api service" {
    _assert_service_has_extra_hosts "api"
}

@test "CONFIG-05: compose template has extra_hosts on worker service" {
    _assert_service_has_extra_hosts "worker"
}

@test "CONFIG-05: compose template has extra_hosts on worker_beat service" {
    _assert_service_has_extra_hosts "worker_beat"
}

@test "CONFIG-05: compose template has extra_hosts on open-webui service" {
    _assert_service_has_extra_hosts "open-webui"
}

@test "CONFIG-05: compose template has extra_hosts on sandbox service" {
    _assert_service_has_extra_hosts "sandbox"
}

@test "CONFIG-05: compose template has extra_hosts on plugin_daemon service" {
    _assert_service_has_extra_hosts "plugin_daemon"
}

# =============================================================================
# CONFIG-06: Secrets generated and credentials.txt mode 600
# =============================================================================

@test "CONFIG-06: _generate_secret produces 32 char string" {
    run _generate_secret
    assert_success
    [ ${#output} -eq 32 ]
}

@test "CONFIG-06: _generate_secret produces only alphanumeric characters" {
    run _generate_secret
    assert_success
    local cleaned
    cleaned=$(echo "$output" | tr -d 'A-Za-z0-9')
    [ -z "$cleaned" ]
}

@test "CONFIG-06: _generate_secret produces unique values" {
    local s1 s2
    s1=$(_generate_secret)
    s2=$(_generate_secret)
    [ "$s1" != "$s2" ]
}

@test "CONFIG-06: _load_or_generate_secrets creates credentials.txt" {
    _load_or_generate_secrets
    [ -f "${AGMIND_DIR}/credentials.txt" ]
}

@test "CONFIG-06: credentials.txt has correct permissions" {
    _load_or_generate_secrets
    local perms
    perms=$(stat -f %Lp "${AGMIND_DIR}/credentials.txt")
    [ "$perms" = "600" ]
}

@test "CONFIG-06: credentials.txt contains all 9 secrets" {
    _load_or_generate_secrets
    local creds="${AGMIND_DIR}/credentials.txt"
    grep -q "DB_PASSWORD=" "$creds"
    grep -q "REDIS_PASSWORD=" "$creds"
    grep -q "DIFY_SECRET_KEY=" "$creds"
    grep -q "OPENWEBUI_SECRET=" "$creds"
    grep -q "SANDBOX_API_KEY=" "$creds"
    grep -q "WEAVIATE_API_KEY=" "$creds"
    grep -q "QDRANT_API_KEY=" "$creds"
    grep -q "PLUGIN_DAEMON_KEY=" "$creds"
    grep -q "DIFY_INNER_API_KEY=" "$creds"
}

@test "CONFIG-06: _load_or_generate_secrets reuse existing secrets (idempotent)" {
    # Write known credentials
    local creds="${AGMIND_DIR}/credentials.txt"
    cat > "$creds" <<'CREDS'
DB_PASSWORD=KNOWN_DB_SECRET_12345678901234
REDIS_PASSWORD=KNOWN_REDIS_SECRET_1234567890
DIFY_SECRET_KEY=KNOWN_DIFY_SECRET_12345678901
OPENWEBUI_SECRET=KNOWN_OWUI_SECRET_12345678901
SANDBOX_API_KEY=KNOWN_SANDBOX_KEY_12345678901
WEAVIATE_API_KEY=KNOWN_WEAV_KEY_123456789012345
QDRANT_API_KEY=KNOWN_QDRANT_KEY_1234567890123
PLUGIN_DAEMON_KEY=KNOWN_PLUGIN_KEY_123456789012
DIFY_INNER_API_KEY=KNOWN_INNER_KEY_12345678901
CREDS
    chmod 600 "$creds"

    # Reload -- should reuse, not regenerate
    _load_or_generate_secrets
    [ "$DB_PASSWORD" = "KNOWN_DB_SECRET_12345678901234" ]
}

@test "CONFIG-06: secrets substituted in .env (no remaining placeholders)" {
    _load_or_generate_secrets
    _render_env_file
    local count
    count=$(grep -c '{{' "${AGMIND_DIR}/.env" || true)
    [ "$count" -eq 0 ]
}

# =============================================================================
# CONFIG-07: No excluded services in compose template
# =============================================================================

@test "CONFIG-07: compose excludes ollama service definition" {
    # Look for a top-level service named 'ollama:' (2-space indent)
    run grep -E "^  ollama:" "${SCRIPT_DIR}/templates/docker-compose.yml"
    assert_failure
}

@test "CONFIG-07: compose excludes vllm service definition" {
    run grep -E "^  vllm:" "${SCRIPT_DIR}/templates/docker-compose.yml"
    assert_failure
}

@test "CONFIG-07: compose excludes tei service definition" {
    run grep -E "^  tei:" "${SCRIPT_DIR}/templates/docker-compose.yml"
    assert_failure
}

@test "CONFIG-07: compose excludes authelia service definition" {
    run grep -E "^  authelia:" "${SCRIPT_DIR}/templates/docker-compose.yml"
    assert_failure
}

# =============================================================================
# Additional integration tests
# =============================================================================

@test "_get_docker_socket_volume returns desktop path" {
    export DOCKER_RUNTIME="desktop"
    run _get_docker_socket_volume
    assert_success
    assert_output "${HOME}/.docker/run/docker.sock"
}

@test "_get_docker_socket_volume returns colima path" {
    export DOCKER_RUNTIME="colima"
    run _get_docker_socket_volume
    assert_success
    assert_output "${HOME}/.colima/default/docker.sock"
}

@test "_render_compose_file substitutes docker socket path" {
    _render_compose_file
    local count
    count=$(grep -c '{{DOCKER_SOCKET_PATH}}' "${AGMIND_DIR}/docker-compose.yml" || true)
    [ "$count" -eq 0 ]
}

@test "env file has no remaining placeholders after full phase" {
    _load_or_generate_secrets
    _render_env_file
    _render_nginx_conf
    _render_compose_file
    local count
    count=$(grep -c '{{' "${AGMIND_DIR}/.env" || true)
    [ "$count" -eq 0 ]
}

# =============================================================================
# CONFIG-08: Compose profiles with optional tools (v1.1) -- TEST-05
# =============================================================================

@test "CONFIG-08: build_compose_profiles omits opennotebook when not selected" {
    export WIZARD_OPEN_NOTEBOOK="0"
    export WIZARD_DBGPT="0"
    run _build_compose_profiles
    assert_success
    refute_output --partial "opennotebook"
}

@test "CONFIG-08: build_compose_profiles includes opennotebook when selected" {
    export WIZARD_OPEN_NOTEBOOK="1"
    export WIZARD_DBGPT="0"
    run _build_compose_profiles
    assert_success
    assert_output --partial "opennotebook"
    refute_output --partial "dbgpt"
}

@test "CONFIG-08: build_compose_profiles includes dbgpt when selected" {
    export WIZARD_OPEN_NOTEBOOK="0"
    export WIZARD_DBGPT="1"
    run _build_compose_profiles
    assert_success
    assert_output --partial "dbgpt"
    refute_output --partial "opennotebook"
}

@test "CONFIG-08: build_compose_profiles includes both optional tools" {
    export WIZARD_OPEN_NOTEBOOK="1"
    export WIZARD_DBGPT="1"
    run _build_compose_profiles
    assert_success
    assert_output --partial "opennotebook"
    assert_output --partial "dbgpt"
}

@test "CONFIG-08: COMPOSE_PROFILES in .env includes opennotebook when selected" {
    export WIZARD_OPEN_NOTEBOOK="1"
    export WIZARD_DBGPT="0"
    _load_or_generate_secrets
    _render_env_file
    grep -q "opennotebook" "${AGMIND_DIR}/.env"
}

@test "CONFIG-08: COMPOSE_PROFILES in .env includes both optional tools" {
    export WIZARD_OPEN_NOTEBOOK="1"
    export WIZARD_DBGPT="1"
    _load_or_generate_secrets
    _render_env_file
    grep -q "opennotebook" "${AGMIND_DIR}/.env"
    grep -q "dbgpt" "${AGMIND_DIR}/.env"
}
