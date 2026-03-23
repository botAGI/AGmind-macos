#!/bin/bash
# lib/detect.sh -- AGMind macOS system detection and preflight validation
# Sourced by install.sh for Phase 1 (Diagnostics)
# Compatible with /bin/bash 3.2.57 (stock macOS)
#
# Provides: System detection functions and preflight aggregator
# Exports: detect_os, detect_ram, detect_disk, detect_ports,
#          detect_docker, detect_ollama, detect_homebrew, preflight_checks
#
# Depends on: lib/common.sh (log_info, log_warn, log_error, log_debug, die)

set -eEuo pipefail

# =============================================================================
# OS Detection
# =============================================================================

detect_os() {
    DETECTED_OS="macos"
    DETECTED_OS_VERSION=$(sw_vers -productVersion)
    DETECTED_ARCH=$(uname -m)
    export DETECTED_OS
    export DETECTED_OS_VERSION
    export DETECTED_ARCH
    log_debug "OS: ${DETECTED_OS} ${DETECTED_OS_VERSION} (${DETECTED_ARCH})"
}

# =============================================================================
# RAM Detection
# =============================================================================

detect_ram() {
    local ram_bytes
    ram_bytes=$(sysctl -n hw.memsize)
    DETECTED_RAM_GB=$((ram_bytes / 1024 / 1024 / 1024))
    export DETECTED_RAM_GB
    log_debug "RAM: ${DETECTED_RAM_GB}GB (${ram_bytes} bytes)"
}

# =============================================================================
# Disk Space Detection
# =============================================================================

detect_disk() {
    local avail_kb
    avail_kb=$(df -k / | awk 'NR==2 {print $4}')
    DETECTED_DISK_FREE_GB=$((avail_kb / 1024 / 1024))
    export DETECTED_DISK_FREE_GB
    log_debug "Disk free: ${DETECTED_DISK_FREE_GB}GB"
}

# =============================================================================
# Port Detection (internal helper + public function)
# =============================================================================

_check_port() {
    local port="$1"
    local output
    output=$(lsof -iTCP:"${port}" -sTCP:LISTEN -P -n 2>/dev/null) || return 1
    # Port is in use -- extract process name and PID from second line
    local proc_name pid
    proc_name=$(echo "$output" | awk 'NR==2 {print $1}')
    pid=$(echo "$output" | awk 'NR==2 {print $2}')
    echo "${proc_name}:${pid}"
    return 0
}

detect_ports() {
    local port result
    PORT_CONFLICTS=""
    for port in 80 443 3000 11434; do
        result=""
        result=$(_check_port "$port") || true
        if [ -n "$result" ]; then
            if [ -n "$PORT_CONFLICTS" ]; then
                PORT_CONFLICTS="${PORT_CONFLICTS}
${port}:${result}"
            else
                PORT_CONFLICTS="${port}:${result}"
            fi
            log_debug "Port ${port}: in use by ${result}"
        else
            log_debug "Port ${port}: free"
        fi
    done
}

# =============================================================================
# Docker Socket Detection (internal helper + public function)
# =============================================================================

_test_docker_socket() {
    local socket="$1"
    [ -S "$socket" ] || return 1
    DOCKER_HOST="unix://${socket}" docker info >/dev/null 2>&1 || return 1
}

detect_docker() {
    # Allow env override for advanced users and testing
    if [ -n "${DOCKER_RUNTIME:-}" ]; then
        log_debug "Docker runtime override: ${DOCKER_RUNTIME}"
        export DOCKER_RUNTIME
        return 0
    fi

    local desktop_socket="${HOME}/.docker/run/docker.sock"
    local colima_socket="${HOME}/.colima/default/docker.sock"

    # Prefer Docker Desktop if both respond
    if _test_docker_socket "$desktop_socket"; then
        DOCKER_RUNTIME="desktop"
    elif _test_docker_socket "$colima_socket"; then
        DOCKER_RUNTIME="colima"
    else
        DOCKER_RUNTIME="none"
    fi
    export DOCKER_RUNTIME
    log_debug "Docker runtime: ${DOCKER_RUNTIME}"
}

# =============================================================================
# Ollama Detection
# =============================================================================

detect_ollama() {
    local port_result=""
    port_result=$(_check_port 11434) || true

    if [ -n "$port_result" ]; then
        # Something is listening on 11434, verify it is Ollama via API
        if curl -sf --connect-timeout 5 --max-time 10 http://localhost:11434/api/tags >/dev/null 2>&1; then
            OLLAMA_RUNNING=1
            log_debug "Ollama: running (API responding on port 11434)"
        else
            OLLAMA_RUNNING=1
            log_debug "Ollama: port 11434 in use by ${port_result} (API not responding)"
        fi
    else
        OLLAMA_RUNNING=0
        log_debug "Ollama: not running"
    fi
    export OLLAMA_RUNNING
}

# =============================================================================
# Homebrew Detection
# =============================================================================

detect_homebrew() {
    if command -v brew >/dev/null 2>&1; then
        BREW_INSTALLED=1
        BREW_PREFIX=$(brew --prefix)
    else
        BREW_INSTALLED=0
        # Set expected prefix based on architecture even when brew is not installed
        if [ "$(uname -m)" = "arm64" ]; then
            BREW_PREFIX="/opt/homebrew"
        else
            BREW_PREFIX="/usr/local"
        fi
    fi
    export BREW_INSTALLED
    export BREW_PREFIX
    log_debug "Homebrew: installed=${BREW_INSTALLED}, prefix=${BREW_PREFIX}"
}

# =============================================================================
# Preflight Checks Aggregator
# =============================================================================

preflight_checks() {
    # Skip all checks if SKIP_PREFLIGHT is set
    if [ "${SKIP_PREFLIGHT:-0}" = "1" ]; then
        log_warn "Preflight checks skipped (SKIP_PREFLIGHT=1)"
        return 0
    fi

    # Counters and message accumulators
    local fail_count=0
    local warn_count=0
    local fail_msgs=""
    local warn_msgs=""

    # Internal helpers (use literal newlines in string concatenation -- Bash 3.2 safe)
    _preflight_pass() {
        log_info "[PASS] $1"
    }

    _preflight_warn() {
        log_warn "[WARN] $1"
        warn_msgs="${warn_msgs}
  - $1"
        warn_count=$((warn_count + 1))
    }

    _preflight_fail() {
        log_error "[FAIL] $1"
        fail_msgs="${fail_msgs}
  - $1"
        fail_count=$((fail_count + 1))
    }

    # -------------------------------------------------------------------------
    # Run all detection functions
    # -------------------------------------------------------------------------
    detect_os
    detect_ram
    detect_disk
    detect_homebrew
    detect_docker
    detect_ollama

    # -------------------------------------------------------------------------
    # Apply threshold checks
    # -------------------------------------------------------------------------

    # macOS version check (minimum macOS 13)
    local major_ver="${DETECTED_OS_VERSION%%.*}"
    if [ "$major_ver" -lt 13 ]; then
        _preflight_fail "macOS ${DETECTED_OS_VERSION} -- minimum macOS 13 required"
    else
        _preflight_pass "macOS ${DETECTED_OS_VERSION}"
    fi

    # Architecture check
    if [ "$DETECTED_ARCH" = "arm64" ] || [ "$DETECTED_ARCH" = "x86_64" ]; then
        _preflight_pass "Architecture: ${DETECTED_ARCH}"
    else
        _preflight_fail "Unsupported architecture: ${DETECTED_ARCH}"
    fi

    # RAM check (minimum 8GB)
    if [ "$DETECTED_RAM_GB" -lt 8 ]; then
        _preflight_fail "RAM: ${DETECTED_RAM_GB}GB (minimum 8GB required)"
    else
        _preflight_pass "RAM: ${DETECTED_RAM_GB}GB"
    fi

    # Disk check (minimum 30GB free)
    if [ "$DETECTED_DISK_FREE_GB" -lt 30 ]; then
        _preflight_fail "Disk: ${DETECTED_DISK_FREE_GB}GB free (minimum 30GB required)"
    else
        _preflight_pass "Disk: ${DETECTED_DISK_FREE_GB}GB free"
    fi

    # Port checks
    detect_ports
    local port proc_info proc_name pid
    for port in 80 443 3000 11434; do
        proc_info=""
        proc_info=$(echo "$PORT_CONFLICTS" | grep "^${port}:" 2>/dev/null) || true
        if [ -n "$proc_info" ]; then
            # Extract process name and PID from "port:procname:pid"
            proc_name=$(echo "$proc_info" | cut -d: -f2)
            pid=$(echo "$proc_info" | cut -d: -f3)
            case "$port" in
                80)
                    _preflight_fail "Port 80 in use by ${proc_name} (PID ${pid}) -- nginx needs this port"
                    ;;
                3000)
                    _preflight_fail "Port 3000 in use by ${proc_name} (PID ${pid}) -- Dify console needs this port"
                    ;;
                443)
                    _preflight_warn "Port 443 in use by ${proc_name} (PID ${pid}) -- not required for LAN profile"
                    ;;
                11434)
                    _preflight_warn "Port 11434 in use by ${proc_name} (PID ${pid}) -- Ollama may already be running (OK)"
                    ;;
            esac
        fi
    done

    # Homebrew check
    if [ "$BREW_INSTALLED" -eq 0 ]; then
        _preflight_warn "Homebrew not found -- will be needed for Ollama and Docker setup"
    else
        _preflight_pass "Homebrew: ${BREW_PREFIX}"
    fi

    # Docker check
    if [ "$DOCKER_RUNTIME" = "none" ]; then
        _preflight_warn "No Docker runtime found -- will be installed in Phase 3"
    else
        _preflight_pass "Docker: ${DOCKER_RUNTIME}"
    fi

    # -------------------------------------------------------------------------
    # Summary
    # -------------------------------------------------------------------------
    printf "\n%s\n" "${_CYAN}${_BOLD}--- Preflight Summary ---${_NC}"

    if [ "$fail_count" -gt 0 ]; then
        log_error "Preflight errors:${fail_msgs}"
        die "Preflight failed with ${fail_count} error(s)" "Fix the issues above and re-run the installer"
    fi

    if [ "$warn_count" -gt 0 ]; then
        log_warn "Preflight warnings:${warn_msgs}"
        if [ "${NON_INTERACTIVE:-0}" != "1" ]; then
            local answer=""
            read -r -p "Continue with ${warn_count} warning(s)? [Y/n] " answer
            case "$answer" in
                n|N) exit 1 ;;
            esac
        else
            log_info "Non-interactive mode: accepting ${warn_count} warning(s) automatically"
        fi
    fi

    if [ "$fail_count" -eq 0 ] && [ "$warn_count" -eq 0 ]; then
        log_info "All preflight checks passed"
    fi
}
