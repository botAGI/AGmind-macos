#!/bin/bash
# lib/common.sh -- AGMind common utilities
# Sourced by all lib/*.sh modules and install.sh
# Compatible with /bin/bash 3.2.57 (stock macOS)
#
# Provides: Logging, error handling, _atomic_sed, idempotency, die()
# Exports: log_info, log_warn, log_error, log_step, log_debug,
#          die, _atomic_sed, _mark_phase_done, _is_phase_done,
#          ensure_directory, _error_handler, _strip_ansi

set -eEuo pipefail

# =============================================================================
# Constants
# =============================================================================

readonly AGMIND_VERSION="1.0.0"
readonly AGMIND_DIR="${AGMIND_DIR:-/opt/agmind}"
readonly AGMIND_LOG_DIR="${AGMIND_LOG_DIR:-${AGMIND_DIR}/logs}"
readonly LOG_FILE="${LOG_FILE:-${AGMIND_LOG_DIR}/install.log}"
readonly STATE_FILE="${STATE_FILE:-${AGMIND_DIR}/.install-state}"

# =============================================================================
# ANSI Colors (generated as actual escape bytes via printf, NOT literal \033)
# =============================================================================

readonly _RED=$(printf "\033[0;31m")
readonly _GREEN=$(printf "\033[0;32m")
readonly _YELLOW=$(printf "\033[0;33m")
readonly _CYAN=$(printf "\033[0;36m")
readonly _BOLD=$(printf "\033[1m")
readonly _NC=$(printf "\033[0m")

# =============================================================================
# Verbosity
# =============================================================================

VERBOSE="${VERBOSE:-0}"

# =============================================================================
# Log Rotation
# =============================================================================
# On each fresh run, rotate the previous log file (one backup kept).
# Gracefully skip if log directory does not exist yet.

if [[ -d "$AGMIND_LOG_DIR" ]] && [[ -s "$LOG_FILE" ]]; then
    mv -f "$LOG_FILE" "${LOG_FILE}.prev"
fi

# =============================================================================
# ANSI Stripping (for log file output)
# =============================================================================

_strip_ansi() {
    /usr/bin/sed -E "s/$(printf "\033")\[[0-9;]*m//g"
}

# =============================================================================
# Logging Functions
# =============================================================================

# Internal helper: prints colored line to stdout, appends stripped line to log file
_log() {
    local color="$1" label="$2" msg="$3"
    local ts
    ts=$(date "+%Y-%m-%d %H:%M:%S")
    local line="${color}[${label}]${_NC}  ${msg}"
    printf "%s\n" "$line"
    if [[ -d "$AGMIND_LOG_DIR" ]]; then
        printf "[%s] [%s] %s\n" "$ts" "$label" "$msg" >> "$LOG_FILE"
    fi
}

log_info()  { _log "$_GREEN"  "INFO"  "$1"; }
log_warn()  { _log "$_YELLOW" "WARN"  "$1"; }
log_error() { _log "$_RED"    "ERROR" "$1"; }

log_debug() {
    if [[ "$VERBOSE" -eq 1 ]]; then
        _log "" "DEBUG" "$1"
    fi
    return 0
}

log_step() {
    local num="$1" name="$2"
    local banner="${_CYAN}${_BOLD}═══ Phase ${num}: ${name} ═══${_NC}"
    printf "\n%s\n\n" "$banner"
    if [[ -d "$AGMIND_LOG_DIR" ]]; then
        printf "\n[%s] ═══ Phase %s: %s ═══\n\n" \
            "$(date "+%Y-%m-%d %H:%M:%S")" "$num" "$name" >> "$LOG_FILE"
    fi
}

# =============================================================================
# Error Handling
# =============================================================================

_error_handler() {
    local exit_code=$?
    local line_no="${1:-unknown}"
    local bash_cmd="${BASH_COMMAND:-unknown}"
    local func_name="${FUNCNAME[1]:-main}"
    local source_file="${BASH_SOURCE[1]:-unknown}"
    log_error "Command '${bash_cmd}' failed (exit ${exit_code}) in ${source_file}:${func_name} line ${line_no}"
}
trap '_error_handler $LINENO' ERR

# =============================================================================
# die() -- Fatal error with optional remediation hint
# =============================================================================

die() {
    local msg="$1"
    local hint="${2:-}"
    log_error "$msg"
    if [[ -n "$hint" ]]; then
        printf "  ${_YELLOW}Hint:${_NC} %s\n" "$hint" >&2
    fi
    exit 1
}

# =============================================================================
# BSD sed Wrapper
# =============================================================================
# Always uses -i '' (no backup) and -E (extended regex, not -r).
# Uses /usr/bin/sed explicitly to avoid any brew-installed GNU sed.

_atomic_sed() {
    local pattern="$1"
    local file="$2"
    if [[ ! -f "$file" ]]; then
        die "File not found: $file" "Check that the file exists before calling _atomic_sed"
    fi
    /usr/bin/sed -i '' -E "$pattern" "$file"
}

# =============================================================================
# Idempotency Helpers
# =============================================================================

_mark_phase_done() {
    local phase="$1"
    echo "$phase" >> "$STATE_FILE"
}

_is_phase_done() {
    local phase="$1"
    grep -qxF "$phase" "$STATE_FILE" 2>/dev/null
}

# =============================================================================
# Directory Helpers
# =============================================================================

ensure_directory() {
    local dir="$1"
    if [[ -d "$dir" ]]; then
        log_debug "Directory already exists: $dir"
        return 0
    fi
    sudo mkdir -p "$dir"
    log_info "Created directory: $dir"
}
