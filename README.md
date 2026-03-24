# AGMind macOS Installer

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Tests](https://img.shields.io/badge/tests-230%20passed-brightgreen.svg)]()
[![macOS](https://img.shields.io/badge/macOS-13%20Ventura%2B-000000.svg)]()
[![Bash](https://img.shields.io/badge/bash-3.2%20compatible-4EAA25.svg)]()

**[Русская версия (README.ru.md)](README.ru.md)**

One-command installer for a full local AI/RAG stack on macOS.
Deploys **Dify, Open WebUI, Ollama, Weaviate/Qdrant, PostgreSQL, Redis, Nginx** — with optional **Open Notebook** and **DB-GPT** — optimized for Mac Studio and Mac Pro with native Metal GPU acceleration.

```bash
git clone https://github.com/botAGI/AGmind-macos.git
cd AGmind-macos
bash install.sh
```

> **Dry-run** — validate the entire 9-phase flow without sudo, Docker, or any system changes:
> ```bash
> bash install.sh --dry-run
> ```

## Why AGMind?

Running AI locally on macOS means dealing with Docker quirks, Ollama networking, Compose profiles, nginx routing, LaunchAgents instead of systemd, and BSD tools instead of GNU. AGMind handles all of it in one command.

- **Metal GPU acceleration** — Ollama runs natively via Homebrew, not in Docker
- **Zero config** — wizard auto-detects your hardware and recommends models
- **Optional tools** — add Open Notebook or DB-GPT with a single "yes"
- **Day-2 ready** — `agmind` CLI for status, doctor, backup, stop/start, uninstall

## What It Does

| Phase | What happens |
|-------|-------------|
| 1. Diagnostics | Validates macOS 13+, RAM, disk, ports, brew, Docker |
| 2. Wizard | Interactive or non-interactive config (profile, models, vector DB, optional tools) |
| 3. Prerequisites | Docker (Colima or Desktop) + Compose v2 |
| 4. Ollama Setup | Native Ollama via Homebrew — Metal GPU acceleration |
| 5. Configuration | Generates `.env`, `nginx.conf`, `docker-compose.yml`, TOML configs, secrets |
| 6. Start | `docker compose up` + admin credential injection |
| 7. Health | Polls all containers + Ollama API until healthy |
| 8. Models | Pulls LLM + embedding models via Ollama |
| 9. Complete | LaunchAgents, CLI install, final summary |

## Requirements

| | Minimum |
|--|---------|
| **macOS** | 13 Ventura+ |
| **Architecture** | Apple Silicon (arm64) or Intel (x86_64) |
| **RAM** | 8 GB (24+ GB recommended) |
| **Disk** | 30 GB free |
| **Ports** | 80, 3000 free |

## Quick Start

### Interactive

```bash
bash install.sh
```

The wizard asks 9 questions with smart defaults based on your hardware.

### Non-Interactive

```bash
NON_INTERACTIVE=1 \
DEPLOY_PROFILE=lan \
LLM_MODEL=qwen2.5:14b \
EMBED_MODEL=nomic-embed-text \
VECTOR_DB=weaviate \
INSTALL_OPEN_NOTEBOOK=1 \
INSTALL_DBGPT=1 \
bash install.sh
```

### Options

| Flag | Description |
|------|-------------|
| `--verbose` | Debug-level output |
| `--non-interactive` | Skip prompts, read from env vars |
| `--dry-run` | Full 9-phase run without system changes |
| `--force-phase N` | Re-run phase N even if complete |
| `--help` | Show usage |

## Stack

| Component | Runs as | Access |
|-----------|---------|--------|
| **Dify** (API + Worker + Web) | Docker | `http://<ip>/apps/` |
| **Open WebUI** | Docker | `http://<ip>/` |
| **Ollama** | **Native** (brew) | `http://localhost:11434` |
| **Weaviate** or **Qdrant** | Docker | internal |
| **PostgreSQL** + **Redis** | Docker | internal |
| **Nginx** | Docker | port 80 |
| **Open Notebook** *(optional)* | Docker | `http://<ip>/notebook/` |
| **DB-GPT** *(optional)* | Docker | `http://<ip>/dbgpt/` |

## Optional Tools

### Open Notebook

AI research notebook ([lfnovo/open-notebook](https://github.com/lfnovo/open-notebook)) — open-source alternative to Google NotebookLM. PDF, video, audio ingestion with vector search and podcast generation. Deploys with SurrealDB.

### DB-GPT

AI database assistant ([eosphoros-ai/DB-GPT](https://github.com/eosphoros-ai/DB-GPT)) — Text-to-SQL, RAG over databases, multi-agent orchestration. SQLite mode with Ollama proxy — no GPU needed in Docker.

Both are Docker Compose profile-gated. They connect to native Ollama via `host.docker.internal:11434`.

## Model Recommendations

Auto-selected based on your unified memory:

| RAM | LLM |
|-----|-----|
| 8 GB | gemma3:4b |
| 16 GB | qwen2.5:7b |
| 32 GB | qwen2.5:14b |
| 64 GB | gemma3:27b |
| 96 GB+ | qwen2.5:72b |

## CLI

```bash
agmind status      # Service states, Ollama, LAN IP, optional tools
agmind doctor      # Health checks — PASS/WARN/FAIL
agmind start       # Ollama first, then Docker Compose
agmind stop        # Docker Compose down, then Ollama
agmind restart     # Stop + Start
agmind logs [svc]  # Compose logs (tail 50) or follow specific service
agmind backup      # Manual backup with rotation
agmind uninstall   # Full removal with confirmation
```

## Profiles

| Profile | Description |
|---------|-------------|
| `lan` | Local network, no TLS |
| `offline` | Air-gapped, no internet |

## Project Structure

```
agmind-macos/
├── install.sh                          # 9-phase orchestrator + dry-run
├── lib/                                # 11 bash modules
│   ├── common.sh                       #   logging, errors, BSD utilities
│   ├── detect.sh                       #   hardware detection, preflight
│   ├── wizard.sh                       #   interactive config (9 questions)
│   ├── docker.sh                       #   Colima / Docker Desktop
│   ├── ollama.sh                       #   native Ollama via brew
│   ├── config.sh                       #   templates, secrets, TOML
│   ├── compose.sh, health.sh           #   deploy + health polling
│   ├── models.sh, openwebui.sh         #   model pull + admin init
│   └── backup.sh                       #   LaunchAgent management
├── scripts/
│   ├── agmind.sh                       # CLI (8 commands)
│   ├── backup.sh                       # scheduled backup + rotation
│   └── health-gen.sh                   # JSON health reports
├── templates/                          # Compose, env, nginx, TOML, plists
└── tests/
    ├── unit/          (230 BATS tests)
    ├── integration-test.sh
    └── helpers/       (mock executables)
```

## Testing

```bash
bash install.sh --dry-run               # Full flow, no sudo, 1 second
bats tests/unit/                        # 230 unit tests
bash tests/integration-test.sh          # Sandboxed 9-phase run
shellcheck lib/*.sh scripts/*.sh        # Lint
```

## Security

- Secrets from `/dev/urandom` (32-char alphanumeric)
- `.env` and `credentials.txt` mode 600, `umask 077`
- Credential key whitelist on `credentials.txt` read
- sed injection prevention (`_sed_escape`)
- `sudo rm -rf` guarded by path validation + `.install-state` marker
- curl timeouts (5s connect, 10s max) on all requests
- JSON via `python3 json.dumps`, not string concatenation

## macOS-Specific Design

| Linux | macOS (AGMind) |
|-------|----------------|
| `apt-get` | `brew` |
| `systemctl` / cron | LaunchAgents |
| `/proc/meminfo` | `sysctl hw.memsize` |
| `ss -tlnp` | `lsof -iTCP` |
| GNU sed | BSD `sed -i ''` |
| `timeout` | counter-based loops |
| Docker GPU passthrough | Native Ollama (Metal) |
| bash 5+ | bash 3.2.57 (stock) |

## License

[Apache 2.0](LICENSE)
