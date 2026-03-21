#!/usr/bin/env bats
# tests/unit/test_wizard.bats -- Tests for lib/wizard.sh
# Covers: WIZ-01 through WIZ-04
# Must be Bash 3.2 compatible -- no declare -A, mapfile, ${var,,}

load "../helpers/setup"

setup() {
    export AGMIND_DIR="${BATS_TEST_TMPDIR}/agmind"
    export AGMIND_LOG_DIR="${AGMIND_DIR}/logs"
    export LOG_FILE="${AGMIND_LOG_DIR}/install.log"
    export STATE_FILE="${AGMIND_DIR}/.install-state"
    mkdir -p "$AGMIND_DIR" "$AGMIND_LOG_DIR"
    touch "$LOG_FILE" "$STATE_FILE"

    trap - ERR
    source "${PROJECT_ROOT}/lib/common.sh"
    trap - ERR
    source "${PROJECT_ROOT}/lib/wizard.sh"
    trap - ERR

    # Default test config
    export DETECTED_RAM_GB=32
    export DETECTED_ARCH="arm64"
    export NON_INTERACTIVE=1

    # Clear any leftover WIZARD_* or input vars
    unset DEPLOY_PROFILE LLM_MODEL EMBED_MODEL VECTOR_DB ETL_MODE MONITORING_MODE BACKUP_MODE
    unset WIZARD_DEPLOY_PROFILE WIZARD_LLM_MODEL WIZARD_EMBED_MODEL WIZARD_VECTOR_DB
    unset WIZARD_ETL_MODE WIZARD_MONITORING_MODE WIZARD_BACKUP_MODE
}

# =============================================================================
# Group 1: _get_recommended_model (WIZ-02)
# =============================================================================

@test "recommends gemma3:4b for 8GB RAM" {
    run _get_recommended_model 8
    assert_success
    assert_output "gemma3:4b"
}

@test "recommends qwen2.5:7b for 16GB RAM" {
    run _get_recommended_model 16
    assert_success
    assert_output "qwen2.5:7b"
}

@test "recommends qwen2.5:14b for 32GB RAM" {
    run _get_recommended_model 32
    assert_success
    assert_output "qwen2.5:14b"
}

@test "recommends gemma3:27b for 64GB RAM" {
    run _get_recommended_model 64
    assert_success
    assert_output "gemma3:27b"
}

@test "recommends qwen2.5:72b for 96GB RAM" {
    run _get_recommended_model 96
    assert_success
    assert_output "qwen2.5:72b"
}

@test "recommends qwen2.5:72b for 192GB RAM" {
    run _get_recommended_model 192
    assert_success
    assert_output "qwen2.5:72b"
}

# =============================================================================
# Group 2: _validate_choice (helper)
# =============================================================================

@test "validate_choice accepts valid choice" {
    run _validate_choice "TEST" "lan" "lan" "offline"
    assert_success
}

@test "validate_choice rejects invalid choice" {
    run _validate_choice "TEST" "bogus" "lan" "offline"
    assert_failure
    assert_output --partial "Invalid TEST"
}

@test "validate_choice shows valid options in error" {
    run _validate_choice "TEST" "bogus" "lan" "offline"
    assert_failure
    assert_output --partial "Valid options"
}

@test "validate_choice accepts second option" {
    run _validate_choice "MODE" "offline" "lan" "offline"
    assert_success
}

# =============================================================================
# Group 3: Non-interactive mode with defaults (WIZ-03, WIZ-04)
# =============================================================================

@test "non-interactive uses defaults for all 7 parameters" {
    # Call directly (not via run) to preserve exported variables
    run_wizard
    [ "$WIZARD_DEPLOY_PROFILE" = "lan" ]
    [ "$WIZARD_LLM_MODEL" = "qwen2.5:14b" ]
    [ "$WIZARD_EMBED_MODEL" = "nomic-embed-text" ]
    [ "$WIZARD_VECTOR_DB" = "weaviate" ]
    [ "$WIZARD_ETL_MODE" = "standard" ]
    [ "$WIZARD_MONITORING_MODE" = "none" ]
    [ "$WIZARD_BACKUP_MODE" = "local" ]
}

@test "non-interactive uses explicit env vars" {
    export DEPLOY_PROFILE="offline"
    export VECTOR_DB="qdrant"
    export EMBED_MODEL="bge-m3"
    export ETL_MODE="extended"
    export MONITORING_MODE="local"
    export BACKUP_MODE="remote"
    run_wizard
    [ "$WIZARD_DEPLOY_PROFILE" = "offline" ]
    [ "$WIZARD_VECTOR_DB" = "qdrant" ]
    [ "$WIZARD_EMBED_MODEL" = "bge-m3" ]
    [ "$WIZARD_ETL_MODE" = "extended" ]
    [ "$WIZARD_MONITORING_MODE" = "local" ]
    [ "$WIZARD_BACKUP_MODE" = "remote" ]
}

# =============================================================================
# Group 4: Non-interactive validation (WIZ-03)
# =============================================================================

@test "non-interactive dies on invalid DEPLOY_PROFILE" {
    export DEPLOY_PROFILE="bogus"
    run run_wizard
    assert_failure
    assert_output --partial "Invalid DEPLOY_PROFILE"
}

@test "non-interactive dies on invalid VECTOR_DB" {
    export VECTOR_DB="milvus"
    run run_wizard
    assert_failure
    assert_output --partial "Invalid VECTOR_DB"
}

@test "non-interactive dies on invalid EMBED_MODEL" {
    export EMBED_MODEL="bad-model"
    run run_wizard
    assert_failure
    assert_output --partial "Invalid EMBED_MODEL"
}

@test "non-interactive dies on invalid ETL_MODE" {
    export ETL_MODE="turbo"
    run run_wizard
    assert_failure
    assert_output --partial "Invalid ETL_MODE"
}

@test "non-interactive dies on invalid MONITORING_MODE" {
    export MONITORING_MODE="cloud"
    run run_wizard
    assert_failure
    assert_output --partial "Invalid MONITORING_MODE"
}

@test "non-interactive dies on invalid BACKUP_MODE" {
    export BACKUP_MODE="s3"
    run run_wizard
    assert_failure
    assert_output --partial "Invalid BACKUP_MODE"
}

@test "non-interactive accepts any LLM_MODEL string" {
    export LLM_MODEL="my-custom:latest"
    run_wizard
    [ "$WIZARD_LLM_MODEL" = "my-custom:latest" ]
}

# =============================================================================
# Group 5: Non-interactive defaults by RAM (WIZ-02, WIZ-03)
# =============================================================================

@test "non-interactive defaults to RAM-appropriate model for 8GB" {
    export DETECTED_RAM_GB=8
    run_wizard
    [ "$WIZARD_LLM_MODEL" = "gemma3:4b" ]
}

@test "non-interactive defaults to RAM-appropriate model for 64GB" {
    export DETECTED_RAM_GB=64
    run_wizard
    [ "$WIZARD_LLM_MODEL" = "gemma3:27b" ]
}

@test "non-interactive defaults to RAM-appropriate model for 96GB" {
    export DETECTED_RAM_GB=96
    run_wizard
    [ "$WIZARD_LLM_MODEL" = "qwen2.5:72b" ]
}

@test "non-interactive defaults to RAM-appropriate model for 16GB" {
    export DETECTED_RAM_GB=16
    run_wizard
    [ "$WIZARD_LLM_MODEL" = "qwen2.5:7b" ]
}

# =============================================================================
# Group 6: Interactive functions via piped input (WIZ-01)
# =============================================================================

@test "interactive _wizard_ask reads choice via stdin" {
    result=$(printf "2\n" | _wizard_ask "Pick one:" 1 "alpha" "beta" "gamma")
    [ "$result" = "beta" ]
}

@test "interactive _wizard_ask uses default on empty input" {
    result=$(printf "\n" | _wizard_ask "Pick one:" 2 "alpha" "beta" "gamma")
    [ "$result" = "beta" ]
}

@test "interactive _wizard_ask handles first option" {
    result=$(printf "1\n" | _wizard_ask "Pick one:" 2 "alpha" "beta" "gamma")
    [ "$result" = "alpha" ]
}

@test "interactive _wizard_ask handles last option" {
    result=$(printf "3\n" | _wizard_ask "Pick one:" 1 "alpha" "beta" "gamma")
    [ "$result" = "gamma" ]
}

@test "interactive _wizard_ask_profile returns lan for choice 1" {
    result=$(printf "1\n" | _wizard_ask_profile)
    [ "$result" = "lan" ]
}

@test "interactive _wizard_ask_profile returns offline for choice 2" {
    result=$(printf "2\n" | _wizard_ask_profile)
    [ "$result" = "offline" ]
}

@test "interactive run_wizard calls all 7 questions with defaults" {
    export NON_INTERACTIVE=0
    local tmpdir="${BATS_TEST_TMPDIR}"
    # Pipe 7 newlines to accept all defaults
    # Check wizard's log output for the summary (pipe causes subshell, so vars are lost)
    run /bin/bash -c "
        set +u
        cd '${PROJECT_ROOT}'
        export AGMIND_DIR='${tmpdir}/agmind_interactive'
        export AGMIND_LOG_DIR='${tmpdir}/agmind_interactive/logs'
        export LOG_FILE='${tmpdir}/agmind_interactive/logs/install.log'
        export STATE_FILE='${tmpdir}/agmind_interactive/.install-state'
        mkdir -p \"\${AGMIND_DIR}\" \"\${AGMIND_LOG_DIR}\"
        touch \"\${LOG_FILE}\" \"\${STATE_FILE}\"
        source lib/common.sh
        DETECTED_RAM_GB=32
        source lib/wizard.sh
        NON_INTERACTIVE=0
        printf '\n\n\n\n\n\n\n' | run_wizard
    " 2>&1
    assert_success
    # Verify all 7 choices are logged in the configuration summary
    assert_output --partial "Profile:    lan"
    assert_output --partial "LLM:        qwen2.5:14b"
    assert_output --partial "Embedding:  nomic-embed-text"
    assert_output --partial "Vector DB:  weaviate"
    assert_output --partial "ETL:        standard"
    assert_output --partial "Monitoring: none"
    assert_output --partial "Backup:     local"
}

@test "LLM model menu shows recommended marker" {
    export NON_INTERACTIVE=0
    # Menu output goes to stderr, so redirect stderr to stdout to capture it
    run /bin/bash -c "
        set +u
        cd '${PROJECT_ROOT}'
        export AGMIND_DIR='${BATS_TEST_TMPDIR}/agmind'
        export AGMIND_LOG_DIR='\${AGMIND_DIR}/logs'
        export LOG_FILE='\${AGMIND_LOG_DIR}/install.log'
        export STATE_FILE='\${AGMIND_DIR}/.install-state'
        mkdir -p \"\${AGMIND_DIR}\" \"\${AGMIND_LOG_DIR}\"
        touch \"\${LOG_FILE}\" \"\${STATE_FILE}\"
        source lib/common.sh
        DETECTED_RAM_GB=32
        source lib/wizard.sh
        printf '\n' | _wizard_ask_llm_model 2>&1
    "
    assert_success
    assert_output --partial "recommended"
}

@test "LLM model menu shows RAM requirement warning for models above system RAM" {
    export NON_INTERACTIVE=0
    # Menu output goes to stderr, so redirect stderr to stdout to capture it
    run /bin/bash -c "
        set +u
        cd '${PROJECT_ROOT}'
        export AGMIND_DIR='${BATS_TEST_TMPDIR}/agmind'
        export AGMIND_LOG_DIR='\${AGMIND_DIR}/logs'
        export LOG_FILE='\${AGMIND_LOG_DIR}/install.log'
        export STATE_FILE='\${AGMIND_DIR}/.install-state'
        mkdir -p \"\${AGMIND_DIR}\" \"\${AGMIND_LOG_DIR}\"
        touch \"\${LOG_FILE}\" \"\${STATE_FILE}\"
        source lib/common.sh
        DETECTED_RAM_GB=32
        source lib/wizard.sh
        printf '\n' | _wizard_ask_llm_model 2>&1
    "
    assert_success
    assert_output --partial "requires"
    assert_output --partial "you have 32GB"
}

# =============================================================================
# Group 7: WIZARD_* export verification (WIZ-04)
# =============================================================================

@test "all 7 WIZARD_* variables are exported after wizard completes" {
    run_wizard
    # Verify all variables are set and non-empty
    [ -n "$WIZARD_DEPLOY_PROFILE" ]
    [ -n "$WIZARD_LLM_MODEL" ]
    [ -n "$WIZARD_EMBED_MODEL" ]
    [ -n "$WIZARD_VECTOR_DB" ]
    [ -n "$WIZARD_ETL_MODE" ]
    [ -n "$WIZARD_MONITORING_MODE" ]
    [ -n "$WIZARD_BACKUP_MODE" ]
}

@test "WIZARD_* variables are exported (available in subshell)" {
    run_wizard
    # Run in subshell to verify export
    result=$(bash -c 'echo "${WIZARD_DEPLOY_PROFILE}:${WIZARD_LLM_MODEL}:${WIZARD_VECTOR_DB}"')
    [ "$result" = "lan:qwen2.5:14b:weaviate" ]
}
