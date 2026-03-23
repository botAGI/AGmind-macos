# Roadmap: AGMind macOS Installer

## Overview

The AGMind macOS Installer is a 7-phase project that delivers a one-command bash installer for the full AI/RAG stack on macOS. The dependency chain is strict: a BSD-safe foundation layer must exist before any module is written, system detection feeds the interactive wizard, the wizard and infrastructure setup (Docker + Ollama) feed config generation (the integration bottleneck), config generation feeds stack deployment, and the CLI is built last as the day-2 operations surface. Tests are built alongside each module, not as a separate phase.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Foundation** - BSD-safe common library, install.sh orchestrator skeleton, BATS test infrastructure
- [x] **Phase 2: Detection** - System detection and preflight validation for macOS hardware and software
- [x] **Phase 3: Wizard** - Interactive and non-interactive configuration with RAM-aware model recommendations
- [ ] **Phase 4: Docker and Ollama** - Docker runtime setup (Colima or Desktop) and native Ollama installation
- [ ] **Phase 5: Config Generation** - Template rendering and config file generation from all upstream variables
- [ ] **Phase 6: Stack Deployment** - Container orchestration, health verification, model pull, LaunchAgent scheduling
- [ ] **Phase 7: CLI** - Post-install agmind command-line tool for day-2 operations

## Phase Details

### Phase 1: Foundation
**Goal**: Every subsequent module can be written using safe, portable, tested building blocks without worrying about BSD/Bash 3.2 incompatibilities
**Depends on**: Nothing (first phase)
**Requirements**: FNDTN-01, FNDTN-02, FNDTN-03, FNDTN-04, FNDTN-05, FNDTN-06, TEST-01, TEST-02, TEST-03
**Success Criteria** (what must be TRUE):
  1. Running `bash install.sh` on stock macOS bash 3.2.57 prints phase banners and exits cleanly (no syntax errors, no GNU tool invocations)
  2. `lib/common.sh` can be sourced and its logging functions (`log_info`, `log_warn`, `log_error`, `log_step`) produce formatted output to both terminal and log file
  3. `_atomic_sed()` correctly performs in-place substitution on a test file using BSD sed (no backup files created, no GNU sed required)
  4. Re-running `install.sh` on an already-installed system does not corrupt existing files or state (idempotency guard)
  5. BATS test suite runs under `/bin/bash` 3.2 with PATH-prepended stub executables for mocking external commands, and `tests/unit/test_common.bats` passes
**Plans:** 2 plans

Plans:
- [ ] 01-01-PLAN.md — lib/common.sh utilities and install.sh orchestrator skeleton
- [ ] 01-02-PLAN.md — BATS test infrastructure and comprehensive tests for lib/common.sh

### Phase 2: Detection
**Goal**: The installer knows everything about the target system before asking the user any questions or installing anything
**Depends on**: Phase 1
**Requirements**: DETECT-01, DETECT-02, DETECT-03, DETECT-04, DETECT-05, DETECT-06, DETECT-07, DETECT-08, DETECT-09
**Success Criteria** (what must be TRUE):
  1. Running preflight on a qualifying Mac (macOS 13+, 8GB+ RAM, 30GB+ free disk) prints all `[PASS]` checks and proceeds
  2. Running preflight on a system that fails any hard requirement (e.g., macOS 12, 4GB RAM, port 80 in use) prints `[FAIL]` with a remediation hint and aborts the install
  3. `DETECTED_OS`, `DETECTED_ARCH`, `DETECTED_RAM_GB`, `DETECTED_DISK_FREE_GB`, `BREW_PREFIX` are all correctly exported and available to downstream modules
  4. Docker runtime detection correctly identifies Docker Desktop socket, Colima socket, or absence of both via actual connectivity test (not just file existence)
  5. `tests/unit/test_detect.bats` passes with mocked system commands
**Plans:** 2 plans

Plans:
- [x] 02-01-PLAN.md — lib/detect.sh detection functions and preflight aggregator wired into install.sh
- [ ] 02-02-PLAN.md — Mock executables and comprehensive BATS tests for lib/detect.sh

### Phase 3: Wizard
**Goal**: The user (or automation) has chosen all deployment parameters and the installer has validated those choices against system capabilities
**Depends on**: Phase 2
**Requirements**: WIZ-01, WIZ-02, WIZ-03, WIZ-04
**Success Criteria** (what must be TRUE):
  1. Interactive wizard presents 7 questions in order (profile, LLM model, embed model, vector DB, ETL mode, monitoring, backup) with sensible defaults and accepts user input
  2. LLM model menu shows a RAM-aware recommendation (e.g., "Recommended for your 32GB system: qwen2.5:14b") derived from `DETECTED_RAM_GB`
  3. Setting `NON_INTERACTIVE=1` with env vars (`DEPLOY_PROFILE`, `LLM_MODEL`, `EMBED_MODEL`, `VECTOR_DB`, etc.) skips all prompts and produces identical `WIZARD_*` exports
  4. All wizard choices are exported as `WIZARD_*` variables consumable by config.sh
**Plans:** 1 plan

Plans:
- [x] 03-01-PLAN.md — lib/wizard.sh interactive wizard, model menu, non-interactive mode, WIZARD_* exports, and BATS tests

### Phase 4: Docker and Ollama
**Goal**: A working Docker runtime and a native Ollama instance are both running and ready to accept commands
**Depends on**: Phase 2
**Requirements**: DOCKER-01, DOCKER-02, DOCKER-03, DOCKER-04, DOCKER-05, DOCKER-06, OLLAMA-01, OLLAMA-02, OLLAMA-03, OLLAMA-04
**Success Criteria** (what must be TRUE):
  1. On a Mac with no Docker runtime, the installer auto-installs Colima and docker CLI via Homebrew, starts Colima with arch-appropriate flags, and `docker info` succeeds
  2. On a Mac with Docker Desktop already running, the installer detects it and skips Colima installation
  3. `docker compose version` confirms Compose v2 is available; if not, the installer aborts with a clear remediation message
  4. Ollama is installed via Homebrew (or existing install is reused), `brew services start ollama` succeeds, and `http://localhost:11434/api/tags` responds within 60 seconds
  5. `/var/run/docker.sock` exists (symlinked if necessary) and `DOCKER_RUNTIME` is exported for downstream use
**Plans:** 2 plans

Plans:
- [ ] 04-01-PLAN.md — lib/docker.sh with Docker runtime detection, Colima install/start, socket fix, Compose v2 verify, and BATS tests
- [ ] 04-02-PLAN.md — lib/ollama.sh with native Ollama install/start/wait, BATS tests, and install.sh phase wiring

### Phase 5: Config Generation
**Goal**: All configuration files needed to launch the stack are rendered from templates with correct values for the user's choices and system
**Depends on**: Phase 3, Phase 4
**Requirements**: CONFIG-01, CONFIG-02, CONFIG-03, CONFIG-04, CONFIG-05, CONFIG-06, CONFIG-07
**Success Criteria** (what must be TRUE):
  1. `/opt/agmind/.env` exists and contains `OLLAMA_API_BASE=http://host.docker.internal:11434` plus all wizard-derived values for the chosen profile (LAN or Offline)
  2. Generated `docker-compose.yml` includes `extra_hosts: ["host.docker.internal:host-gateway"]` on every service that contacts Ollama, and excludes ollama/vllm/tei/authelia services entirely
  3. `docker-compose.yml` activates correct `COMPOSE_PROFILES` for the chosen vector DB, ETL mode, and monitoring options
  4. `nginx.conf` is rendered from template with correct upstream addresses
  5. `/opt/agmind/credentials.txt` exists with mode 600, containing all generated secrets (passwords, API keys from `/dev/urandom`)
**Plans:** 2 plans

Plans:
- [ ] 05-01-PLAN.md — Templates (versions.env, env profiles, nginx.conf, docker-compose.yml) and lib/config.sh with template rendering, secret generation, and phase function
- [ ] 05-02-PLAN.md — Comprehensive BATS tests for CONFIG-01 through CONFIG-07 and install.sh wiring

### Phase 6: Stack Deployment
**Goal**: The full RAG stack is running, healthy, models are pulled, and scheduled maintenance is active
**Depends on**: Phase 5
**Requirements**: DEPLOY-01, DEPLOY-02, DEPLOY-03, DEPLOY-04, DEPLOY-05, DEPLOY-06, LAUNCH-01, LAUNCH-02, LAUNCH-03, LAUNCH-04
**Success Criteria** (what must be TRUE):
  1. `docker compose up -d` brings up all profile-selected containers and every container passes its health check within the polling timeout
  2. Ollama API responds at `http://localhost:11434/api/tags` and the chosen LLM and embedding models are pulled and listed
  3. Open WebUI admin account is initialized via API and the web interface is accessible at `http://localhost:3000`
  4. LaunchAgent plists for backup and health are installed in `~/Library/LaunchAgents/`, pass `plutil -lint`, include explicit PATH with `/opt/homebrew/bin`, and are loaded via `launchctl`
  5. Installer prints a final summary showing service URLs, credentials file path, and next-step instructions
**Plans:** 4 plans

Plans:
- [ ] 06-01-PLAN.md — Deploy modules: compose.sh, health.sh, models.sh, openwebui.sh with install.sh phase wiring
- [ ] 06-02-PLAN.md — LaunchAgent modules: plist templates, lib/backup.sh, scripts/backup.sh, scripts/health-gen.sh
- [ ] 06-03-PLAN.md — BATS tests for deploy modules (compose, health, models, openwebui) with mock extensions
- [ ] 06-04-PLAN.md — BATS tests for LaunchAgent module (backup) with launchctl and plutil mocks

### Phase 7: CLI
**Goal**: Users can manage the AGMind stack day-to-day without remembering Docker or Homebrew commands
**Depends on**: Phase 6
**Requirements**: CLI-01, CLI-02, CLI-03, CLI-04, CLI-05, CLI-06, CLI-07, CLI-08
**Success Criteria** (what must be TRUE):
  1. Running `agmind status` shows all Docker container states, Ollama brew service status, and local IP address
  2. `agmind stop` shuts down all containers and stops Ollama; `agmind start` brings everything back up in correct order (Ollama first, then Docker Compose)
  3. `agmind doctor` runs preflight-style checks on the live system and prints `[PASS/WARN/FAIL]` for each
  4. `agmind backup` creates a timestamped backup in `~/Library/Application Support/AGMind/backups/`
  5. `agmind uninstall` removes all containers, volumes, LaunchAgents, and `/opt/agmind/` after user confirms the prompt
**Plans:** 2 plans

Plans:
- [ ] 07-01-PLAN.md — scripts/agmind.sh CLI dispatcher with all commands and install.sh phase_9_complete wiring
- [ ] 07-02-PLAN.md — Mock enhancements and comprehensive BATS tests for CLI-01 through CLI-08

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7

Note: Phase 3 (Wizard) and Phase 4 (Docker and Ollama) both depend on Phase 2 but not on each other. However, Phase 5 depends on both, so they execute sequentially (3 then 4) before Phase 5 begins.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation | 2/2 | Complete | 2026-03-21 |
| 2. Detection | 1/2 | In Progress | - |
| 3. Wizard | 0/1 | Not started | - |
| 4. Docker and Ollama | 0/2 | Not started | - |
| 5. Config Generation | 0/2 | Not started | - |
| 6. Stack Deployment | 0/4 | Not started | - |
| 7. CLI | 0/2 | Not started | - |
