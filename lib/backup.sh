#!/bin/bash
# lib/backup.sh -- AGMind LaunchAgent management
# Sourced by install.sh for Phase 9 (Complete)
# Compatible with /bin/bash 3.2.57 (stock macOS)
#
# Provides: LaunchAgent plist rendering, validation, and loading
# Exports: _install_launch_agents
#
# Depends on: lib/common.sh (log_info, log_warn, die, ensure_directory, AGMIND_DIR)

set -eEuo pipefail

# Resolve SCRIPT_DIR: available from install.sh, fallback for standalone sourcing
SCRIPT_DIR="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# =============================================================================
# Internal: Load a LaunchAgent via launchctl
# =============================================================================
# Uses modern `launchctl bootstrap` with legacy `launchctl load` fallback.
# Idempotent: skips if the agent is already loaded.
#
# Arguments:
#   $1  Full path to the .plist file

_load_launch_agent() {
    local plist="$1"
    local label
    label=$(basename "$plist" .plist)

    # Idempotent: check if already loaded
    if launchctl list "$label" >/dev/null 2>&1; then
        log_info "LaunchAgent ${label} already loaded -- skipping"
        return 0
    fi

    # Try modern bootstrap first (macOS 10.10+, required on Ventura+)
    local uid
    uid=$(id -u)
    if launchctl bootstrap "gui/${uid}" "$plist" 2>/dev/null; then
        log_info "LaunchAgent ${label} loaded (bootstrap)"
        return 0
    fi

    # Fallback to legacy load (deprecated but still functional)
    if launchctl load "$plist" 2>/dev/null; then
        log_info "LaunchAgent ${label} loaded (legacy)"
        return 0
    fi

    # Both methods failed
    log_warn "Failed to load LaunchAgent ${label}"
    log_warn "Try manually: launchctl load ${plist}"
}

# =============================================================================
# Internal: Install a plist template to ~/Library/LaunchAgents/
# =============================================================================
# Copies the template to the LaunchAgents directory and validates it
# with plutil -lint.
#
# Arguments:
#   $1  Source template path
#   $2  Destination plist filename (e.g., com.agmind.backup.plist)

_install_plist() {
    local template="$1"
    local filename="$2"
    local dest="${HOME}/Library/LaunchAgents/${filename}"

    ensure_directory "${HOME}/Library/LaunchAgents"

    cp "$template" "$dest"

    if ! plutil -lint "$dest" >/dev/null 2>&1; then
        die "Invalid plist: ${dest}" "Check template: ${template}"
    fi

    log_info "Installed plist: ${dest}"
}

# =============================================================================
# Exported: Install and load all LaunchAgents
# =============================================================================
# Copies helper scripts to /opt/agmind/scripts/, installs plist templates
# to ~/Library/LaunchAgents/, validates them, and loads via launchctl.
# Called by phase_9_complete in install.sh.

_install_launch_agents() {
    # Ensure target directories exist
    ensure_directory "${AGMIND_DIR}/scripts"
    ensure_directory "${AGMIND_DIR}/logs"

    # Copy helper scripts to install directory
    sudo cp "${SCRIPT_DIR}/scripts/backup.sh" "${AGMIND_DIR}/scripts/backup.sh"
    sudo cp "${SCRIPT_DIR}/scripts/health-gen.sh" "${AGMIND_DIR}/scripts/health-gen.sh"
    sudo chown "$(whoami)" "${AGMIND_DIR}/scripts/backup.sh" "${AGMIND_DIR}/scripts/health-gen.sh"
    chmod +x "${AGMIND_DIR}/scripts/backup.sh" "${AGMIND_DIR}/scripts/health-gen.sh"

    # Install plist templates
    _install_plist "${SCRIPT_DIR}/templates/launchd/com.agmind.backup.plist.template" "com.agmind.backup.plist"
    _install_plist "${SCRIPT_DIR}/templates/launchd/com.agmind.health.plist.template" "com.agmind.health.plist"

    # Load both LaunchAgents
    _load_launch_agent "${HOME}/Library/LaunchAgents/com.agmind.backup.plist"
    _load_launch_agent "${HOME}/Library/LaunchAgents/com.agmind.health.plist"

    log_info "LaunchAgents installed and loaded"
}
