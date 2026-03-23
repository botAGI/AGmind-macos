# Requirements: AGMind macOS Installer

**Defined:** 2026-03-20
**Core Value:** One `bash install.sh` command deploys a full local AI RAG stack on macOS with native Metal-accelerated Ollama inference

## v1 Requirements

### Foundation

- [x] **FNDTN-01**: Installer runs under `/bin/bash` 3.2.57 (stock macOS bash) without errors
- [x] **FNDTN-02**: `lib/common.sh` provides `log_info`, `log_warn`, `log_error`, `log_step` logging helpers used by all modules
- [x] **FNDTN-03**: `lib/common.sh` provides BSD-safe `_atomic_sed()` wrapper (`sed -i '' -E`) used for all config substitution
- [x] **FNDTN-04**: `install.sh` orchestrates 9 phases with clear per-phase banners and exit-on-failure
- [x] **FNDTN-05**: All scripts run with `set -euo pipefail` and trap errors with file/line context
- [x] **FNDTN-06**: Every phase is idempotent — re-running install.sh on an existing setup does not corrupt it

### Detection

- [x] **DETECT-01**: `detect_os()` exports `DETECTED_OS=macos`, `DETECTED_OS_VERSION`, `DETECTED_ARCH` (arm64 or x86_64)
- [x] **DETECT-02**: `detect_ram()` uses `sysctl hw.memsize` and exports `DETECTED_RAM_GB`
- [x] **DETECT-03**: `detect_disk()` uses `df -k /` and exports `DETECTED_DISK_FREE_GB`
- [x] **DETECT-04**: `detect_ports()` uses `lsof -iTCP -sTCP:LISTEN` to check ports 80, 443, 3000, 11434 and exports conflicts
- [x] **DETECT-05**: `detect_docker()` tests connectivity (not just file existence) for both Docker Desktop (`~/.docker/run/docker.sock`) and Colima (`~/.colima/default/docker.sock`) sockets
- [x] **DETECT-06**: `detect_ollama()` checks if native Ollama is already running on port 11434
- [x] **DETECT-07**: `detect_homebrew()` checks if brew is installed and exports `BREW_PREFIX` (`/opt/homebrew` or `/usr/local`)
- [x] **DETECT-08**: `preflight_checks()` outputs `[PASS/WARN/FAIL]` for each check; FAIL aborts install, WARN prompts user
- [x] **DETECT-09**: Preflight validates: macOS 13+, ARM64 or x86_64, RAM >= 8GB, Disk >= 30GB, ports 80 and 3000 free

### Wizard

- [x] **WIZ-01**: Interactive wizard asks 7 questions in order: profile, LLM model, embed model, vector DB, ETL mode, monitoring, backup
- [x] **WIZ-02**: LLM model menu shows RAM-aware recommendation based on `DETECTED_RAM_GB` (e.g. qwen2.5:14b for 32GB)
- [x] **WIZ-03**: Non-interactive mode reads all choices from env vars (`DEPLOY_PROFILE`, `LLM_MODEL`, `EMBED_MODEL`, `VECTOR_DB`, etc.) when `NON_INTERACTIVE=1`
- [x] **WIZ-04**: Wizard exports all choices as `WIZARD_*` variables consumed by `config.sh`

### Docker Setup

- [x] **DOCKER-01**: `detect_docker_runtime()` auto-detects Docker Desktop or Colima by testing socket connectivity with `docker info`
- [x] **DOCKER-02**: `install_colima()` installs Colima and docker CLI via `brew install colima docker` if no Docker runtime found
- [x] **DOCKER-03**: `start_colima()` starts Colima with `--arch aarch64` (Apple Silicon) or `--arch x86_64` (Intel), 8 CPU, 12GB RAM, 60GB disk defaults
- [x] **DOCKER-04**: `fix_docker_socket()` creates symlink `/var/run/docker.sock -> active socket path` when default path unavailable
- [x] **DOCKER-05**: `verify_compose()` confirms `docker compose version` returns v2; aborts with remediation hint if not
- [x] **DOCKER-06**: `DOCKER_RUNTIME` env var overrides auto-detection (`colima` or `desktop`)

### Ollama Setup

- [x] **OLLAMA-01**: `install_ollama()` installs Ollama via `brew install ollama` (idempotent — skips if already installed)
- [x] **OLLAMA-02**: `start_ollama()` starts Ollama via `brew services start ollama` and waits for readiness
- [x] **OLLAMA-03**: `wait_for_ollama()` polls `http://localhost:11434/api/tags` in a bash loop (no `timeout` command) with 60-second limit
- [x] **OLLAMA-04**: Ollama runs natively on the host (never in Docker); Docker containers reach it via `http://host.docker.internal:11434`

### Configuration

- [x] **CONFIG-01**: `config.sh` generates `/opt/agmind/.env` from `env.lan.template` or `env.offline.template` based on `DEPLOY_PROFILE`
- [x] **CONFIG-02**: Generated `.env` sets `OLLAMA_API_BASE=http://host.docker.internal:11434` and `OLLAMA_HOST=http://host.docker.internal:11434`
- [x] **CONFIG-03**: `config.sh` generates `nginx.conf` from `nginx.conf.template`
- [x] **CONFIG-04**: `config.sh` generates final `docker-compose.yml` with correct `COMPOSE_PROFILES` for chosen vector DB, ETL mode, and monitoring
- [x] **CONFIG-05**: All services in `docker-compose.yml` that call `host.docker.internal` include `extra_hosts: - "host.docker.internal:host-gateway"` for Colima compatibility
- [x] **CONFIG-06**: All secrets (passwords, API keys) generated via `/dev/urandom` and written to `/opt/agmind/credentials.txt` (chmod 600)
- [x] **CONFIG-07**: `docker-compose.yml` excludes ollama, vllm, tei, and authelia services entirely

### Stack Deployment

- [x] **DEPLOY-01**: `compose.sh` runs `docker compose up -d` with correct profile flags for chosen services
- [x] **DEPLOY-02**: `health.sh` waits for all containers to pass health checks before proceeding (polling loop, no `timeout`)
- [x] **DEPLOY-03**: `health.sh` independently verifies Ollama API at `http://localhost:11434/api/tags`
- [x] **DEPLOY-04**: `models.sh` runs `ollama pull <LLM_MODEL>` and `ollama pull <EMBED_MODEL>` on the host with progress output
- [x] **DEPLOY-05**: `openwebui.sh` performs Open WebUI admin user initialization via API after stack is healthy
- [x] **DEPLOY-06**: Installer prints final summary with URLs, credentials path, and next-step instructions

### LaunchAgents

- [x] **LAUNCH-01**: `backup.sh` generates and installs `~/Library/LaunchAgents/com.agmind.backup.plist` from template
- [x] **LAUNCH-02**: `health-gen.sh` generates and installs `~/Library/LaunchAgents/com.agmind.health.plist` from template
- [x] **LAUNCH-03**: All LaunchAgent plists include explicit `EnvironmentVariables` dict with `PATH` containing `/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin` to avoid tool-not-found failures
- [x] **LAUNCH-04**: LaunchAgents loaded via `launchctl load ~/Library/LaunchAgents/com.agmind.*.plist`

### CLI Tool

- [x] **CLI-01**: `scripts/agmind.sh` installed to `/usr/local/bin/agmind` (or `/opt/agmind/bin/agmind` with PATH hint)
- [x] **CLI-02**: `agmind status` shows all Docker container states plus Ollama brew service status and local IP via `ipconfig getifaddr en0`
- [x] **CLI-03**: `agmind doctor` runs preflight checks on the running system and shows `[PASS/WARN/FAIL]` for each
- [x] **CLI-04**: `agmind stop` runs `docker compose down` then `brew services stop ollama`
- [x] **CLI-05**: `agmind start` runs `brew services start ollama`, waits for readiness, then `docker compose up -d`
- [x] **CLI-06**: `agmind logs [service]` passes through to `docker logs`
- [x] **CLI-07**: `agmind backup` runs manual backup to `~/Library/Application Support/AGMind/backups/`
- [x] **CLI-08**: `agmind uninstall` removes all containers, volumes, LaunchAgents, and `/opt/agmind/` after confirmation prompt

### Testing

- [x] **TEST-01**: BATS test suite (`tests/`) exists for all `lib/*.sh` modules
- [x] **TEST-02**: Unit tests mock external commands (`brew`, `docker`, `ollama`, `sysctl`, `lsof`) via PATH-prepended stub executables
- [x] **TEST-03**: Tests pass when run with `/bin/bash` 3.2 (no bash 4+ features in test files)

## v2 Requirements

### Advanced Deployment
- **DEPLOY-v2-01**: TLS / self-signed certificate generation for LAN profile
- **DEPLOY-v2-02**: VPN profile (Tailscale or WireGuard integration)
- **DEPLOY-v2-03**: Offline/air-gapped Homebrew package caching

### Advanced CLI
- **CLI-v2-01**: `agmind update` — pull new Docker images and restart services with Dify DB migration handling
- **CLI-v2-02**: `agmind restore` — restore from backup with service stop/start
- **CLI-v2-03**: `agmind restart [service]` — restart individual service

### Monitoring
- **MON-v2-01**: Automated health report generation to `/opt/agmind/logs/health.json`
- **MON-v2-02**: Alert on disk space < 10GB remaining

## Out of Scope

| Feature | Reason |
|---------|--------|
| vLLM / TEI | Requires CUDA — not available on macOS |
| Authelia 2FA | Overkill for local-only deployment |
| UFW / fail2ban | Not applicable on macOS |
| Let's Encrypt / Certbot | Mac Studio not on public IP |
| Reverse SSH tunnel | Not in v1 |
| SOPS encryption | Not in v1 |
| Dify API automation | Out of scope |
| VPS / public server profiles | macOS not suited for public server deployment |
| GUI installer | CLI only in v1 |
| Multi-node install | Single machine only |
| gnu-sed / coreutils dependency | Must work on stock macOS |
| `agmind update` with Dify DB migration | Complex version-specific logic, deferred to v2 |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| FNDTN-01 | Phase 1 | Complete |
| FNDTN-02 | Phase 1 | Complete |
| FNDTN-03 | Phase 1 | Complete |
| FNDTN-04 | Phase 1 | Complete |
| FNDTN-05 | Phase 1 | Complete |
| FNDTN-06 | Phase 1 | Complete |
| DETECT-01 | Phase 2 | Complete |
| DETECT-02 | Phase 2 | Complete |
| DETECT-03 | Phase 2 | Complete |
| DETECT-04 | Phase 2 | Complete |
| DETECT-05 | Phase 2 | Complete |
| DETECT-06 | Phase 2 | Complete |
| DETECT-07 | Phase 2 | Complete |
| DETECT-08 | Phase 2 | Complete |
| DETECT-09 | Phase 2 | Complete |
| WIZ-01 | Phase 3 | Complete |
| WIZ-02 | Phase 3 | Complete |
| WIZ-03 | Phase 3 | Complete |
| WIZ-04 | Phase 3 | Complete |
| DOCKER-01 | Phase 4 | Complete |
| DOCKER-02 | Phase 4 | Complete |
| DOCKER-03 | Phase 4 | Complete |
| DOCKER-04 | Phase 4 | Complete |
| DOCKER-05 | Phase 4 | Complete |
| DOCKER-06 | Phase 4 | Complete |
| OLLAMA-01 | Phase 4 | Complete |
| OLLAMA-02 | Phase 4 | Complete |
| OLLAMA-03 | Phase 4 | Complete |
| OLLAMA-04 | Phase 4 | Complete |
| CONFIG-01 | Phase 5 | Complete |
| CONFIG-02 | Phase 5 | Complete |
| CONFIG-03 | Phase 5 | Complete |
| CONFIG-04 | Phase 5 | Complete |
| CONFIG-05 | Phase 5 | Complete |
| CONFIG-06 | Phase 5 | Complete |
| CONFIG-07 | Phase 5 | Complete |
| DEPLOY-01 | Phase 6 | Complete |
| DEPLOY-02 | Phase 6 | Complete |
| DEPLOY-03 | Phase 6 | Complete |
| DEPLOY-04 | Phase 6 | Complete |
| DEPLOY-05 | Phase 6 | Complete |
| DEPLOY-06 | Phase 6 | Complete |
| LAUNCH-01 | Phase 6 | Complete |
| LAUNCH-02 | Phase 6 | Complete |
| LAUNCH-03 | Phase 6 | Complete |
| LAUNCH-04 | Phase 6 | Complete |
| CLI-01 | Phase 7 | Complete |
| CLI-02 | Phase 7 | Complete |
| CLI-03 | Phase 7 | Complete |
| CLI-04 | Phase 7 | Complete |
| CLI-05 | Phase 7 | Complete |
| CLI-06 | Phase 7 | Complete |
| CLI-07 | Phase 7 | Complete |
| CLI-08 | Phase 7 | Complete |
| TEST-01 | Phase 1 | Complete |
| TEST-02 | Phase 1 | Complete |
| TEST-03 | Phase 1 | Complete |

**Coverage:**
- v1 requirements: 57 total
- Mapped to phases: 57
- Unmapped: 0

---
*Requirements defined: 2026-03-20*
*Last updated: 2026-03-20 after roadmap creation*
