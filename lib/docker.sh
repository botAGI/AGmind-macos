#!/bin/bash
# lib/docker.sh -- AGMind Docker runtime management
# Sourced by install.sh for Phase 3 (Prerequisites)
# Compatible with /bin/bash 3.2.57 (stock macOS)
#
# Provides: Docker runtime detection, Colima install/start, socket fix,
#           Docker Compose v2 verification
# Exports: detect_docker_runtime, install_colima, start_colima,
#          fix_docker_socket, verify_compose, setup_compose_plugin
#
# Internal: _get_socket_path
#
# Depends on: lib/common.sh (log_info, log_warn, log_error, log_debug, die)
#             lib/detect.sh (DETECTED_ARCH, BREW_PREFIX, DOCKER_RUNTIME globals)

set -eEuo pipefail

# =============================================================================
# Docker Runtime Detection
# =============================================================================
# Detects whether Docker Desktop or Colima is the active Docker runtime.
# Prefers Docker Desktop when both respond.
# Respects DOCKER_RUNTIME env var override (DOCKER-06).

detect_docker_runtime() {
    # Env override (DOCKER-06)
    if [ -n "${DOCKER_RUNTIME:-}" ]; then
        log_debug "Docker runtime override: ${DOCKER_RUNTIME}"
        export DOCKER_RUNTIME
        return 0
    fi

    local desktop_socket="${HOME}/.docker/run/docker.sock"
    local colima_socket="${HOME}/.colima/default/docker.sock"

    # Prefer Docker Desktop if both respond
    if DOCKER_HOST="unix://${desktop_socket}" docker info >/dev/null 2>&1; then
        DOCKER_RUNTIME="desktop"
    elif DOCKER_HOST="unix://${colima_socket}" docker info >/dev/null 2>&1; then
        DOCKER_RUNTIME="colima"
    else
        DOCKER_RUNTIME="none"
    fi

    export DOCKER_RUNTIME
    log_info "Docker runtime detected: ${DOCKER_RUNTIME}"
}

# =============================================================================
# Docker Compose CLI Plugin Configuration
# =============================================================================
# Ensures Docker CLI can find the brew-installed docker-compose plugin.
# Creates or updates ~/.docker/config.json with cliPluginsExtraDirs.

setup_compose_plugin() {
    local docker_dir="${HOME}/.docker"
    local config_file="${docker_dir}/config.json"
    local plugins_dir="${BREW_PREFIX:-/opt/homebrew}/lib/docker/cli-plugins"

    mkdir -p "$docker_dir"

    if [ ! -f "$config_file" ]; then
        # Create new config with cliPluginsExtraDirs
        printf '{"cliPluginsExtraDirs": ["%s"]}\n' "$plugins_dir" > "$config_file"
        log_info "Created ${config_file} with cliPluginsExtraDirs"
        return 0
    fi

    # File exists -- check if already configured
    if grep -q "cliPluginsExtraDirs" "$config_file"; then
        log_debug "cliPluginsExtraDirs already configured in ${config_file}"
        return 0
    fi

    # SEC-04: Merge into existing JSON using python3 -- pass values via sys.argv
    python3 -c "
import json, sys
config_path = sys.argv[1]
plugins_path = sys.argv[2]
with open(config_path, 'r') as f:
    cfg = json.load(f)
cfg['cliPluginsExtraDirs'] = [plugins_path]
with open(config_path, 'w') as f:
    json.dump(cfg, f, indent=2)
    f.write('\n')
" "$config_file" "$plugins_dir"
    log_info "Added cliPluginsExtraDirs to ${config_file}"
}

# =============================================================================
# Colima Installation
# =============================================================================
# Installs colima, docker, and docker-compose via brew if not already present.
# Idempotent: checks each package individually before installing.

install_colima() {
    local packages_needed=""
    local pkg

    for pkg in colima docker docker-compose; do
        if brew list --formula "$pkg" >/dev/null 2>&1; then
            log_info "${pkg} already installed"
        else
            if [ -n "$packages_needed" ]; then
                packages_needed="${packages_needed} ${pkg}"
            else
                packages_needed="$pkg"
            fi
        fi
    done

    if [ -n "$packages_needed" ]; then
        log_info "Installing: ${packages_needed}"
        # Intentionally unquoted for word splitting
        brew install $packages_needed
    fi

    # Configure Docker CLI plugin path for Compose
    setup_compose_plugin
}

# =============================================================================
# Colima Start
# =============================================================================
# Starts Colima with architecture-appropriate flags and resource overrides.
# Skips if already running. Polls for Docker readiness after start.

start_colima() {
    # Skip if already running
    if colima status >/dev/null 2>&1; then
        log_info "Colima already running -- skipping start"
        return 0
    fi

    # Map macOS arch to Colima arch flag
    local arch_flag
    case "${DETECTED_ARCH}" in
        arm64)   arch_flag="aarch64" ;;
        x86_64)  arch_flag="x86_64" ;;
        *)       die "Unsupported architecture: ${DETECTED_ARCH}" "AGMind requires arm64 or x86_64" ;;
    esac

    # Resource overrides (env vars with defaults)
    local cpu="${COLIMA_CPU:-8}"
    local memory="${COLIMA_MEMORY:-16}"
    local disk="${COLIMA_DISK:-60}"

    log_info "Starting Colima (arch=${arch_flag}, cpu=${cpu}, memory=${memory}GB, disk=${disk}GB)..."
    colima start --arch "$arch_flag" --cpu "$cpu" --memory "$memory" --disk "$disk"

    # Poll for Docker readiness (counter-based, no GNU timeout)
    local attempts=0
    local max_attempts=30
    while [ "$attempts" -lt "$max_attempts" ]; do
        if docker info >/dev/null 2>&1; then
            log_info "Docker is ready via Colima"
            return 0
        fi
        attempts=$((attempts + 1))
        sleep 2
    done

    die "Docker not ready after ${max_attempts} attempts (60s)" "Check: colima status"
}

# =============================================================================
# Docker Socket Fix
# =============================================================================
# Creates /var/run/docker.sock symlink pointing to the active runtime's socket.
# Skips when Docker Desktop already manages the default socket.

_get_socket_path() {
    case "${DOCKER_RUNTIME}" in
        desktop) echo "${HOME}/.docker/run/docker.sock" ;;
        colima)  echo "${HOME}/.colima/default/docker.sock" ;;
        *)       die "Cannot determine socket path for runtime: ${DOCKER_RUNTIME}" \
                     "Set DOCKER_RUNTIME to 'desktop' or 'colima'" ;;
    esac
}

fix_docker_socket() {
    local active_socket
    active_socket=$(_get_socket_path)

    # Verify active socket exists
    if [ ! -S "$active_socket" ]; then
        die "Docker socket not found: ${active_socket}" \
            "Ensure ${DOCKER_RUNTIME} is running"
    fi

    # Docker Desktop manages /var/run/docker.sock itself
    if [ "$DOCKER_RUNTIME" = "desktop" ]; then
        if [ -S "/var/run/docker.sock" ] && docker info >/dev/null 2>&1; then
            log_info "Docker Desktop manages socket -- skipping symlink"
            return 0
        fi
    fi

    # If symlink already points to correct target, skip
    if [ -L "/var/run/docker.sock" ]; then
        local current_target
        current_target=$(readlink /var/run/docker.sock) || true
        if [ "$current_target" = "$active_socket" ]; then
            log_debug "Symlink /var/run/docker.sock already points to ${active_socket}"
            return 0
        fi
    fi

    # Create/update symlink
    log_info "Creating symlink: /var/run/docker.sock -> ${active_socket}"
    sudo ln -sf "$active_socket" /var/run/docker.sock
}

# =============================================================================
# Docker Compose v2 Verification
# =============================================================================
# Confirms Docker Compose v2 is available as a Docker CLI plugin.

verify_compose() {
    local compose_output
    if compose_output=$(docker compose version 2>&1); then
        if echo "$compose_output" | grep -qE 'v[2-9]\.'; then
            log_info "Docker Compose: ${compose_output}"
            return 0
        fi
    fi

    die "Docker Compose v2 not available" \
        "Run: brew install docker-compose && see ~/.docker/config.json cliPluginsExtraDirs"
}
