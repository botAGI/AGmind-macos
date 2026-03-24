# Roadmap: AGMind macOS Installer

## Milestones

- ✅ **v1.0 AGMind macOS Installer** — Phases 1-7 (shipped 2026-03-23)
- 🚧 **v1.1 Optional AI Tools** — Phases 8-11 (in progress)

## Phases

<details>
<summary>✅ v1.0 AGMind macOS Installer (Phases 1-7) — SHIPPED 2026-03-23</summary>

- [x] Phase 1: Foundation (2/2 plans) — completed 2026-03-21
- [x] Phase 2: Detection (2/2 plans) — completed 2026-03-21
- [x] Phase 3: Wizard (1/1 plans) — completed 2026-03-21
- [x] Phase 4: Docker and Ollama (2/2 plans) — completed 2026-03-21
- [x] Phase 5: Config Generation (2/2 plans) — completed 2026-03-22
- [x] Phase 6: Stack Deployment (4/4 plans) — completed 2026-03-22
- [x] Phase 7: CLI (2/2 plans) — completed 2026-03-23

Full details: `.planning/milestones/v1.0-ROADMAP.md`

</details>

### 🚧 v1.1 Optional AI Tools (In Progress)

**Milestone Goal:** Add Open Notebook and DB-GPT as optional wizard-selectable tools to the AGMind stack

- [x] **Phase 8: Wizard Extension** — Interactive and non-interactive selection of optional AI tools (completed 2026-03-24)
- [x] **Phase 9: Config Generation and Templates** — Compose profiles, env templates, nginx routing, secrets, TOML config for optional tools (completed 2026-03-24)
- [x] **Phase 10: Health Checks and CLI** — Conditional health monitoring and CLI awareness of optional tools (completed 2026-03-24)
- [ ] **Phase 11: Test Suite** — BATS test coverage for wizard, config, and integration with optional tools

## Phase Details

### Phase 8: Wizard Extension
**Goal**: Users can choose which optional AI tools to install during setup
**Depends on**: Phase 7 (v1.0 complete)
**Requirements**: ONBOOK-02, DBGPT-03
**Success Criteria** (what must be TRUE):
  1. Running `install.sh` interactively shows "Install Open Notebook? [y/N]" and "Install DB-GPT? [y/N]" questions with RAM usage hints
  2. Setting `INSTALL_OPEN_NOTEBOOK=1` and/or `INSTALL_DBGPT=1` in non-interactive mode selects tools without prompts
  3. Wizard exports `WIZARD_OPEN_NOTEBOOK` and `WIZARD_DBGPT` variables consumed by downstream config generation
  4. On systems with 8 GB RAM, wizard warns about memory pressure when selecting optional tools
**Plans:** 1/1 plans complete
Plans:
- [x] 08-01-PLAN.md — Add Open Notebook and DB-GPT questions to wizard (interactive + non-interactive)

### Phase 9: Config Generation and Templates
**Goal**: Optional tools deploy as Docker Compose profile-gated services with correct networking, secrets, and nginx routing
**Depends on**: Phase 8
**Requirements**: ONBOOK-01, ONBOOK-03, ONBOOK-04, DBGPT-01, DBGPT-02, DBGPT-04
**Success Criteria** (what must be TRUE):
  1. When Open Notebook is selected, `docker compose up` starts open-notebook and SurrealDB containers; when not selected, they do not start and nginx still works
  2. When DB-GPT is selected, `docker compose up` starts DB-GPT container in SQLite/Ollama proxy mode with auto-generated TOML config
  3. Open Notebook is accessible at `http://<host>/notebook/` via nginx reverse proxy (with WebSocket support for Streamlit)
  4. DB-GPT is accessible at `http://<host>/dbgpt/` via nginx reverse proxy
  5. Both tools reach native Ollama via `host.docker.internal:11434` (Open Notebook container env, DB-GPT via TOML config)
**Plans:** 2/2 plans complete
Plans:
- [ ] 09-01-PLAN.md — Docker Compose services, version pins, TOML template, nginx markers, env placeholders
- [ ] 09-02-PLAN.md — Extend config.sh with profile building, secrets, conditional nginx, TOML rendering

### Phase 10: Health Checks and CLI
**Goal**: Optional tools are monitored and visible through the agmind CLI when installed
**Depends on**: Phase 9
**Requirements**: DBGPT-05, DBGPT-06
**Success Criteria** (what must be TRUE):
  1. `phase_7_health` conditionally checks DB-GPT container health when dbgpt profile is active
  2. `agmind status` shows DB-GPT status and URL when installed, or omits it when not installed
  3. `agmind doctor` reports DB-GPT health when the dbgpt profile is active
**Plans:** 1/1 plans complete
Plans:
- [x] 10-01-PLAN.md — Add conditional DB-GPT health check to health.sh and DB-GPT status/doctor to agmind.sh

### Phase 11: Test Suite
**Goal**: All v1.1 changes are verified by automated BATS tests
**Depends on**: Phase 10
**Requirements**: TEST-04, TEST-05, TEST-06
**Success Criteria** (what must be TRUE):
  1. BATS tests verify wizard asks Open Notebook and DB-GPT questions and respects non-interactive env vars
  2. BATS tests verify Compose profile string includes optional tool profiles for all selection combinations (none, one, both)
  3. Integration test exercises the full optional tools flow: wizard selection through config generation through compose profile activation
**Plans**: TBD

## Progress

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Foundation | v1.0 | 2/2 | Complete | 2026-03-21 |
| 2. Detection | v1.0 | 2/2 | Complete | 2026-03-21 |
| 3. Wizard | v1.0 | 1/1 | Complete | 2026-03-21 |
| 4. Docker and Ollama | v1.0 | 2/2 | Complete | 2026-03-21 |
| 5. Config Generation | v1.0 | 2/2 | Complete | 2026-03-22 |
| 6. Stack Deployment | v1.0 | 4/4 | Complete | 2026-03-22 |
| 7. CLI | v1.0 | 2/2 | Complete | 2026-03-23 |
| 8. Wizard Extension | v1.1 | 1/1 | Complete | 2026-03-24 |
| 9. Config Generation and Templates | 2/2 | Complete   | 2026-03-24 | - |
| 10. Health Checks and CLI | v1.1 | 1/1 | Complete | 2026-03-24 |
| 11. Test Suite | v1.1 | 0/? | Not started | - |
