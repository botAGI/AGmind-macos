#!/bin/bash
# lib/models.sh -- AGMind Ollama model management
# Sourced by install.sh for Phase 8 (Models)
# Compatible with /bin/bash 3.2.57 (stock macOS)
#
# Provides: Ollama model pull with idempotency
# Exports: phase_8_models
#
# Depends on: lib/common.sh (log_info, die, LOG_FILE)

set -eEuo pipefail

# =============================================================================
# Idempotent Model Pull
# =============================================================================
# Checks if model is already present via `ollama list`, skips if so.
# On pull, passes through stdout for progress display and tees to log file.

_pull_model_if_needed() {
    local model="$1"

    # Capture model list to variable first (avoids SIGPIPE with pipefail)
    local model_list
    model_list=$(ollama list 2>/dev/null) || true

    # SEC-06: Use fixed-string grep to avoid regex injection from model name
    if echo "$model_list" | grep -qF "$model"; then
        log_info "Model ${model} already present -- skipping pull"
        return 0
    fi

    log_info "Pulling model: ${model} (this may take a while)..."
    # Capture pull output and exit code explicitly to avoid pipefail/subshell issues
    local pull_output
    local pull_rc=0
    pull_output=$(ollama pull "$model" 2>&1) || pull_rc=$?
    printf "%s\n" "$pull_output" | tee -a "$LOG_FILE"
    if [ "$pull_rc" -ne 0 ]; then
        die "Failed to pull model: ${model}" "Check: ollama pull ${model}"
    fi
    log_info "Model ${model} pulled successfully"
}

# =============================================================================
# Phase 8 Entry Point
# =============================================================================
# Pulls LLM and embedding models specified by the wizard.
# WIZARD_LLM_MODEL and WIZARD_EMBED_MODEL are exported globals from wizard.sh.

phase_8_models() {
    _pull_model_if_needed "$WIZARD_LLM_MODEL"
    _pull_model_if_needed "$WIZARD_EMBED_MODEL"

    log_info "All models ready"
}
