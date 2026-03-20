# AGMind macOS Installer

## What This Is

Native macOS installer for the AGMind RAG stack — a one-command setup that deploys Dify, Open WebUI, Ollama, a vector database, PostgreSQL, Redis, and Nginx on Mac Studio / Mac Pro hardware. Unlike the Linux installer, it runs Ollama natively via Homebrew (not Docker) to leverage Apple Silicon Metal GPU, while all other services run in Docker via Colima or Docker Desktop.

## Core Value

One `bash install.sh` command deploys a full local AI RAG stack on macOS with native Metal-accelerated Ollama inference — no Docker GPU passthrough hacks, no Linux-specific tooling.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] 9-phase orchestrated installer runs to completion on Apple Silicon and Intel Mac
- [ ] Ollama installs natively via Homebrew and runs as a brew service with Metal acceleration
- [ ] Docker runtime auto-detected (Colima or Docker Desktop), Colima auto-installed if neither found
- [ ] Full RAG stack deployed: Dify, Open WebUI, Weaviate/Qdrant, PostgreSQL, Redis, Nginx, Squid
- [ ] LAN and Offline deployment profiles supported
- [ ] Preflight checks validate macOS 13+, RAM ≥ 8GB, Disk ≥ 30GB, ports free
- [ ] Non-interactive mode via env vars for automation
- [ ] LaunchAgent plists replace cron for health and backup scheduling
- [ ] `agmind` CLI provides status/doctor/start/stop/backup/restore/update/uninstall
- [ ] BATS test suite covers all lib/*.sh modules

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

## Context

- **Reference:** Linux installer v3.0 (difyowebinstaller) — significant portions reused (~70-95% per module)
- **Key macOS differences:** BSD sed (`sed -i ''`), launchd instead of systemctl/cron, Homebrew instead of apt-get, `lsof` instead of `ss`, `sysctl hw.memsize` instead of `/proc/meminfo`, no `timeout` command
- **Docker sockets:** Docker Desktop uses `~/.docker/run/docker.sock`, Colima uses `~/.colima/default/docker.sock`
- **host.docker.internal:** Resolves automatically in Docker Desktop; requires `extra_hosts: - "host.docker.internal:host-gateway"` in Colima
- **Install path:** `/opt/agmind/` (requires sudo, same as Linux for compatibility)
- **Backups path:** `~/Library/Application Support/AGMind/backups/`
- **LaunchAgents:** `~/Library/LaunchAgents/com.agmind.*.plist`

## Constraints

- **Tech stack:** Bash only — no Python, no Node, no compiled binaries. Must run on stock macOS zsh/bash
- **BSD compatibility:** No GNU coreutils assumptions. `sed -i ''` throughout, no `timeout`, no `gnu-parallel`
- **Idempotency:** Every phase re-runnable without breaking existing setup
- **Minimal deps:** Prefer macOS built-ins; only brew-install what's strictly required
- **Apple Silicon primary:** Intel x86_64 supported but secondary priority
- **macOS 13 Ventura minimum:** macOS 12 not supported

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Ollama natively via brew (not Docker) | Metal GPU passthrough impossible in Docker on macOS; native = full performance | — Pending |
| Support Colima + Docker Desktop | Docker Desktop is paid for companies; Colima is free and lighter | — Pending |
| /opt/agmind/ install path | Compatibility with Linux installer scripts | — Pending |
| BSD sed throughout (no gnu-sed dep) | Avoid mandatory brew dep for sed; `sed -i ''` works on macOS | — Pending |
| LaunchAgents over crontab | More reliable, proper macOS integration, survives logout/login | — Pending |
| OLLAMA_API_BASE=http://host.docker.internal:11434 | Ollama on host; containers reach it via Docker's host gateway | — Pending |
| LAN + Offline profiles only in v1 | macOS not suited for public server deployment | — Pending |

---
*Last updated: 2026-03-20 after initialization*
