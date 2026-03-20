# CLAUDE.md — AGMind macOS Installer

## Project Overview

Native macOS installer for AGMind RAG stack. Bash-based, 9-phase orchestration.
Target: Mac Studio / Mac Pro (Apple Silicon + Intel) as local AI server.

## Stack

- Dify (API + Worker + Web + Plugin Daemon) — Docker
- Open WebUI — Docker
- Ollama — **native via brew** (not Docker), uses Metal GPU
- Weaviate or Qdrant — Docker
- PostgreSQL + Redis — Docker
- Nginx + Squid — Docker
- Optional: Grafana + Portainer + Prometheus — Docker

## Architecture

```
agmind-mac/
├── install.sh              # 9-phase orchestrator
├── lib/
│   ├── common.sh           # Logging, utils, validation
│   ├── detect.sh           # macOS diagnostics
│   ├── wizard.sh           # Interactive config
│   ├── docker.sh           # Colima / Docker Desktop
│   ├── ollama.sh           # Native Ollama (new)
│   ├── config.sh           # .env, nginx.conf generation
│   ├── compose.sh          # docker compose up/down
│   ├── health.sh           # Healthchecks
│   ├── models.sh           # ollama pull
│   ├── backup.sh           # Backup + launchd plist
│   └── openwebui.sh        # Open WebUI admin init
├── templates/
│   ├── docker-compose.yml
│   ├── env.lan.template
│   ├── env.offline.template
│   ├── nginx.conf.template
│   ├── versions.env
│   └── launchd/
│       ├── com.agmind.health.plist.template
│       └── com.agmind.backup.plist.template
├── scripts/
│   ├── agmind.sh           # CLI: status/doctor/backup/...
│   ├── backup.sh
│   ├── health-gen.sh
│   └── update.sh
└── tests/
    ├── test_detect.bats
    ├── test_wizard.bats
    ├── test_config.bats
    ├── test_docker.bats
    └── test_ollama.bats
```

## Critical macOS vs Linux Differences

| Concern | Linux | macOS |
|---------|-------|-------|
| Package manager | apt-get | brew |
| Services | systemctl | launchctl / LaunchAgents |
| Memory | /proc/meminfo | sysctl hw.memsize |
| Ports | ss -tlnp | lsof -iTCP -sTCP:LISTEN |
| Docker | docker-ce daemon | Docker Desktop or Colima |
| Ollama | Docker container | Native brew service |
| Cron | /etc/cron.d | LaunchAgent plist |
| sed | GNU sed | BSD sed → `sed -i ''` |
| timeout | GNU timeout | No timeout → use poll loops |

## Non-Negotiable Rules

### Bash

- **POSIX-compatible** where possible; bash 5+ features only when necessary
- **BSD sed only** — always `sed -i ''` (no GNU sed dependency unless explicitly brewed)
- **No `timeout` command** — replace with manual poll loops with counter
- **No GNU coreutils assumptions** — test on stock macOS zsh/bash
- Idempotent: every phase can be re-run safely
- Set `set -euo pipefail` in every script
- All functions return meaningful exit codes
- Trap errors and log with file/line context

### Docker

- Ollama is NEVER in Docker on macOS — it runs natively via brew
- `OLLAMA_API_BASE=http://host.docker.internal:11434` in all .env files
- For Colima: always add `extra_hosts: - "host.docker.internal:host-gateway"` in compose
- Docker socket: detect which is active (Desktop: `~/.docker/run/docker.sock`, Colima: `~/.colima/default/docker.sock`)
- Symlink `/var/run/docker.sock` → actual socket when needed

### Testing

- Use **bats-core** for all tests
- Tests must pass on a fresh macOS install (no pre-installed tools assumed)
- Mock external calls (brew, docker, ollama) in unit tests
- Integration tests clearly marked and skippable

### Logging

```bash
# Always use these helpers from lib/common.sh:
log_info  "message"   # [INFO]  message
log_warn  "message"   # [WARN]  message
log_error "message"   # [ERROR] message
log_step  "N" "name"  # ═══ Phase N: name ═══
```

### Error Handling

- Never swallow errors silently
- On fatal error: print remediation hint, then exit 1
- Preflight failures: FAIL = abort, WARN = continue with prompt

## Profiles (v1 only)

- `lan` — local network, no TLS
- `offline` — air-gapped, no internet

**NOT in v1:** vps, vpn, tls/https, authelia, ufw, fail2ban, vllm, tei, tunnel, SOPS

## Key Environment Variables

```bash
DEPLOY_PROFILE=lan|offline
LLM_MODEL=qwen2.5:14b           # ollama model tag
EMBED_MODEL=nomic-embed-text     # ollama embed model
VECTOR_DB=weaviate|qdrant
ETL_MODE=standard|extended
MONITORING_MODE=none|local
BACKUP_MODE=local|remote
DOCKER_RUNTIME=colima|desktop    # override auto-detect
COLIMA_CPU=8
COLIMA_MEMORY=16
SKIP_PREFLIGHT=0
NON_INTERACTIVE=0
```

## Ollama

- Install: `brew install ollama`
- Start: `brew services start ollama`
- Health: poll `http://localhost:11434/api/tags` until 200 (60s timeout via counter)
- Pull models: `ollama pull <model>` directly on host
- Docker containers reach Ollama via `http://host.docker.internal:11434`

## Installation Path

- `/opt/agmind/` — main install dir (requires sudo, same as Linux for compatibility)
- `~/Library/LaunchAgents/` — LaunchAgent plists
- `~/Library/Application Support/AGMind/backups/` — backups

## CLI (agmind.sh)

```bash
agmind status    # show all service status + IPs
agmind doctor    # preflight check on running system
agmind logs      # docker logs
agmind backup    # manual backup
agmind restore   # restore from backup
agmind update    # update images + pull new models
agmind stop      # docker compose down + brew services stop ollama
agmind start     # brew services start ollama + docker compose up -d
agmind restart   # stop + start
agmind uninstall # full removal
```

## Model Recommendations by RAM

| Unified Memory | LLM Model |
|----------------|-----------|
| 8 GB | gemma3:4b, qwen2.5:3b |
| 16 GB | qwen2.5:7b, llama3.1:8b |
| 32 GB | qwen2.5:14b, phi-4:14b |
| 64 GB | qwen2.5:32b, gemma3:27b |
| 96 GB+ | qwen2.5:72b, llama3.1:70b |
| 192 GB | any |

## Development Principles

1. **Write it once, right** — no placeholder code, every function fully implemented
2. **Fail fast** — detect problems at preflight, not mid-install
3. **Idempotent** — re-running install.sh must not corrupt existing setup
4. **Minimal dependencies** — prefer macOS built-ins over brew installs
5. **Clear UX** — every phase shows progress; errors show remediation steps
6. **Test coverage** — every lib/*.sh function has a corresponding bats test
