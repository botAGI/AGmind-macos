# Requirements: AGMind macOS Installer

**Defined:** 2026-03-24
**Core Value:** One `bash install.sh` command deploys a full local AI RAG stack on macOS with native Metal-accelerated Ollama inference

## v1.1 Requirements

Requirements for v1.1 Optional AI Tools. Each maps to roadmap phases.

### Open Notebook

- [x] **ONBOOK-01**: Open Notebook deploys via Docker Compose profile `opennotebook` (SurrealDB + app containers)
- [x] **ONBOOK-02**: Wizard asks "Install Open Notebook? [y/N]" with env var `INSTALL_OPEN_NOTEBOOK` for non-interactive mode
- [x] **ONBOOK-03**: nginx proxies Open Notebook at `/notebook/` path (upstream port 8502)
- [x] **ONBOOK-04**: Open Notebook connects to native Ollama via `host.docker.internal:11434`

### DB-GPT

- [x] **DBGPT-01**: DB-GPT deploys via Docker Compose profile `dbgpt` (SQLite mode, Ollama proxy provider)
- [x] **DBGPT-02**: config.sh generates TOML config for DB-GPT with `proxy/ollama` provider pointing to `host.docker.internal:11434`
- [x] **DBGPT-03**: Wizard asks "Install DB-GPT? [y/N]" with env var `INSTALL_DBGPT` for non-interactive mode
- [x] **DBGPT-04**: nginx proxies DB-GPT at `/dbgpt/` path (upstream port 5670)
- [x] **DBGPT-05**: Health check for DB-GPT container integrated into phase_7_health (conditional on profile)
- [x] **DBGPT-06**: `agmind status` and `agmind doctor` show DB-GPT status when installed

### Testing

- [ ] **TEST-04**: BATS tests for wizard extensions (Open Notebook + DB-GPT questions, non-interactive env vars)
- [ ] **TEST-05**: BATS tests for Compose profile generation with optional tools
- [x] **TEST-06**: Integration test updated for optional tools flow

## v2 Requirements

### Advanced CLI
- **CLI-v2-01**: `agmind update` — pull new Docker images and restart services
- **CLI-v2-02**: `agmind restore` — restore from backup

### Advanced Deployment
- **DEPLOY-v2-01**: TLS / self-signed certificate generation for LAN profile
- **DEPLOY-v2-02**: Offline/air-gapped Homebrew package caching

## Out of Scope

| Feature | Reason |
|---------|--------|
| Open Notebook health check in CLI | Not critical for v1.1 — notebook is optional tool, health visible in Docker |
| Open Notebook backup integration | SurrealDB volume included in Docker volume backup already |
| DB-GPT MySQL mode | SQLite sufficient for local use, avoids extra container |
| DB-GPT GPU mode in Docker | Metal GPU not available in Docker on macOS |
| Per-tool nginx TLS | No TLS in LAN profile (v1 decision) |
| DB-GPT ARM64 native image | Use Rosetta emulation if needed; native image not available |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| ONBOOK-01 | Phase 9 | Complete |
| ONBOOK-02 | Phase 8 | Complete |
| ONBOOK-03 | Phase 9 | Complete |
| ONBOOK-04 | Phase 9 | Complete |
| DBGPT-01 | Phase 9 | Complete |
| DBGPT-02 | Phase 9 | Complete |
| DBGPT-03 | Phase 8 | Complete |
| DBGPT-04 | Phase 9 | Complete |
| DBGPT-05 | Phase 10 | Complete |
| DBGPT-06 | Phase 10 | Complete |
| TEST-04 | Phase 11 | Pending |
| TEST-05 | Phase 11 | Pending |
| TEST-06 | Phase 11 | Complete |

**Coverage:**
- v1.1 requirements: 13 total
- Mapped to phases: 13
- Unmapped: 0

---
*Requirements defined: 2026-03-24*
*Last updated: 2026-03-24 after roadmap creation*
