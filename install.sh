#!/bin/bash
# install.sh -- AGMind macOS Installer Orchestrator
# Runs 9 installation phases in sequence
# Compatible with /bin/bash 3.2.57 (stock macOS)

set -eEuo pipefail
umask 077

# =============================================================================
# Script directory resolution
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# =============================================================================
# Early dry-run detection (must set AGMIND_DIR BEFORE sourcing common.sh
# because common.sh makes it readonly)
# =============================================================================

_EARLY_DRY_RUN=0
for _arg in "$@"; do
    [ "$_arg" = "--dry-run" ] && _EARLY_DRY_RUN=1
done
if [ "$_EARLY_DRY_RUN" = "1" ]; then
    _DRY_RUN_DIR=$(mktemp -d)
    export AGMIND_DIR="$_DRY_RUN_DIR"
    export AGMIND_LOG_DIR="${_DRY_RUN_DIR}/logs"
    export LOG_FILE="${_DRY_RUN_DIR}/logs/install.log"
    export STATE_FILE="${_DRY_RUN_DIR}/.install-state"
    mkdir -p "${_DRY_RUN_DIR}/logs"
fi

# Source common utilities
source "${SCRIPT_DIR}/lib/common.sh"

# Source detection module
source "${SCRIPT_DIR}/lib/detect.sh"

# Source wizard module
source "${SCRIPT_DIR}/lib/wizard.sh"

# Source docker module
source "${SCRIPT_DIR}/lib/docker.sh"

# Source ollama module
source "${SCRIPT_DIR}/lib/ollama.sh"

# Source config module
source "${SCRIPT_DIR}/lib/config.sh"

# Source deployment modules
source "${SCRIPT_DIR}/lib/compose.sh"
source "${SCRIPT_DIR}/lib/health.sh"
source "${SCRIPT_DIR}/lib/models.sh"
source "${SCRIPT_DIR}/lib/openwebui.sh"

# Source backup/LaunchAgent module
source "${SCRIPT_DIR}/lib/backup.sh"

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
  --dry-run           Show what would happen without making changes
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
DRY_RUN="${DRY_RUN:-0}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --verbose)         VERBOSE=1 ;;
        --non-interactive) NON_INTERACTIVE=1 ;;
        --dry-run)         DRY_RUN=1; NON_INTERACTIVE=1; VERBOSE=1 ;;
        --force-phase)
            [[ $# -lt 2 ]] && die "Missing argument for --force-phase" "Usage: --force-phase N"
            FORCE_PHASE="$2"; shift ;;
        --help|-h)         show_usage; exit 0 ;;
        *)                 die "Unknown option: $1" "Run with --help for usage" ;;
    esac
    shift
done

# =============================================================================
# Dry-Run Mode
# =============================================================================

if [ "$DRY_RUN" = "1" ]; then
    # _DRY_RUN_DIR and AGMIND_DIR already set in early detection block above
    HOME="$_DRY_RUN_DIR"

    # Override commands that would modify the system
    sudo() { "$@" 2>/dev/null || true; }
    docker() {
        case "$1" in
            info) echo "Server Version: 29.0.0 (dry-run)" ;;
            compose)
                shift; case "$1" in
                    version) echo "Docker Compose version v2.30.0 (dry-run)" ;;
                    up) log_info "[DRY-RUN] docker compose up $*" ;;
                    ps) [ "${2:-}" = "-q" ] && echo "dry-run-id" || [ "${2:-}" = "--services" ] && printf "api\nworker\nweb\ndb_postgres\nredis\nnginx\n" || echo "" ;;
                    *) log_info "[DRY-RUN] docker compose $*" ;;
                esac ;;
            inspect) case "$*" in *Health*) echo "healthy" ;; *State*) echo "running" ;; *) echo "healthy" ;; esac ;;
            *) log_info "[DRY-RUN] docker $*" ;;
        esac
    }
    brew() {
        case "$1" in
            --prefix) echo "/opt/homebrew" ;;
            install) log_info "[DRY-RUN] brew install $*" ;;
            services) log_info "[DRY-RUN] brew services $*" ;;
            info) [ "${3:-}" = "--json" ] && echo '[{"installed":[{"version":"0.17.0"}]}]' ;;
            *) log_info "[DRY-RUN] brew $*" ;;
        esac
    }
    ollama() {
        case "$1" in
            --version) echo "ollama version 0.17.0 (dry-run)" ;;
            pull) log_info "[DRY-RUN] ollama pull $2" ;;
            list) echo "NAME SIZE" ;;
            *) log_info "[DRY-RUN] ollama $*" ;;
        esac
    }
    curl() {
        for arg in "$@"; do
            case "$arg" in
                */api/v1/auths/signup*) echo '{"id":"dry-run"}'; return 0 ;;
                http://localhost/) echo "OK"; return 0 ;;
                *11434*) echo '{"models":[]}'; return 0 ;;
            esac
        done
        echo "dry-run-ok"; return 0
    }
    launchctl() { log_info "[DRY-RUN] launchctl $*"; }
    plutil() { echo "$2: OK"; }
    ipconfig() { echo "192.168.1.100"; }
    sleep() { :; }

    # Export overrides so subshells see them
    export -f sudo docker brew ollama curl launchctl plutil ipconfig sleep 2>/dev/null || true

    # Set detection vars and create fake socket
    export DOCKER_RUNTIME=desktop
    export DETECTED_ARCH=arm64
    export DETECTED_RAM_GB=24
    mkdir -p "${_DRY_RUN_DIR}/.docker/run" "${_DRY_RUN_DIR}/Library/LaunchAgents"
    python3 -c "import socket,os; s=socket.socket(socket.AF_UNIX); p='${_DRY_RUN_DIR}/.docker/run/docker.sock'; s.bind(p)" 2>/dev/null || true

    log_info "${_CYAN}${_BOLD}DRY-RUN MODE${_NC} — no system changes will be made"
    log_info "Temp directory: ${_DRY_RUN_DIR}"
fi

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

phase_2_wizard() {
    run_wizard
}

phase_3_prerequisites() {
    detect_docker_runtime
    if [ "$DOCKER_RUNTIME" = "none" ]; then
        install_colima
        start_colima
        detect_docker_runtime  # re-detect after install
    fi
    fix_docker_socket
    setup_compose_plugin
    verify_compose
    log_info "Docker runtime ready: ${DOCKER_RUNTIME}"
}

phase_4_ollama() {
    install_ollama
    start_ollama
    log_info "Ollama setup complete"
}

# phase_6_start, phase_7_health, phase_8_models are defined in their
# respective lib modules (compose.sh, health.sh, models.sh).

phase_9_complete() {
    # Install LaunchAgents for scheduled backup and health checks
    _install_launch_agents

    # Install CLI tool
    sudo cp "${SCRIPT_DIR}/scripts/agmind.sh" "${AGMIND_DIR}/scripts/agmind.sh"
    sudo chown "$(whoami)" "${AGMIND_DIR}/scripts/agmind.sh"
    chmod +x "${AGMIND_DIR}/scripts/agmind.sh"
    if sudo ln -sf "${AGMIND_DIR}/scripts/agmind.sh" /usr/local/bin/agmind 2>/dev/null; then
        log_info "CLI installed: /usr/local/bin/agmind"
    else
        log_warn "Could not create /usr/local/bin/agmind symlink"
        log_warn "Add ${AGMIND_DIR}/scripts to your PATH, or run: sudo ln -sf ${AGMIND_DIR}/scripts/agmind.sh /usr/local/bin/agmind"
    fi

    # Verify Open WebUI is accessible (includes POST signup fallback)
    _verify_openwebui_admin

    # Determine LaunchAgent status for summary
    local backup_agent_status="not loaded"
    local health_agent_status="not loaded"
    if launchctl list com.agmind.backup >/dev/null 2>&1; then
        backup_agent_status="loaded"
    fi
    if launchctl list com.agmind.health >/dev/null 2>&1; then
        health_agent_status="loaded"
    fi

    # Print final summary
    local ip_addr
    ip_addr=$(ipconfig getifaddr en0 2>/dev/null || echo "localhost")

    printf "\n"
    printf "%s\n" "${_CYAN}${_BOLD}═══════════════════════════════════════════${_NC}"
    printf "%s\n" "${_CYAN}${_BOLD}  AGMind Installation Complete${_NC}"
    printf "%s\n" "${_CYAN}${_BOLD}═══════════════════════════════════════════${_NC}"
    printf "\n"
    printf "%s\n" "${_GREEN}Service URLs:${_NC}"
    printf "  %-20s %s\n" "Open WebUI:" "http://${ip_addr}/"
    printf "  %-20s %s\n" "Dify Console:" "http://${ip_addr}/apps/"
    printf "  %-20s %s\n" "Ollama API:" "http://localhost:11434"
    printf "\n"
    printf "%s\n" "${_GREEN}Credentials:${_NC}"
    printf "  %-20s %s\n" "File:" "${AGMIND_DIR}/credentials.txt"
    printf "  %-20s %s\n" "Admin Email:" "admin@agmind.local"
    printf "  %-20s %s\n" "Admin Password:" "(see credentials.txt)"
    printf "\n"
    printf "%s\n" "${_GREEN}LaunchAgent Status:${_NC}"
    printf "  %-20s %s\n" "Backup (daily 3AM):" "${backup_agent_status}"
    printf "  %-20s %s\n" "Health (every 60s):" "${health_agent_status}"
    printf "\n"
    printf "%s\n" "${_GREEN}CLI Commands:${_NC}"
    printf "  %-20s %s\n" "agmind status" "Show all service status"
    printf "  %-20s %s\n" "agmind doctor" "Run health checks"
    printf "  %-20s %s\n" "agmind stop" "Stop all services"
    printf "  %-20s %s\n" "agmind start" "Start all services"
    printf "\n"
    log_info "Installation complete"
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

printf "\n"
log_info "Phases run: ${PHASES_RAN}, skipped: ${PHASES_SKIPPED}, total time: ${ELAPSED}s"
log_info "Log file: ${LOG_FILE}"
