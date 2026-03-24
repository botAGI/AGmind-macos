# Pitfalls Research

**Domain:** macOS Bash Installer for Docker-based AI RAG Stack
**Researched:** 2026-03-20
**Confidence:** HIGH (most findings verified on live macOS 26.3 / Apple M4 Pro)

## Critical Pitfalls

### Pitfall 1: BSD vs GNU Tool Incompatibilities Silently Corrupt Data

**What goes wrong:**
Scripts ported from Linux use GNU syntax that either errors out or silently does the wrong thing on macOS. The most dangerous cases are silent ones -- where the script appears to succeed but produces incorrect output.

Verified incompatibilities on this machine (macOS 26.3, arm64):

| Tool | GNU (Linux) | BSD (macOS) | Failure Mode |
|------|-------------|-------------|--------------|
| `sed -i` | `sed -i 's/a/b/' file` | `sed -i '' 's/a/b/' file` | **Creates `file's/a/b/'` backup file** if you omit `''` |
| `grep -P` | Works (PCRE) | **Does not exist** | `grep: invalid option -- P` hard error |
| `readlink -f` | Resolves full path | **Not supported** on older macOS | `readlink: illegal option -- f` (works on macOS 26 but not universal) |
| `timeout` | Built-in coreutils | **Does not exist** | `command not found` |
| `date --date` | `date --date="1 hour ago"` | `date -v-1H` | `illegal option -- -` |
| `stat --format` | `stat --format '%Y' file` | `stat -f '%m' file` | `illegal option -- -` |
| `grep -P '\d+'` | Perl regex | Not available | Must use `grep -E '[0-9]+'` |
| `mktemp` | `mktemp /tmp/foo.XXXXXX` | Same works, but `-t` flag behaves differently | Template path may differ |
| `|&` pipe stderr | Bash 4+ syntax | **Syntax error** on bash 3.2 | Script dies immediately |

**Why it happens:**
Developers write and test on Linux or with Homebrew's GNU coreutils installed. The script works locally but fails on stock macOS. The spec explicitly mentions this risk but it is extremely easy to slip up when porting ~70-95% of the Linux codebase.

**How to avoid:**
Create a `_portable_sed()` wrapper in `lib/common.sh` and use it everywhere:

```bash
_portable_sed() {
  if sed --version 2>/dev/null | grep -q 'GNU'; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}
```

For `timeout`, implement a pure-bash replacement:

```bash
_timeout() {
  local duration="$1"; shift
  ( "$@" ) & local pid=$!
  ( sleep "$duration" && kill "$pid" 2>/dev/null ) & local timer=$!
  wait "$pid" 2>/dev/null; local exit_code=$?
  kill "$timer" 2>/dev/null; wait "$timer" 2>/dev/null
  return "$exit_code"
}
```

Ban `grep -P` entirely. Use `grep -E` (extended regex) for all patterns. Add a CI lint rule: `grep -rn 'grep -P' lib/` should return zero results.

**Warning signs:**
- Any `sed -i` call without `''` as the first argument after `-i`
- Any use of `timeout`, `readlink -f`, `stat --format`, `date --date` in source
- Any `grep -P` usage
- BATS tests passing on Linux CI but failing on macOS

**Phase to address:**
Phase 1 (lib/common.sh) -- all portability wrappers must exist before any other module is written. Every module must use the wrappers, never raw commands.

---

### Pitfall 2: macOS Ships Bash 3.2 -- Many Bash 4+ Features Crash

**What goes wrong:**
macOS ships `/bin/bash` version **3.2.57** (from 2007, kept at 3.2 due to GPLv3 licensing). Scripts using bash 4+ features crash immediately.

Verified on this machine -- these all fail under `/bin/bash`:

| Feature | Minimum Bash | Error on 3.2 |
|---------|-------------|--------------|
| `declare -A` (associative arrays) | 4.0 | `declare: -A: invalid option` |
| `mapfile` / `readarray` | 4.0 | `command not found` |
| `coproc` | 4.0 | `command not found` |
| `|&` (pipe stderr) | 4.0 | `syntax error near unexpected token '&'` |
| `${var,,}` lowercase | 4.0 | parse error |
| `${!prefix@}` indirect | 4.0 | broken behavior |
| `[[ $x =~ regex ]]` capture groups | 3.2 works | But regex behavior changed in 4.0 |

**Why it happens:**
Developers have Homebrew bash 5.x installed and their default shell is zsh (which is modern). They write bash scripts on macOS that happen to work because `/opt/homebrew/bin/bash` is in PATH, but the shebang `#!/bin/bash` uses the system 3.2.

**How to avoid:**
- Use `#!/bin/bash` shebang (not `#!/usr/bin/env bash` which might pick up brew bash inconsistently)
- **Never use associative arrays.** Use paired indexed arrays or `case` statements instead
- **Never use `mapfile`.** Use `while IFS= read -r` loops
- Add a shellcheck CI rule: `shellcheck --shell=bash --exclude=SC2034 lib/*.sh`
- Add a BATS test that explicitly runs under `/bin/bash` to catch regressions:

```bash
@test "installer runs under stock macOS bash 3.2" {
  /bin/bash -n install.sh  # syntax check
}
```

**Warning signs:**
- Any `declare -A` in source code
- Any `mapfile` or `readarray` usage
- ShellCheck warnings about bash version compatibility
- Scripts that work when run as `bash script.sh` but fail with `./script.sh`

**Phase to address:**
Phase 1 (lib/common.sh) and enforced across all phases. ShellCheck must be in CI from day 1.

---

### Pitfall 3: Colima `host.docker.internal` Does Not Resolve Without `extra_hosts`

**What goes wrong:**
The entire AGMind architecture depends on Docker containers reaching Ollama on the host via `host.docker.internal:11434`. In Docker Desktop, this resolves automatically. In Colima, it does **not** resolve without explicit `extra_hosts` configuration -- DNS lookup works (verified: resolves to `192.168.5.2`) but `/etc/hosts` inside containers does NOT contain the entry unless `extra_hosts` is specified.

Verified on this machine:
- `docker run --rm alpine cat /etc/hosts | grep host.docker` -- **empty** (no entry without extra_hosts)
- With `extra_hosts: ["host.docker.internal:host-gateway"]` in compose -- resolves to `192.168.5.2`
- DNS resolution via Colima's DNS does work (nslookup succeeds), but some applications use `/etc/hosts` directly

**Why it happens:**
Docker Desktop injects `host.docker.internal` into every container's `/etc/hosts` automatically. Colima relies on its DNS server which works for `nslookup` but not for all resolution paths. Applications that bypass DNS (using `/etc/hosts` directly or `getaddrinfo` with certain configurations) will fail silently -- connections to Ollama time out with no useful error message.

**How to avoid:**
Always add `extra_hosts` to every service that needs host access in `docker-compose.yml`, regardless of runtime:

```yaml
services:
  api:
    extra_hosts:
      - "host.docker.internal:host-gateway"
  open-webui:
    extra_hosts:
      - "host.docker.internal:host-gateway"
  worker:
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

This is harmless on Docker Desktop (it already resolves) and essential on Colima. Do NOT make this conditional on the detected runtime -- always include it.

Additionally, in the health check phase, verify connectivity:

```bash
docker exec dify-api wget -q -O /dev/null http://host.docker.internal:11434/api/tags \
  || die "Containers cannot reach Ollama on host"
```

**Warning signs:**
- Dify shows "connection refused" or "timeout" when trying to use Ollama models
- Open WebUI shows no models available
- `curl http://localhost:11434/api/tags` works from the host but fails from inside containers

**Phase to address:**
Phase 5 (Configuration) -- docker-compose.yml templates must include `extra_hosts` on every relevant service. Phase 7 (Health) must verify container-to-host connectivity.

---

### Pitfall 4: Docker Socket Location Varies and Breaks Silently

**What goes wrong:**
Docker socket location differs between runtimes and can change between versions. Scripts that hardcode socket paths break when users switch runtimes or upgrade.

Verified socket locations on this machine:

| Runtime | Socket Path | Notes |
|---------|-------------|-------|
| Colima | `~/.colima/default/docker.sock` | Profile-dependent (`~/.colima/<profile>/docker.sock`) |
| Docker Desktop | `~/.docker/run/docker.sock` | Changed from `/var/run/docker.sock` in recent versions |
| Symlink | `/var/run/docker.sock` | Points to Colima socket (manually created, requires sudo) |
| Docker context | `colima` context active | `docker context ls` shows which is active |

On this machine: Colima is active via docker context, symlink exists at `/var/run/docker.sock -> ~/.colima/default/docker.sock`, DOCKER_HOST is not set in env.

**Why it happens:**
- Docker Desktop moved its socket from `/var/run/docker.sock` to `~/.docker/run/docker.sock`
- Colima uses profile-specific sockets
- The `/var/run/docker.sock` symlink is created manually (by `colima start` or by the user) and can break on reboot
- Docker contexts add another layer: the `colima` context overrides DOCKER_HOST

**How to avoid:**
Use docker context, not socket paths:

```bash
detect_docker_socket() {
  # Prefer docker context (most reliable)
  if docker context inspect colima &>/dev/null; then
    docker context use colima &>/dev/null
    return 0
  fi

  # Check known socket locations
  local sockets=(
    "$HOME/.colima/default/docker.sock"
    "$HOME/.docker/run/docker.sock"
    "/var/run/docker.sock"
  )
  for sock in "${sockets[@]}"; do
    if [ -S "$sock" ]; then
      export DOCKER_HOST="unix://$sock"
      return 0
    fi
  done
  return 1
}
```

**Never** hardcode `/var/run/docker.sock`. Always detect.

**Warning signs:**
- `docker ps` fails with "Cannot connect to the Docker daemon"
- Socket file exists but is stale (Colima stopped, socket file remains)
- Works after `colima start` but breaks after reboot

**Phase to address:**
Phase 3 (Prerequisites / docker.sh) -- socket detection must be robust and tested for both runtimes. Phase 1 (Diagnostics) should report which runtime and socket are active.

---

### Pitfall 5: Ollama Already Running -- Port 11434 Conflict and Double Instances

**What goes wrong:**
Many macOS users already have Ollama installed (via brew or the .app download). The installer tries to install/start Ollama but port 11434 is already occupied. Worse: if Ollama was installed via the macOS app (not brew), `brew services start ollama` starts a second instance that binds to a random port or fails silently.

Verified on this machine:
- Ollama 0.17.7 running via brew services on port 11434 (PID 923)
- LaunchAgent: `~/Library/LaunchAgents/homebrew.mxcl.ollama.plist`
- Models already downloaded: bge-m3 (1.2GB), nomic-embed-text (274MB)

Two separate Ollama installations can exist:
1. **Brew:** `/opt/homebrew/opt/ollama/bin/ollama` with LaunchAgent `homebrew.mxcl.ollama`
2. **App:** `/Applications/Ollama.app` with its own LaunchAgent

**Why it happens:**
Users install Ollama independently before running the AGMind installer. The installer blindly runs `brew install ollama` + `brew services start ollama` without checking.

**How to avoid:**

```bash
setup_ollama() {
  # Check if already running and healthy
  if curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
    log_info "Ollama already running on :11434, reusing existing instance"
    OLLAMA_PREEXISTING=true
    return 0
  fi

  # Check for App version
  if [ -d "/Applications/Ollama.app" ]; then
    log_warn "Ollama.app detected. Prefer brew version for service management."
    log_warn "Stop Ollama.app before continuing, or accept manual management."
  fi

  # Check if brew version installed but not running
  if brew list ollama &>/dev/null; then
    brew services start ollama
    _wait_for_ollama 60
    return $?
  fi

  # Fresh install
  brew install ollama
  brew services start ollama
  _wait_for_ollama 60
}
```

Track `OLLAMA_PREEXISTING=true` so the uninstaller knows not to remove a user's pre-existing Ollama.

**Warning signs:**
- `lsof -iTCP:11434` shows a process that is not the brew-installed ollama
- `brew services list` shows ollama as "none" (not managed) but port is in use
- Two ollama processes in `ps aux | grep ollama`

**Phase to address:**
Phase 1 (Diagnostics / detect.sh) -- detect existing Ollama instances. Phase 4 (Ollama Setup) -- reuse existing instance if healthy, handle App vs Brew conflict.

---

### Pitfall 6: `set -euo pipefail` Causes Unexpected Script Termination

**What goes wrong:**
`set -euo pipefail` is best practice but creates three classes of silent script death on macOS:

1. **`-u` (nounset):** `$DEPLOY_PROFILE` without `${DEPLOY_PROFILE:-}` kills the script. Verified: `bash -c 'set -u; echo "$DEPLOY_PROFILE"'` exits with "unbound variable."
2. **`-e` (errexit):** `grep "pattern" file` where pattern is not found exits with code 1, killing the script.
3. **`-o pipefail`:** `echo "test" | grep "nonexistent" | cat` -- the middle `grep` fails, killing the entire pipeline. Verified: exits with code 1.

**Why it happens:**
The Linux installer likely has patterns like `local existing=$(grep "PATTERN" "$file")` which work fine without `set -e` but die with it. On macOS, with BSD tools that have slightly different exit codes, the problem is amplified.

**How to avoid:**
Define strict patterns and use them consistently:

```bash
# SAFE: Always use default values for optional vars
local profile="${DEPLOY_PROFILE:-lan}"

# SAFE: grep that won't kill the script
local result
result=$(grep "PATTERN" "$file" 2>/dev/null) || true

# SAFE: check if grep found something
if grep -q "PATTERN" "$file" 2>/dev/null; then
  # found
fi

# SAFE: command that might fail
if ! docker ps &>/dev/null; then
  die "Docker not running"
fi

# DANGEROUS: This kills the script if PATTERN not found
local result=$(grep "PATTERN" "$file")  # DON'T DO THIS

# DANGEROUS: pipe with pipefail
echo "$output" | grep "SUCCESS" | head -1  # DON'T DO THIS
```

Add a trap for debugging:

```bash
trap 'echo "ERROR: $BASH_SOURCE:$LINENO: command \"$BASH_COMMAND\" exited with $?" >&2' ERR
```

**Warning signs:**
- Script exits silently with no error message
- Script works when run without `set -euo pipefail`
- `grep` commands without `|| true` or `if` guards
- Variable references without `${VAR:-default}` syntax

**Phase to address:**
Phase 1 (lib/common.sh) -- establish the error handling pattern. Every module must follow it. BATS tests should test with `set -euo pipefail` enabled.

---

### Pitfall 7: LaunchAgent Plists Have Strict Requirements macOS Will Silently Ignore

**What goes wrong:**
LaunchAgent plists that are syntactically valid XML but semantically incorrect are silently ignored by launchd. The job never runs, and there is no error message. Common mistakes:

1. **Wrong permissions:** plist must be owned by the user and have mode 644. Mode 755 or root ownership = silently ignored.
2. **Missing PATH:** LaunchAgents run with a minimal environment. `/opt/homebrew/bin` is NOT in PATH. Scripts that call `docker`, `ollama`, `brew` will fail because those are in `/opt/homebrew/bin/`.
3. **TMPDIR not set:** LaunchAgents don't inherit the user's TMPDIR. Scripts using `$TMPDIR` get empty string.
4. **Working directory:** If `WorkingDirectory` points to a nonexistent path, the job silently fails.
5. **Label mismatch:** The `Label` value MUST match the filename (e.g., `com.agmind.health.plist` must have Label `com.agmind.health`). Mismatch = silently ignored.
6. **User vs System context:** `~/Library/LaunchAgents/` is user context (runs as user). `/Library/LaunchDaemons/` is system context (runs as root). Mixing them up causes permission errors.

Verified on this machine: Homebrew's Ollama plist correctly includes `LimitLoadToSessionType` for multiple session types and uses the full path `/opt/homebrew/opt/ollama/bin/ollama`.

**Why it happens:**
Developers test by running scripts manually (where PATH includes everything) and assume LaunchAgents have the same environment. launchd's error reporting is nearly nonexistent.

**How to avoid:**
Template plists must always include:

```xml
<key>EnvironmentVariables</key>
<dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>HOME</key>
    <string>__HOME__</string>
</dict>
<key>WorkingDirectory</key>
<string>/opt/agmind</string>
```

Use full absolute paths for all commands in `ProgramArguments`. Never use bare `docker` or `ollama`.

Validate plists after generation:

```bash
plutil -lint ~/Library/LaunchAgents/com.agmind.health.plist \
  || die "Invalid plist"
```

Set correct ownership and permissions:

```bash
chown "$USER" ~/Library/LaunchAgents/com.agmind.*.plist
chmod 644 ~/Library/LaunchAgents/com.agmind.*.plist
```

**Warning signs:**
- `launchctl list | grep agmind` returns nothing (job not loaded)
- Health checks or backups never run
- Script works when run manually but not via launchd
- `launchctl print gui/$(id -u)/com.agmind.health` shows error state

**Phase to address:**
Phase 9 (Complete) -- LaunchAgent creation and validation. Must include BATS tests that verify plist validity and environment.

---

### Pitfall 8: `/opt/agmind` Ownership Creates Sudo Treadmill

**What goes wrong:**
`/opt/agmind` is created with `sudo mkdir` and owned by root. All subsequent file operations need sudo. The installer runs as root for initial setup but the `agmind` CLI, backup scripts, and LaunchAgents run as the user. Files created by sudo during install are unreadable/unwritable by user-context operations.

Verified on this machine:
- `/opt/agmind` is owned by `root:wheel` with mode `drwxr-xr-x`
- User cannot write to it: `touch /opt/agmind/test_write` fails with "Permission denied"
- Docker volumes inside `/opt/agmind/docker/` are also root-owned

**Why it happens:**
The Linux installer runs everything as root. On macOS, the norm is to avoid running as root. The installer needs sudo for `/opt/` creation but then subsequent operations (backup scripts, CLI commands, LaunchAgent scripts) run as the user.

**How to avoid:**
Create the directory with sudo, then immediately chown to the user:

```bash
setup_install_dir() {
  sudo mkdir -p /opt/agmind
  sudo chown -R "$(whoami):staff" /opt/agmind
  chmod 755 /opt/agmind
}
```

For Docker volumes that need to be owned by specific container UIDs, create a separate `docker/` subdirectory:

```bash
# /opt/agmind/ -- owned by user (scripts, config, logs)
# /opt/agmind/docker/ -- owned by user, Docker manages internals via named volumes
```

Use named Docker volumes instead of bind mounts where possible -- they avoid host permission issues entirely.

**Warning signs:**
- `agmind backup` fails with "Permission denied"
- LaunchAgent scripts fail silently (writing to root-owned log files)
- `docker compose` can't read `.env` or config files
- Files created during install have different ownership than files created during operation

**Phase to address:**
Phase 3 (Prerequisites) -- directory creation with correct ownership. Must be tested in BATS with a non-root user.

---

### Pitfall 9: Colima Memory Defaults Starve the Docker Stack

**What goes wrong:**
Colima defaults to 2GB memory allocation. Even with manual configuration, users often under-allocate. The AGMind stack (PostgreSQL + Redis + Weaviate/Qdrant + Dify API + Dify Worker + Dify Web + Plugin Daemon + Open WebUI + Nginx + Squid) easily needs 6-8GB minimum. With only 2GB, containers OOM-kill randomly with no clear error message.

Verified on this machine: Colima configured with 6GB / 4 CPU / 40GB disk. System has 24GB total. This leaves 18GB for Ollama + macOS.

**Why it happens:**
Colima is conservative by default. Users don't know how much memory Docker needs. On macOS with unified memory, over-allocating to Colima starves Ollama (which needs memory for model weights) and the system itself.

**How to avoid:**
Calculate Colima allocation based on system memory and selected LLM model:

```bash
calculate_colima_resources() {
  local total_gb=$(( $(sysctl -n hw.memsize) / 1073741824 ))
  local model_gb="${MODEL_MEMORY_GB:-4}"  # estimated from model selection

  # Reserve: model_gb for Ollama + 4GB for macOS + rest for Docker
  local docker_gb=$(( total_gb - model_gb - 4 ))

  # Minimum 4GB for Docker, maximum 16GB
  docker_gb=$(( docker_gb < 4 ? 4 : docker_gb ))
  docker_gb=$(( docker_gb > 16 ? 16 : docker_gb ))

  local docker_cpu=$(( $(sysctl -n hw.ncpu) / 2 ))
  docker_cpu=$(( docker_cpu < 2 ? 2 : docker_cpu ))

  echo "COLIMA_MEMORY=$docker_gb"
  echo "COLIMA_CPU=$docker_cpu"
}
```

Warn users when total memory is insufficient:

```bash
if [ "$total_gb" -lt 16 ] && [ "$model_gb" -gt 4 ]; then
  log_warn "Only ${total_gb}GB RAM. Large models may cause OOM."
  log_warn "Recommend: 32GB+ for models above 14B parameters."
fi
```

**Warning signs:**
- Random container restarts with exit code 137 (OOM killed)
- `docker stats` shows containers at memory limit
- System becomes unresponsive during model inference
- `colima list` shows memory allocation much lower than needed

**Phase to address:**
Phase 2 (Wizard) -- memory calculation based on model choice. Phase 3 (Prerequisites / docker.sh) -- Colima start with calculated resources. Phase 1 (Diagnostics) -- warn if total RAM is too low.

---

### Pitfall 10: Disk Space Vanishes -- Ollama Models + Docker Layers on Virtualized FS

**What goes wrong:**
Ollama models and Docker images consume far more disk than users expect. On macOS, Docker runs in a VM (Colima uses QEMU/VZ), and the virtual disk file grows but **never shrinks** even after deleting images. Users run out of disk space with no clear indication of why.

Verified on this machine:
- Ollama models: 1.3GB (just 2 small embedding models)
- Docker images: 2.5GB, volumes: 24GB, containers: 974MB
- Colima disk allocation: 40GB (grows to actual usage)

Typical full AGMind stack disk usage:
- Ollama 14B model: ~8-9GB
- Ollama 70B model: ~40GB
- Docker images (all services): ~5-8GB
- Docker volumes (PostgreSQL, Weaviate data): grows with usage, typically 5-20GB
- **Total minimum: 30GB. Realistic: 60-100GB.**

**Why it happens:**
The 30GB minimum in the spec is barely enough for a small model + empty databases. Users choose 70B models without realizing they need 40GB for the model alone. Colima's virtual disk never reclaims space -- even `docker system prune` doesn't shrink the qcow2/raw file.

**How to avoid:**
Calculate disk requirements based on model selection:

```bash
check_disk_space() {
  local available_gb=$(( $(df -k / | tail -1 | awk '{print $4}') / 1048576 ))
  local model_size_gb="${MODEL_DISK_GB:-10}"
  local docker_base_gb=15  # images + initial volumes
  local required_gb=$(( model_size_gb + docker_base_gb + 10 ))  # 10GB buffer

  if [ "$available_gb" -lt "$required_gb" ]; then
    die "Need ${required_gb}GB free disk space, only ${available_gb}GB available"
  fi

  if [ "$available_gb" -lt $(( required_gb + 20 )) ]; then
    log_warn "Low disk space. ${available_gb}GB available, recommend $(( required_gb + 20 ))GB+"
  fi
}
```

Set Colima disk size during creation (cannot be decreased later, only increased):

```bash
# Start with generous disk -- it's sparse, only uses actual space
colima start --disk 100  # sparse disk, actual usage << 100GB
```

**Warning signs:**
- `df -h /` shows < 10GB free
- Ollama model pull hangs or fails
- Docker containers fail to start with "no space left on device"
- Colima VM becomes unresponsive

**Phase to address:**
Phase 1 (Diagnostics) -- disk space check with model-aware calculation. Phase 2 (Wizard) -- warn about disk requirements for chosen model. Phase 3 (Prerequisites) -- generous Colima disk allocation.

---

### Pitfall 11: AirPlay Receiver Occupies Ports 5000 and 7000

**What goes wrong:**
macOS Monterey+ has AirPlay Receiver enabled by default, which binds to ports 5000 and 7000. While AGMind doesn't use these ports directly, developers often find Docker Desktop or monitoring tools (Grafana uses 3000, Portainer uses 9443) conflicting with other macOS services. The real critical conflict: **port 5000 is commonly used by Docker Registry and some Python apps**.

Verified on this machine:
- Port 5000: ControlCenter (AirPlay Receiver) LISTENING on IPv4 and IPv6
- Port 7000: ControlCenter (AirPlay Receiver) LISTENING on IPv4 and IPv6
- Port 5432: SSH tunnel (postgres) -- user already forwarding a remote DB
- Port 6379: SSH tunnel (redis) -- user already forwarding a remote Redis
- Port 11434: Ollama running

**Why it happens:**
macOS enables AirPlay Receiver by default. Users also commonly run development databases, SSH tunnels, and other services on standard ports that overlap with AGMind's stack.

**How to avoid:**
Comprehensive port check in preflight:

```bash
check_ports() {
  local required_ports=(80 3000 5432 6379 8080 11434)
  local conflicts=()

  for port in "${required_ports[@]}"; do
    local process
    process=$(lsof -iTCP:"$port" -sTCP:LISTEN -t 2>/dev/null | head -1)
    if [ -n "$process" ]; then
      local pname
      pname=$(ps -p "$process" -o comm= 2>/dev/null)

      if [ "$port" = "11434" ] && [ "$pname" = "ollama" ]; then
        log_info "Port 11434: Ollama already running (will reuse)"
        continue
      fi

      conflicts+=("Port $port: in use by $pname (PID $process)")
    fi
  done

  if [ ${#conflicts[@]} -gt 0 ]; then
    log_error "Port conflicts detected:"
    printf '  %s\n' "${conflicts[@]}"
    die "Free the above ports before continuing"
  fi
}
```

Note: Docker Compose maps container ports to host ports. If port 5432 is in use (as on this machine -- SSH tunnel), PostgreSQL's container port mapping `5432:5432` will fail. Either change the host port or detect and warn.

**Warning signs:**
- `docker compose up` fails with "address already in use"
- Specific containers fail to start while others work
- `lsof -iTCP -sTCP:LISTEN` shows unexpected processes on required ports

**Phase to address:**
Phase 1 (Diagnostics / detect.sh) -- comprehensive port conflict detection with process identification. Phase 2 (Wizard) -- offer alternative port mappings when conflicts detected.

---

### Pitfall 12: macOS Firewall Blocks Incoming Connections Without Notice

**What goes wrong:**
The macOS Application Firewall (ALF) blocks incoming connections to applications unless explicitly allowed. When the installer starts Docker/Colima or Nginx, macOS shows a firewall prompt ("Do you want to allow incoming connections?"). In non-interactive mode or over SSH, this prompt is invisible and the connection is silently blocked. Other machines on the LAN cannot reach the AGMind services.

Verified on this machine:
- Firewall: **enabled** (State = 1)
- Stealth mode: **on** (does not respond to ICMP/ping)
- Block all incoming: disabled

**Why it happens:**
The macOS firewall operates per-application. Each new version of Docker/Colima needs re-authorization. Users running the installer via SSH never see the GUI prompt.

**How to avoid:**
Detect firewall state and warn:

```bash
check_firewall() {
  local fw_state
  fw_state=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null)

  if echo "$fw_state" | grep -q "enabled"; then
    log_warn "macOS Firewall is enabled."
    log_warn "LAN clients may not be able to reach AGMind services."
    log_warn "You may see a firewall prompt for Docker/Colima."

    if [ "${DEPLOY_PROFILE:-}" = "lan" ]; then
      log_warn "For LAN profile: allow incoming connections for Docker when prompted."
      log_warn "Or run: sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add /opt/homebrew/bin/colima"
    fi
  fi
}
```

Do NOT automatically disable the firewall or add rules without user consent. Just warn clearly.

**Warning signs:**
- Services accessible from localhost but not from other machines on LAN
- `curl http://mac-ip:3000` times out from another machine
- Stealth mode prevents even ping from working

**Phase to address:**
Phase 1 (Diagnostics) -- detect and warn about firewall. Phase 7 (Health) -- test both localhost and LAN accessibility if LAN profile.

---

### Pitfall 13: Homebrew Path Differs Between Intel and Apple Silicon

**What goes wrong:**
Homebrew installs to different prefixes depending on architecture:
- **Apple Silicon (arm64):** `/opt/homebrew/`
- **Intel (x86_64):** `/usr/local/`

Scripts that hardcode either path break on the other architecture. This affects every tool installed via brew: `docker`, `colima`, `ollama`, `jq`, etc.

**Why it happens:**
Apple Silicon Macs use `/opt/homebrew` because `/usr/local` is reserved for non-Homebrew tools and has SIP (System Integrity Protection) restrictions. Scripts from Linux (where everything is in `/usr/local/bin`) or from Apple Silicon-only development hardcode paths.

**How to avoid:**
Always use `brew --prefix` to find the Homebrew installation:

```bash
BREW_PREFIX="$(brew --prefix 2>/dev/null)"
if [ -z "$BREW_PREFIX" ]; then
  die "Homebrew not found. Install from https://brew.sh"
fi

# Use for tool paths
DOCKER_BIN="${BREW_PREFIX}/bin/docker"
OLLAMA_BIN="${BREW_PREFIX}/opt/ollama/bin/ollama"
```

In LaunchAgent plists, use the detected prefix, not hardcoded paths:

```bash
# When generating plist templates
sed "s|__BREW_PREFIX__|${BREW_PREFIX}|g" template.plist > output.plist
```

**Warning signs:**
- "command not found" for `docker`, `ollama`, etc. in scripts
- Scripts work on Apple Silicon but fail on Intel (or vice versa)
- LaunchAgent scripts can't find brew-installed tools

**Phase to address:**
Phase 1 (Diagnostics / detect.sh) -- detect and export `BREW_PREFIX`. Phase 3 (Prerequisites) -- use it for all tool paths. Phase 9 (Complete) -- use it in LaunchAgent plist generation.

---

### Pitfall 14: Docker Compose v1 vs v2 Command Syntax

**What goes wrong:**
Docker Compose v1 (`docker-compose`, Python-based) and v2 (`docker compose`, Go plugin) have subtle differences:
- `docker-compose` (with hyphen) vs `docker compose` (with space)
- `--profile` flag behavior differs in edge cases
- `docker-compose` returns different exit codes for some operations
- `docker-compose` is deprecated and unmaintained

Verified on this machine:
- `docker compose version` = 5.1.0 (v2)
- `docker-compose` binary exists at `/opt/homebrew/bin/docker-compose` (likely a compatibility wrapper)

**Why it happens:**
Users may have old `docker-compose` installed via pip or brew. The command name looks similar but behavior diverges.

**How to avoid:**
Check for v2 and refuse v1:

```bash
verify_compose() {
  if ! docker compose version &>/dev/null; then
    if docker-compose version &>/dev/null; then
      die "docker-compose v1 detected but v2 required. Install: brew install docker-compose"
    fi
    die "Docker Compose not found"
  fi

  local version
  version=$(docker compose version --short 2>/dev/null)
  log_info "Docker Compose v${version} detected"
}
```

Always use `docker compose` (space) throughout the codebase. Never use `docker-compose` (hyphen).

**Warning signs:**
- `docker-compose` works but `docker compose` does not
- Profile activation behaves differently than expected
- `docker compose up` exits with unexpected errors on profile handling

**Phase to address:**
Phase 3 (Prerequisites / docker.sh) -- verify v2 is available. All modules must use `docker compose` with space.

---

### Pitfall 15: Colima Disk Cannot Be Shrunk After Creation

**What goes wrong:**
Colima's virtual disk size can only be **increased** after creation, never decreased. If the installer creates a Colima instance with 40GB disk and the user later needs 100GB, they can increase it. But if they accidentally create with 200GB, they cannot shrink it without destroying and recreating the VM (losing all Docker volumes).

The inverse is also dangerous: starting with too small a disk (like the 60GB default) means running out of space when pulling large Docker images or when PostgreSQL/Weaviate data grows.

**Why it happens:**
The Colima VM uses a sparse virtual disk (qcow2 or raw). The max size is set at creation time. Shrinking a virtual disk requires offline resizing of the filesystem inside the VM, which Colima does not support.

**How to avoid:**
Start generous because there is no downside (sparse file):

```bash
start_colima() {
  if colima status &>/dev/null; then
    log_info "Colima already running"
    # Check if disk is sufficient
    local current_disk
    current_disk=$(colima list -j 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['disk'])" 2>/dev/null || echo "0")
    if [ "$current_disk" -lt 60 ]; then
      log_warn "Colima disk is only ${current_disk}GB. Consider recreating with more."
    fi
    return 0
  fi

  colima start \
    --arch aarch64 \
    --cpu "${COLIMA_CPU:-4}" \
    --memory "${COLIMA_MEMORY:-8}" \
    --disk "${COLIMA_DISK:-100}" \
    --network-address
}
```

If Colima already exists with insufficient resources, offer to recreate:

```bash
if need_more_resources; then
  log_warn "Colima exists but has insufficient resources."
  log_warn "Recreating will DELETE all Docker volumes."
  confirm "Recreate Colima with recommended resources?" || die "Cannot continue with current resources"
  colima delete -f
  start_colima
fi
```

**Warning signs:**
- "no space left on device" inside Docker containers
- `colima list` shows disk usage near max
- Cannot pull new Docker images

**Phase to address:**
Phase 3 (Prerequisites / docker.sh) -- Colima creation with generous defaults. Must warn about consequences of recreation.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Hardcoding `/opt/homebrew` paths | Faster to write | Breaks on Intel Macs | Never -- always use `$(brew --prefix)` |
| Using GNU sed via `brew install gnu-sed` | Familiar syntax | Adds mandatory dependency, confuses `gsed` vs `sed` | Never for the installer itself -- use BSD `sed -i ''` |
| Skipping plist validation | Faster plist generation | Silent failures in LaunchAgents | Never -- always `plutil -lint` |
| Running entire installer as sudo | Simpler permissions | User-context operations (LaunchAgents, CLI) break | Never -- sudo only for `/opt/` creation, then chown |
| Hardcoding Colima socket path | Works for default profile | Breaks for custom Colima profiles | Never -- use docker context |
| Using bash 4+ features | Cleaner code (associative arrays, mapfile) | Breaks on stock macOS bash 3.2 | Never -- target `/bin/bash` 3.2 |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Dify to Ollama | Using `http://ollama:11434` (Docker network) | Use `http://host.docker.internal:11434` with `extra_hosts` |
| Open WebUI to Ollama | Not adding `extra_hosts` in Colima | Always add `extra_hosts: ["host.docker.internal:host-gateway"]` |
| LaunchAgent to Docker | Using bare `docker` command | Use full path: `/opt/homebrew/bin/docker` (or `$(brew --prefix)/bin/docker`) |
| Backup script to /opt/agmind | Running as user, files owned by root | Chown /opt/agmind to user after creation |
| Colima to Docker socket | Expecting `/var/run/docker.sock` to exist | Use docker context or detect actual socket location |
| Ollama to Metal GPU | Assuming Metal is available (Intel Macs) | Check `system_profiler SPDisplaysDataType` for Metal support -- Intel Macs have limited/no Metal for ML |
| brew services to launchd | Not waiting for service to actually start | Poll the health endpoint (`localhost:11434/api/tags`) with timeout |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Colima with 2GB RAM default | Random container OOM kills, slow responses | Allocate based on stack needs (minimum 6GB) | Immediately with full stack |
| Ollama + Colima competing for RAM | System swapping, model inference takes minutes | Calculate memory split: Ollama gets model size + 2GB, Docker gets 4-8GB, macOS gets 4GB | When model exceeds remaining memory |
| Docker bind mounts on macOS | 10-100x slower than Linux for filesystem-heavy operations | Use named volumes for databases (PostgreSQL, Weaviate) | Immediately with database workloads |
| Colima with VZ framework (default on AS) vs QEMU | VZ is faster but has networking quirks | Default to VZ, test thoroughly, fall back to QEMU for networking issues | Network-dependent operations |
| Checking `docker compose ps` in a loop for health | CPU spin, slow compose command on macOS | Use `docker events` or check individual container health | With many containers (10+) |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Storing credentials in `/opt/agmind/credentials.txt` readable by all | Any user on the Mac can read database passwords | `chmod 600 /opt/agmind/credentials.txt` and `chown $USER` |
| Running installer scripts as root when not needed | Root-owned files, privilege escalation surface | Only sudo for `/opt/` creation, then drop privileges |
| Docker socket accessible to user | Any process as user can control Docker | Acceptable on single-user Mac, but document the risk |
| Ollama binding to `0.0.0.0:11434` | LAN users can query the LLM directly | Bind Ollama to `127.0.0.1:11434` only via `OLLAMA_HOST=127.0.0.1:11434` |
| `.env` file with secrets in world-readable location | Credentials exposed | `chmod 600 /opt/agmind/.env` |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| No progress indicator during model download | User thinks installer is frozen (70B model = 40GB download) | Show download progress from `ollama pull` output, estimate time |
| Silent failure on insufficient RAM | User gets cryptic Docker errors hours later | Fail fast in preflight with clear "need X GB RAM for Y model" |
| Colima starting without network-address | LAN clients can't reach services | Always use `colima start --network-address` for LAN profile |
| Firewall prompt appearing during non-interactive install | Script blocks waiting for GUI input that nobody sees | Detect non-interactive mode and warn about firewall pre-emptively |
| No clear log location | User can't debug failures | Always tell user: "Logs at /opt/agmind/install.log" |
| Installing GNU coreutils as a "fix" for BSD tools | Pollutes user's system, may conflict with system tools | Write BSD-compatible code, don't install GNU tools |

## "Looks Done But Isn't" Checklist

- [ ] **Port check:** Verified ports are free, but didn't check if Docker mapping conflicts with ports inside Colima VM (not the host)
- [ ] **Ollama running:** Port 11434 responds, but didn't verify Metal GPU is actually being used (Intel Mac might fall back to CPU-only)
- [ ] **Docker socket:** `docker ps` works, but didn't test `docker compose` (compose might use a different context)
- [ ] **LaunchAgent loaded:** `launchctl load` succeeded, but didn't verify the job actually runs on schedule (test with `launchctl kickstart`)
- [ ] **Colima started:** `colima status` shows running, but didn't verify DNS resolution works inside containers
- [ ] **host.docker.internal:** `nslookup` works inside container, but `/etc/hosts` entry missing -- some apps check hosts file directly
- [ ] **Backup working:** Script runs manually, but LaunchAgent can't find `docker` because PATH is minimal
- [ ] **Idempotency:** Install completes on first run, but re-running overwrites user's customized `.env` or `docker-compose.yml`
- [ ] **Uninstaller:** Removes /opt/agmind, but doesn't clean up LaunchAgents, Colima instance, or brew-installed packages
- [ ] **Disk space check:** Passed preflight, but didn't account for Colima VM overhead (qcow2 file can be 2-3x actual data size)

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| BSD sed corrupted config file | LOW | Regenerate from template: `lib/config.sh` can regenerate all config files |
| LaunchAgent silently not running | LOW | `plutil -lint`, fix plist, `launchctl unload && launchctl load` |
| Colima OOM killing containers | MEDIUM | `colima stop`, edit `~/.colima/default/colima.yaml` to increase memory, `colima start` |
| Colima disk full | HIGH | `colima delete` (loses all data), recreate with larger disk, restore from backup |
| Ollama port conflict with App version | LOW | Kill Ollama.app process, switch to brew version: `brew install ollama && brew services start ollama` |
| /opt/agmind permissions wrong | LOW | `sudo chown -R $(whoami):staff /opt/agmind` |
| Docker socket not found after reboot | LOW | `colima start` (re-creates socket), or `docker context use colima` |
| host.docker.internal not resolving | LOW | Add `extra_hosts` to docker-compose.yml, `docker compose up -d --force-recreate` |
| Stock bash 3.2 script failure | HIGH | Rewrite affected module to avoid bash 4+ features -- this is a code fix, not a runtime fix |
| Firewall blocking LAN access | LOW | System Preferences > Firewall > allow Docker/Colima, or `sudo socketfilterfw --add` |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| BSD vs GNU tools | Phase 1 (common.sh wrappers) | ShellCheck CI + BATS test on stock `/bin/bash` |
| Bash 3.2 limitations | Phase 1 (common.sh) + CI | `/bin/bash -n install.sh` syntax check in CI |
| host.docker.internal | Phase 5 (compose templates) | Phase 7 health check: container-to-host curl |
| Docker socket detection | Phase 3 (docker.sh) | BATS test: detect_docker_socket works for both runtimes |
| Ollama already running | Phase 1 (detect.sh) + Phase 4 (ollama.sh) | Preflight detects and reuses existing instance |
| set -euo pipefail traps | Phase 1 (common.sh patterns) | All BATS tests run with `set -euo pipefail` |
| LaunchAgent environment | Phase 9 (plist generation) | `plutil -lint` + `launchctl kickstart` verification |
| /opt/agmind ownership | Phase 3 (directory setup) | BATS test: non-root user can write to /opt/agmind |
| Colima memory defaults | Phase 2 (wizard) + Phase 3 (docker.sh) | Check `colima list` shows calculated memory |
| Disk space calculation | Phase 1 (detect.sh) + Phase 2 (wizard) | Model-aware disk check in preflight |
| Port conflicts | Phase 1 (detect.sh) | lsof check for all required ports with process identification |
| Firewall warnings | Phase 1 (detect.sh) | Detect and warn, verify in Phase 7 health |
| Homebrew path differences | Phase 1 (detect.sh) | `BREW_PREFIX` exported and used everywhere |
| Docker Compose v1 vs v2 | Phase 3 (docker.sh) | `docker compose version` check, reject v1 |
| Colima disk size | Phase 3 (docker.sh) | Generous default (100GB sparse), warn if too small |

## Sources

- Direct verification on macOS 26.3 (Build 25D125), Apple M4 Pro, 24GB RAM, Homebrew at /opt/homebrew
- `/bin/bash --version`: GNU bash 3.2.57(1)-release (arm64-apple-darwin25)
- Colima 0.10.1 behavior verified: socket at `~/.colima/default/docker.sock`, docker context system
- Ollama 0.17.7 verified: brew service, LaunchAgent at `~/Library/LaunchAgents/homebrew.mxcl.ollama.plist`
- Docker Compose 5.1.0 verified: `docker compose` (space) syntax
- macOS firewall verified: enabled with stealth mode, per-application rules
- AirPlay Receiver verified: occupies ports 5000 and 7000 via ControlCenter
- host.docker.internal verified: DNS resolves (192.168.5.2) but not in /etc/hosts without extra_hosts
- BSD tool behavior verified: `sed -i` requires `''`, `grep -P` unavailable, `timeout` missing, `stat --format` unavailable

---
*Pitfalls research for: AGMind macOS Installer*
*Researched: 2026-03-20*
