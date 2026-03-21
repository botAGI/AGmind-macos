#!/bin/bash
# install.sh -- AGMind macOS Installer Orchestrator
# Runs 9 installation phases in sequence
# Compatible with /bin/bash 3.2.57 (stock macOS)

set -eEuo pipefail

# =============================================================================
# Script directory resolution
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source common utilities
source "${SCRIPT_DIR}/lib/common.sh"

# Source detection module
source "${SCRIPT_DIR}/lib/detect.sh"

# =============================================================================
# Defaults for optional variables (must be set before arg parsing due to set -u)
# =============================================================================

NON_INTERACTIVE="${NON_INTERACTIVE:-0}"
SKIP_PREFLIGHT="${SKIP_PREFLIGHT:-0}"

# =============================================================================
# Usage / Help
# =============================================================================

show_usage() {
    cat <<EOF
Usage: bash install.sh [OPTIONS]

AGMind macOS Installer -- deploys a local AI RAG stack on macOS.

Options:
  --verbose           Enable debug-level output
  --non-interactive   Skip all prompts (read from env vars)
  --force-phase N     Re-run phase N even if already complete
  --help, -h          Show this help

Environment Variables:
  DEPLOY_PROFILE      lan|offline (default: lan)
  NON_INTERACTIVE     0|1 (same as --non-interactive)
  VERBOSE             0|1 (same as --verbose)
  SKIP_PREFLIGHT      0|1 (skip preflight checks)
EOF
}

# =============================================================================
# Argument Parsing (while-case loop, NOT getopts)
# =============================================================================

FORCE_PHASE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose)         VERBOSE=1 ;;
        --non-interactive) NON_INTERACTIVE=1 ;;
        --force-phase)
            [[ $# -lt 2 ]] && die "Missing argument for --force-phase" "Usage: --force-phase N"
            FORCE_PHASE="$2"; shift ;;
        --help|-h)         show_usage; exit 0 ;;
        *)                 die "Unknown option: $1" "Run with --help for usage" ;;
    esac
    shift
done

# =============================================================================
# Bootstrap: ensure directories exist
# =============================================================================

ensure_directory "$AGMIND_DIR"
ensure_directory "$AGMIND_LOG_DIR"
sudo chown -R "$(whoami)" "$AGMIND_DIR"
touch "$LOG_FILE"
touch "$STATE_FILE"

# =============================================================================
# Phase Definitions (indexed array of "num:Name" strings)
# =============================================================================
# These are the 9 installer phases from the spec (not the 7 project phases).

PHASE_NAMES=(
    "1:Diagnostics"
    "2:Wizard"
    "3:Prerequisites"
    "4:Ollama Setup"
    "5:Configuration"
    "6:Start"
    "7:Health"
    "8:Models"
    "9:Complete"
)

# =============================================================================
# Timing
# =============================================================================

INSTALL_START=$(date +%s)
PHASES_RAN=0
PHASES_SKIPPED=0

# =============================================================================
# Phase Runner
# =============================================================================

run_phase() {
    local num="$1" name="$2" func="$3"
    local phase_key="phase_${num}"

    # Check force-phase override
    if [[ "$FORCE_PHASE" == "$num" ]]; then
        log_info "Force re-running phase ${num}"
    elif _is_phase_done "$phase_key"; then
        log_info "[SKIP] Phase ${num}: ${name} -- already complete"
        PHASES_SKIPPED=$((PHASES_SKIPPED + 1))
        return 0
    fi

    log_step "$num" "$name"

    # Check if function exists
    if type "$func" >/dev/null 2>&1; then
        "$func"
        _mark_phase_done "$phase_key"
        PHASES_RAN=$((PHASES_RAN + 1))
    else
        log_warn "[SKIP] Phase ${num}: ${name} -- not yet implemented"
        PHASES_SKIPPED=$((PHASES_SKIPPED + 1))
    fi
}

# =============================================================================
# Phase Functions
# =============================================================================

phase_1_diagnostics() {
    preflight_checks
}

# =============================================================================
# Execute All 9 Phases
# =============================================================================

run_phase 1 "Diagnostics"    "phase_1_diagnostics"
run_phase 2 "Wizard"         "phase_2_wizard"
run_phase 3 "Prerequisites"  "phase_3_prerequisites"
run_phase 4 "Ollama Setup"   "phase_4_ollama"
run_phase 5 "Configuration"  "phase_5_configuration"
run_phase 6 "Start"          "phase_6_start"
run_phase 7 "Health"         "phase_7_health"
run_phase 8 "Models"         "phase_8_models"
run_phase 9 "Complete"       "phase_9_complete"

# =============================================================================
# Final Summary (always printed)
# =============================================================================

INSTALL_END=$(date +%s)
ELAPSED=$((INSTALL_END - INSTALL_START))

printf "\n%s\n" "${_CYAN}${_BOLD}═══ Installation Summary ═══${_NC}"
log_info "Phases run: ${PHASES_RAN}"
log_info "Phases skipped: ${PHASES_SKIPPED}"
log_info "Total time: ${ELAPSED}s"
log_info "Log file: ${LOG_FILE}"
