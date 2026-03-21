#!/usr/bin/env bats
# tests/unit/test_models.bats -- Tests for lib/models.sh
# Covers: DEPLOY-04
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
    source "${PROJECT_ROOT}/lib/models.sh"
    trap - ERR

    # Default wizard model selections
    export WIZARD_LLM_MODEL="qwen2.5:14b"
    export WIZARD_EMBED_MODEL="nomic-embed-text"

    # Default mock config
    export MOCK_OLLAMA_MODELS=""
    export MOCK_OLLAMA_PULL="ok"
}

# =============================================================================
# DEPLOY-04: _pull_model_if_needed
# =============================================================================

@test "DEPLOY-04: _pull_model_if_needed skips existing model" {
    export MOCK_OLLAMA_MODELS="qwen2.5:14b"
    run _pull_model_if_needed "qwen2.5:14b"
    assert_success
    assert_output --partial "already present"
}

@test "DEPLOY-04: _pull_model_if_needed pulls missing model" {
    export MOCK_OLLAMA_MODELS=""
    export MOCK_OLLAMA_PULL="ok"
    run _pull_model_if_needed "qwen2.5:14b"
    assert_success
    assert_output --partial "Pulling"
}

@test "DEPLOY-04: _pull_model_if_needed fails on pull error" {
    export MOCK_OLLAMA_MODELS=""
    export MOCK_OLLAMA_PULL="fail"
    run _pull_model_if_needed "badmodel"
    assert_failure
}

@test "DEPLOY-04: phase_8_models pulls both LLM and embed models" {
    export MOCK_OLLAMA_MODELS=""
    export MOCK_OLLAMA_PULL="ok"
    run phase_8_models
    assert_success
    assert_output --partial "qwen2.5:14b"
    assert_output --partial "nomic-embed-text"
}

@test "DEPLOY-04: phase_8_models skips when both models present" {
    export MOCK_OLLAMA_MODELS="qwen2.5:14b,nomic-embed-text"
    run phase_8_models
    assert_success
    assert_output --partial "already present"
}
