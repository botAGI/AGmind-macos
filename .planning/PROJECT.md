# AGMind macOS Installer

## What This Is

Native macOS installer for the AGMind RAG stack — a one-command setup that deploys Dify, Open WebUI, Ollama, a vector database, PostgreSQL, Redis, and Nginx on Mac Studio / Mac Pro hardware. Runs Ollama natively via Homebrew for Metal GPU acceleration, all other services in Docker via Colima or Docker Desktop. Includes `agmind` CLI for day-2 operations.

## Core Value

One `bash install.sh` command deploys a full local AI RAG stack on macOS with native Metal-accelerated Ollama inference — no Docker GPU passthrough hacks, no Linux-specific tooling.

## Requirements

### Validated

- ✓ 9-phase orchestrated installer runs to completion on Apple Silicon and Intel Mac — v1.0
- ✓ Ollama installs natively via Homebrew and runs as a brew service with Metal acceleration — v1.0
- ✓ Docker runtime auto-detected (Colima or Docker Desktop), Colima auto-installed if neither found — v1.0
- ✓ Full RAG stack deployed: Dify, Open WebUI, Weaviate/Qdrant, PostgreSQL, Redis, Nginx — v1.0
- ✓ LAN and Offline deployment profiles supported — v1.0
- ✓ Preflight checks validate macOS 13+, RAM >= 8GB, Disk >= 30GB, ports free — v1.0
- ✓ Non-interactive mode via env vars for automation — v1.0
- ✓ LaunchAgent plists replace cron for health and backup scheduling — v1.0
- ✓ `agmind` CLI provides status/doctor/start/stop/logs/backup/uninstall — v1.0
- ✓ BATS test suite covers all lib/*.sh modules (109 tests) — v1.0

### Active

(None — v1.0 complete, v2 requirements to be defined)

### Out of Scope

- VPS / VPN deployment profiles — macOS not for public servers in v1
- TLS / HTTPS / Certbot — Mac Studio on LAN, no public IP in v1
- Authelia 2FA — overkill for local use
- UFW / fail2ban — not applicable on macOS
- vLLM / TEI — requires CUDA, not available on macOS
- Reverse SSH tunnel — not in v1
- SOPS encryption — not in v1
- Dify API automation — out of scope
- GUI installer — CLI only in v1
- `agmind update` with Dify DB migration — complex version-specific logic, deferred to v2
- `agmind restore` — deferred to v2
- Mobile responsive — not applicable (CLI tool)

## Context

Shipped v1.0 with 5,101 LOC (2,761 bash + 2,340 BATS tests) across 79 files.
Tech stack: Bash 3.2 (stock macOS), BSD sed, BATS-core for testing.
7 phases, 15 plans, 57 requirements — all satisfied.
109 BATS tests covering all lib/*.sh modules and CLI.

- **Reference:** Linux installer v3.0 (difyowebinstaller) — adapted for macOS differences
- **Docker sockets:** Docker Desktop `~/.docker/run/docker.sock`, Colima `~/.colima/default/docker.sock`
- **host.docker.internal:** Requires `extra_hosts` in Colima; automatic in Docker Desktop
- **Install path:** `/opt/agmind/` | **Backups:** `~/Library/Application Support/AGMind/backups/`
- **LaunchAgents:** `~/Library/LaunchAgents/com.agmind.*.plist`

## Constraints

- **Tech stack:** Bash only — no Python, no Node, no compiled binaries. Must run on stock macOS
- **BSD compatibility:** No GNU coreutils. `sed -i ''`, no `timeout`, no `gnu-parallel`
- **Idempotency:** Every phase re-runnable without breaking existing setup
- **Minimal deps:** Prefer macOS built-ins; only brew-install what's strictly required
- **Apple Silicon primary:** Intel x86_64 supported but secondary priority
- **macOS 13 Ventura minimum**

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Ollama natively via brew (not Docker) | Metal GPU passthrough impossible in Docker on macOS | ✓ Good |
| Support Colima + Docker Desktop | Docker Desktop is paid for companies; Colima is free | ✓ Good |
| /opt/agmind/ install path | Compatibility with Linux installer scripts | ✓ Good |
| BSD sed throughout (no gnu-sed dep) | Avoid mandatory brew dep for sed | ✓ Good |
| LaunchAgents over crontab | More reliable, proper macOS integration | ✓ Good |
| OLLAMA_API_BASE via host.docker.internal | Ollama on host; containers reach it via Docker gateway | ✓ Good |
| LAN + Offline profiles only in v1 | macOS not suited for public server deployment | ✓ Good |
| ANSI colors via printf byte sequences | BSD sed can't handle literal \033 in patterns | ✓ Good |
| Phase state via flat file with grep -qxF | Simple, Bash 3.2 compatible, no associative arrays needed | ✓ Good |
| python3 -c for JSON merge in docker.sh | python3 ships with macOS, avoids jq dependency | ✓ Good |
| launchctl bootstrap + load fallback | Modern API (Ventura+) with legacy compat | ✓ Good |
| Open WebUI admin via env var injection | More reliable than POST signup; fallback for verification | ✓ Good |

---
*Last updated: 2026-03-23 after v1.0 milestone*
