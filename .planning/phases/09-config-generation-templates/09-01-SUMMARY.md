---
phase: 09-config-generation-templates
plan: 01
subsystem: infra
tags: [docker-compose, nginx, toml, surrealdb, open-notebook, dbgpt, templates]

# Dependency graph
requires:
  - phase: 08-wizard-extension
    provides: WIZARD_OPEN_NOTEBOOK and WIZARD_DBGPT exports (1/0 values)
provides:
  - Three profile-gated Docker Compose services (surrealdb, open-notebook, dbgpt)
  - Four new Docker volumes (surrealdb_data, opennotebook_data, dbgpt_data, dbgpt_message)
  - Version pins for new images in versions.env
  - DB-GPT TOML config template with proxy/ollama provider
  - Nginx conditional injection markers (OPTIONAL_UPSTREAMS, OPTIONAL_LOCATIONS)
  - Env template placeholders for Open Notebook secrets
affects: [09-config-generation-templates/09-02, 10-health-cli-extension, 11-tests]

# Tech tracking
tech-stack:
  added: [surrealdb, open-notebook, dbgpt-openai]
  patterns: [conditional-nginx-markers, toml-config-templates]

key-files:
  created:
    - templates/dbgpt-proxy-ollama.toml.template
  modified:
    - templates/docker-compose.yml
    - templates/versions.env
    - templates/nginx.conf.template
    - templates/env.lan.template
    - templates/env.offline.template

key-decisions:
  - "Profile name 'opennotebook' (one word) to avoid YAML parsing issues with hyphens"
  - "SurrealDB has no ports mapping to avoid conflict with Weaviate on port 8000"
  - "DB-GPT uses eosphorosai/dbgpt-openai (lightweight ~2GB) not full dbgpt image (10+GB)"
  - "Nginx uses marker-based injection (OPTIONAL_UPSTREAMS/OPTIONAL_LOCATIONS) for conditional blocks"

patterns-established:
  - "Conditional nginx config: markers replaced by config.sh at render time, removed if tool not selected"
  - "TOML template pattern: mustache-style placeholders rendered by config.sh"

requirements-completed: [ONBOOK-01, ONBOOK-03, ONBOOK-04, DBGPT-01, DBGPT-04]

# Metrics
duration: 2min
completed: 2026-03-24
---

# Phase 9 Plan 1: Config Generation Templates Summary

**Docker Compose services for Open Notebook + SurrealDB + DB-GPT with profile-gated deployment, nginx conditional markers, and TOML config template**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-24T11:22:26Z
- **Completed:** 2026-03-24T11:24:16Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments
- Added three new profile-gated services (surrealdb, open-notebook, dbgpt) to docker-compose.yml
- Created DB-GPT TOML config template with proxy/ollama provider for Ollama integration
- Added conditional nginx markers for config.sh to inject optional upstream/location blocks
- Added Open Notebook secret placeholders to both env templates (lan + offline)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add Docker Compose services, volumes, and version pins** - `455e1bb` (feat)
2. **Task 2: Update nginx and env templates with conditional markers and new placeholders** - `42d9ccb` (feat)

## Files Created/Modified
- `templates/docker-compose.yml` - Three new services (surrealdb, open-notebook, dbgpt) + four volumes
- `templates/versions.env` - Version pins for OPEN_NOTEBOOK, SURREALDB, DBGPT
- `templates/dbgpt-proxy-ollama.toml.template` - DB-GPT TOML config with proxy/ollama and host.docker.internal
- `templates/nginx.conf.template` - OPTIONAL_UPSTREAMS and OPTIONAL_LOCATIONS markers
- `templates/env.lan.template` - OPEN_NOTEBOOK_ENCRYPTION_KEY and SURREAL_PASSWORD placeholders
- `templates/env.offline.template` - Identical new sections as lan template

## Decisions Made
- Profile name `opennotebook` (one word) per CONTEXT.md decision, avoiding YAML hyphen issues
- SurrealDB has NO host port mapping -- avoids conflict with Weaviate on port 8000
- Used `eosphorosai/dbgpt-openai` image (lightweight proxy-only ~2GB, not full 10+GB image)
- Nginx uses marker-based conditional injection rather than always-present upstream blocks (nginx fails if upstream DNS unresolvable)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All templates ready for config.sh (Plan 02) to render at install time
- config.sh needs: _build_compose_profiles() extension, secret generation, nginx block injection, TOML rendering
- Blockers from STATE.md still apply: DB-GPT arm64 support and Streamlit sub-path routing need testing

---
*Phase: 09-config-generation-templates*
*Completed: 2026-03-24*
