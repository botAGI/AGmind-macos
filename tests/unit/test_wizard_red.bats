#!/usr/bin/env bats
# tests/unit/test_wizard_red.bats -- RED phase test for lib/wizard.sh
# Minimal tests to verify core wizard behaviors before full test suite

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

    export DETECTED_RAM_GB=32
    export DETECTED_ARCH="arm64"
    export NON_INTERACTIVE=1

    unset DEPLOY_PROFILE LLM_MODEL EMBED_MODEL VECTOR_DB ETL_MODE MONITORING_MODE BACKUP_MODE
    unset WIZARD_DEPLOY_PROFILE WIZARD_LLM_MODEL WIZARD_EMBED_MODEL WIZARD_VECTOR_DB
    unset WIZARD_ETL_MODE WIZARD_MONITORING_MODE WIZARD_BACKUP_MODE
}

@test "non-interactive mode exports all 7 WIZARD_* variables with defaults" {
    run_wizard
    [ "$WIZARD_DEPLOY_PROFILE" = "lan" ]
    [ "$WIZARD_LLM_MODEL" = "qwen2.5:14b" ]
    [ "$WIZARD_EMBED_MODEL" = "nomic-embed-text" ]
    [ "$WIZARD_VECTOR_DB" = "weaviate" ]
    [ "$WIZARD_ETL_MODE" = "standard" ]
    [ "$WIZARD_MONITORING_MODE" = "none" ]
    [ "$WIZARD_BACKUP_MODE" = "local" ]
}

@test "_get_recommended_model returns qwen2.5:14b for 32GB" {
    run _get_recommended_model 32
    assert_success
    assert_output "qwen2.5:14b"
}

@test "_get_recommended_model returns gemma3:4b for 8GB" {
    run _get_recommended_model 8
    assert_success
    assert_output "gemma3:4b"
}

@test "_get_recommended_model returns qwen2.5:72b for 96GB" {
    run _get_recommended_model 96
    assert_success
    assert_output "qwen2.5:72b"
}

@test "_validate_choice accepts valid choice" {
    run _validate_choice "TEST" "lan" "lan" "offline"
    assert_success
}

@test "_validate_choice rejects invalid choice" {
    run _validate_choice "TEST" "bogus" "lan" "offline"
    assert_failure
    assert_output --partial "Invalid TEST"
}

@test "non-interactive dies on invalid DEPLOY_PROFILE" {
    export DEPLOY_PROFILE="bogus"
    run run_wizard
    assert_failure
    assert_output --partial "Invalid DEPLOY_PROFILE"
}
