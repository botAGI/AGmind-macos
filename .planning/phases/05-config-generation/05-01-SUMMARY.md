---
phase: 05-config-generation
plan: 01
subsystem: infra
tags: [bash, docker-compose, nginx, sed, template-rendering, secrets, config-generation]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: "_atomic_sed, die, log_info, ensure_directory, AGMIND_DIR from lib/common.sh"
  - phase: 03-wizard
    provides: "WIZARD_* exported variables (7 user choices)"
  - phase: 04-docker-and-ollama
    provides: "DOCKER_RUNTIME variable for socket path detection"
provides:
  - "5 template files: versions.env, env.lan.template, env.offline.template, nginx.conf.template, docker-compose.yml"
  - "lib/config.sh with phase_5_configuration() entry point"
  - "Secret generation and idempotent credential management"
  - "Template rendering pipeline via _atomic_sed with pipe delimiter"
affects: [06-stack-deployment, testing]

# Tech tracking
tech-stack:
  added: []
  patterns: [template-copy-then-substitute, idempotent-secrets, compose-profiles]

key-files:
  created:
    - templates/versions.env
    - templates/env.lan.template
    - templates/env.offline.template
    - templates/nginx.conf.template
    - templates/docker-compose.yml
    - lib/config.sh
  modified:
    - install.sh

key-decisions:
  - "Pipe delimiter (|) for all _atomic_sed calls to avoid URL slash conflicts"
  - "etl-extended as Compose profile name (distinct from Dify ETL_TYPE=unstructured)"
  - "sudo tee for credentials.txt write (directory may be root-owned initially)"
  - "Portainer only for v1 monitoring profile (lightweight container management)"
  - "{{DOCKER_SOCKET_PATH}} is the only placeholder in docker-compose.yml (rest uses Docker Compose ${VAR} interpolation)"

patterns-established:
  - "Template rendering: cp template to output, then _atomic_sed each {{PLACEHOLDER}}"
  - "Secret management: check credentials.txt existence, load if present, generate if absent"
  - "Compose profiles: comma-separated string built from wizard choices"

requirements-completed: [CONFIG-01, CONFIG-02, CONFIG-03, CONFIG-04, CONFIG-05, CONFIG-06, CONFIG-07]

# Metrics
duration: 4min
completed: 2026-03-21
---

# Phase 5 Plan 01: Config Generation Summary

**Template files and lib/config.sh for rendering .env, nginx.conf, docker-compose.yml from wizard choices with idempotent /dev/urandom secret generation**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-21T21:07:10Z
- **Completed:** 2026-03-21T21:11:20Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments
- Created 5 template files with {{PLACEHOLDER}} markers for secrets and wizard choices, static Ollama URLs, and macOS-specific Docker Compose (no ollama/vllm/tei/authelia)
- Built lib/config.sh with 9 functions: secret generation, credential management, COMPOSE_PROFILES assembly, template rendering, and phase_5_configuration() entry point
- Wired config.sh source into install.sh orchestrator
- All extra_hosts directives present on 6 Ollama-contacting services (api, worker, worker_beat, open-webui, sandbox, plugin_daemon)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create template files** - `b536f46` (feat)
2. **Task 2: Create lib/config.sh** - `8cdeb23` (feat)

## Files Created/Modified
- `templates/versions.env` - Pinned Docker image versions for all stack services
- `templates/env.lan.template` - LAN profile .env template with 14 {{PLACEHOLDER}} markers
- `templates/env.offline.template` - Offline profile .env template (same structure, different header)
- `templates/nginx.conf.template` - Nginx reverse proxy: upstreams for dify-api, dify-web, open-webui on port 80
- `templates/docker-compose.yml` - macOS Docker Compose: 14 services, 4 profiles, no excluded services
- `lib/config.sh` - Template rendering, secret generation, phase function (240 lines, 9 functions)
- `install.sh` - Added `source lib/config.sh` for Phase 5 wiring

## Decisions Made
- Used `|` (pipe) as sed delimiter in all _atomic_sed calls since replacement values contain URLs with slashes
- Named the ETL Compose profile `etl-extended` (per user decision in CONTEXT.md), distinct from Dify's `ETL_TYPE=unstructured` env var value
- Used `sudo tee` for credentials.txt write since /opt/agmind/ may be root-owned at first run
- Only Portainer included for the monitoring profile in v1 (lightweight container management UI)
- `{{DOCKER_SOCKET_PATH}}` is the only sed-substituted placeholder in docker-compose.yml; all other variables use Docker Compose native `${VAR}` interpolation from .env

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All template files and lib/config.sh ready for BATS testing in Plan 05-02
- phase_5_configuration() wired into install.sh and callable
- Templates consume WIZARD_* and DOCKER_RUNTIME from upstream phases

---
*Phase: 05-config-generation*
*Completed: 2026-03-21*
