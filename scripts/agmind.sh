#!/bin/bash
# scripts/agmind.sh -- AGMind CLI
# Day-2 operations tool for managing the AGMind RAG stack on macOS.
# Compatible with /bin/bash 3.2.57 (stock macOS)
#
# Provides: status, doctor, stop, start, restart, logs, backup, uninstall
# Installed to: /usr/local/bin/agmind (symlink -> /opt/agmind/scripts/agmind.sh)

set -euo pipefail

# =============================================================================
# Script directory resolution (symlink-safe)
# =============================================================================
# When invoked via /usr/local/bin/agmind symlink, $0 points to the symlink.
# readlink resolves to the real script path so we can find lib/ modules.

REAL_SCRIPT=$(readlink "$0" 2>/dev/null || echo "$0")
SCRIPT_DIR=$(cd "$(dirname "$REAL_SCRIPT")" && pwd)
AGMIND_DIR="${AGMIND_DIR:-/opt/agmind}"

# =============================================================================
# Source common utilities (always needed for logging)
# =============================================================================

if [ -f "${AGMIND_DIR}/lib/common.sh" ]; then
    source "${AGMIND_DIR}/lib/common.sh"
elif [ -f "${SCRIPT_DIR}/../lib/common.sh" ]; then
    source "${SCRIPT_DIR}/../lib/common.sh"
else
    echo "[ERROR] Cannot find lib/common.sh" >&2
    exit 1
fi

# =============================================================================
# show_usage() -- Print help text
# =============================================================================

show_usage() {
    cat <<EOF
Usage: agmind <command>

AGMind CLI -- manage the AGMind RAG stack on macOS.

Commands:
  status      Show all service status + IPs
  doctor      Run health checks on the live system
  stop        Stop all services (Docker + Ollama)
  start       Start all services (Ollama + Docker)
  restart     Stop then start all services
  logs        Show container logs (all: last 50 lines)
  logs <svc>  Follow logs for a specific service
  backup      Run a manual backup
  uninstall   Remove all AGMind data (interactive)

Options:
  --help, -h  Show this help
EOF
}

# =============================================================================
# cmd_status() -- CLI-02: Show service status
# =============================================================================

cmd_status() {
    source "${AGMIND_DIR}/lib/detect.sh"

    printf "\n%s\n" "${_CYAN}${_BOLD}AGMind Status${_NC}"
    printf "%s\n\n" "----------------------------------------"

    # Docker Containers
    printf "%s\n" "${_BOLD}Docker Containers:${_NC}"
    if [ -f "${AGMIND_DIR}/docker-compose.yml" ]; then
        (cd "$AGMIND_DIR" && docker compose ps --format '{{.Service}}\t{{.State}}\t{{.Status}}') 2>/dev/null | \
        while IFS=$(printf '\t') read -r svc state status_detail; do
            if [ "$state" = "running" ]; then
                printf "  ${_GREEN}[UP]${_NC}    %-20s %s\n" "$svc" "$status_detail"
            else
                printf "  ${_RED}[DOWN]${_NC}  %-20s %s\n" "$svc" "$status_detail"
            fi
        done
    else
        printf "  %s\n" "(no docker-compose.yml found)"
    fi

    # Ollama
    printf "\n%s\n" "${_BOLD}Ollama:${_NC}"
    local ollama_line
    ollama_line=$(brew services list 2>/dev/null | grep "^ollama ") || true
    if echo "$ollama_line" | grep -q "started"; then
        printf "  ${_GREEN}[UP]${_NC}    ollama\n"
    else
        printf "  ${_RED}[DOWN]${_NC}  ollama\n"
    fi

    # Network
    printf "\n%s\n" "${_BOLD}Network:${_NC}"
    local ip_addr
    ip_addr=$(ipconfig getifaddr en0 2>/dev/null || echo "not found")
    printf "  %-20s %s\n" "LAN IP:" "$ip_addr"
    printf "  %-20s %s\n" "Open WebUI:" "http://${ip_addr}/"
    printf "  %-20s %s\n" "Dify Console:" "http://${ip_addr}/apps/"
    printf "  %-20s %s\n" "Ollama API:" "http://localhost:11434"
}

# =============================================================================
# cmd_doctor() -- CLI-03: Run live system health checks
# =============================================================================

cmd_doctor() {
    source "${AGMIND_DIR}/lib/detect.sh"

    printf "\n%s\n\n" "${_CYAN}${_BOLD}AGMind Doctor${_NC}"

    local fail_count=0

    _doctor_pass() {
        printf "  ${_GREEN}[PASS]${_NC}  %s\n" "$1"
    }

    _doctor_warn() {
        printf "  ${_YELLOW}[WARN]${_NC}  %s\n" "$1"
    }

    _doctor_fail() {
        printf "  ${_RED}[FAIL]${_NC}  %s\n" "$1"
        fail_count=$((fail_count + 1))
    }

    # 1. macOS version
    detect_os
    local major_ver
    major_ver=$(echo "$DETECTED_OS_VERSION" | cut -d. -f1)
    if [ "$major_ver" -ge 13 ]; then
        _doctor_pass "macOS ${DETECTED_OS_VERSION}"
    else
        _doctor_fail "macOS ${DETECTED_OS_VERSION} -- minimum macOS 13 required"
    fi

    # 2. Docker socket
    if docker info >/dev/null 2>&1; then
        _doctor_pass "Docker socket"
    else
        _doctor_fail "Docker socket not accessible"
    fi

    # 3. Docker containers running
    local running_count=0
    running_count=$( (cd "$AGMIND_DIR" && docker compose ps --status running -q 2>/dev/null | wc -l | tr -d ' ') ) || true
    if [ "$running_count" -gt 0 ]; then
        _doctor_pass "Docker containers: ${running_count} running"
    else
        _doctor_fail "No Docker containers running"
    fi

    # 4. Ollama API
    if curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
        _doctor_pass "Ollama API"
    else
        _doctor_fail "Ollama API not responding"
    fi

    # 5. Disk space
    detect_disk
    if [ "$DETECTED_DISK_FREE_GB" -lt 30 ]; then
        _doctor_warn "Disk: ${DETECTED_DISK_FREE_GB}GB free (recommend 30GB+)"
    else
        _doctor_pass "Disk: ${DETECTED_DISK_FREE_GB}GB free"
    fi

    # 6. Install directory
    if [ -d "$AGMIND_DIR" ]; then
        _doctor_pass "Install directory: ${AGMIND_DIR}"
    else
        _doctor_fail "Install directory not found: ${AGMIND_DIR}"
    fi

    # 7. LaunchAgents
    local backup_loaded=0
    local health_loaded=0
    launchctl list com.agmind.backup >/dev/null 2>&1 && backup_loaded=1
    launchctl list com.agmind.health >/dev/null 2>&1 && health_loaded=1
    if [ "$backup_loaded" -eq 1 ] && [ "$health_loaded" -eq 1 ]; then
        _doctor_pass "LaunchAgents: backup + health loaded"
    elif [ "$backup_loaded" -eq 1 ] || [ "$health_loaded" -eq 1 ]; then
        _doctor_warn "LaunchAgents: partially loaded"
    else
        _doctor_fail "LaunchAgents: not loaded"
    fi

    # Summary
    printf "\n"
    if [ "$fail_count" -gt 0 ]; then
        log_error "Doctor found ${fail_count} issue(s)"
        exit 1
    fi
    log_info "All checks passed"
}

# =============================================================================
# cmd_stop() -- CLI-04: Stop all services
# =============================================================================

cmd_stop() {
    log_info "Stopping AGMind services..."

    # Stop Docker Compose stack first
    if [ -f "${AGMIND_DIR}/docker-compose.yml" ]; then
        (cd "$AGMIND_DIR" && docker compose down)
        log_info "Docker Compose stack stopped"
    else
        log_warn "docker-compose.yml not found -- skipping compose down"
    fi

    # Stop Ollama
    brew services stop ollama 2>/dev/null || true
    log_info "Ollama service stopped"

    log_info "All AGMind services stopped"
}

# =============================================================================
# cmd_start() -- CLI-05: Start all services
# =============================================================================

cmd_start() {
    source "${AGMIND_DIR}/lib/ollama.sh"

    log_info "Starting AGMind services..."

    # Start Ollama first (containers depend on it)
    brew services restart ollama
    wait_for_ollama

    # Start Docker Compose stack
    if [ -f "${AGMIND_DIR}/docker-compose.yml" ]; then
        (cd "$AGMIND_DIR" && docker compose up -d)
        log_info "Docker Compose stack started"
    else
        die "docker-compose.yml not found at ${AGMIND_DIR}" \
            "Run the installer first: bash install.sh"
    fi

    log_info "All AGMind services started"
}

# =============================================================================
# cmd_restart() -- Stop then start
# =============================================================================

cmd_restart() {
    cmd_stop
    cmd_start
}

# =============================================================================
# cmd_logs() -- CLI-06: Show container logs
# =============================================================================

cmd_logs() {
    local service="${1:-}"

    if [ -n "$service" ]; then
        # Follow mode for specific service
        (cd "$AGMIND_DIR" && docker compose logs -f "$service")
    else
        # Last 50 lines for all services
        (cd "$AGMIND_DIR" && docker compose logs --tail 50)
    fi
}

# =============================================================================
# cmd_backup() -- CLI-07: Run manual backup
# =============================================================================

cmd_backup() {
    bash "${AGMIND_DIR}/scripts/backup.sh"
    log_info "Backup complete"
}

# =============================================================================
# cmd_uninstall() -- CLI-08: Remove all AGMind data
# =============================================================================

cmd_uninstall() {
    printf "%s\n" "${_RED}${_BOLD}WARNING: This will remove all AGMind data!${_NC}"
    printf "This includes: Docker containers, volumes, configs, LaunchAgents, /opt/agmind/\n\n"

    local answer=""
    read -r -p "Remove all AGMind data? [y/N] " answer
    case "$answer" in
        y|Y) ;;
        *) log_info "Uninstall cancelled"; return 0 ;;
    esac

    log_info "Uninstalling AGMind..."

    # 1. Stop and remove Docker containers + volumes
    if [ -f "${AGMIND_DIR}/docker-compose.yml" ]; then
        (cd "$AGMIND_DIR" && docker compose down -v) || log_warn "docker compose down failed"
        log_info "Docker containers and volumes removed"
    fi

    # 2. Stop Ollama
    brew services stop ollama 2>/dev/null || true
    log_info "Ollama service stopped"

    # 3. Unload and remove LaunchAgents
    local uid
    uid=$(id -u)
    local plist
    for plist in "${HOME}/Library/LaunchAgents"/com.agmind.*.plist; do
        [ -f "$plist" ] || continue
        launchctl bootout "gui/${uid}" "$plist" 2>/dev/null || \
            launchctl unload "$plist" 2>/dev/null || true
        rm -f "$plist"
        log_info "Removed: $plist"
    done

    # 4. Remove CLI symlink
    sudo rm -f /usr/local/bin/agmind 2>/dev/null || true

    # 5. Remove install directory
    sudo rm -rf "$AGMIND_DIR"

    printf "\n%s\n" "${_GREEN}AGMind uninstalled successfully${_NC}"
    printf "Note: Ollama itself remains installed (brew uninstall ollama to remove)\n"
}

# =============================================================================
# Case Dispatcher
# =============================================================================

case "${1:-}" in
    status)     cmd_status ;;
    doctor)     cmd_doctor ;;
    stop)       cmd_stop ;;
    start)      cmd_start ;;
    restart)    cmd_restart ;;
    logs)       shift; cmd_logs "${1:-}" ;;
    backup)     cmd_backup ;;
    uninstall)  cmd_uninstall ;;
    --help|-h|"") show_usage ;;
    *)          printf "${_RED}Unknown command: %s${_NC}\n\n" "$1" >&2; show_usage >&2; exit 1 ;;
esac
