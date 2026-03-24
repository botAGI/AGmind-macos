# AGMind macOS Installer

One-command installer for a full local AI/RAG stack on macOS. Deploys Dify, Open WebUI, Ollama, Weaviate/Qdrant, PostgreSQL, Redis, and Nginx — optimized for Mac Studio and Mac Pro with native Metal GPU acceleration.

```bash
bash install.sh
```

## What It Does

Runs 9 phases automatically:

1. **Diagnostics** — validates macOS version, RAM, disk, ports, installed tools
2. **Wizard** — interactive or non-interactive configuration (profile, models, vector DB)
3. **Prerequisites** — installs/configures Docker (Colima or Desktop) and Compose v2
4. **Ollama Setup** — installs Ollama natively via Homebrew for Metal GPU acceleration
5. **Configuration** — generates `.env`, `nginx.conf`, `docker-compose.yml`, credentials
6. **Start** — `docker compose up` with admin credential injection
7. **Health** — polls all containers and Ollama API until healthy
8. **Models** — pulls LLM and embedding models via Ollama
9. **Complete** — installs LaunchAgents, CLI tool, prints summary

## Why Native Ollama?

Docker on macOS cannot pass through Metal GPU. Ollama runs natively via Homebrew and gets full Apple Silicon performance. Docker containers reach it via `host.docker.internal:11434`.

## Requirements

| Requirement | Minimum |
|-------------|---------|
| macOS | 13 Ventura+ |
| Architecture | Apple Silicon (arm64) or Intel (x86_64) |
| RAM | 8 GB (24+ GB recommended) |
| Disk | 30 GB free |
| Ports | 80, 3000 free |

## Quick Start

### Interactive

```bash
git clone https://github.com/botAGI/AGmind-macos.git
cd AGmind-macos
bash install.sh
```

The wizard will ask 7 questions: deployment profile, LLM model, embedding model, vector database, ETL mode, monitoring, and backup mode — with smart defaults based on your hardware.

### Non-Interactive

```bash
NON_INTERACTIVE=1 \
DEPLOY_PROFILE=lan \
LLM_MODEL=qwen2.5:14b \
EMBED_MODEL=nomic-embed-text \
VECTOR_DB=weaviate \
bash install.sh
```

### Options

```
--verbose           Debug-level output
--non-interactive   Skip prompts (read from env vars)
--force-phase N     Re-run phase N even if already complete
--help              Show usage
```

## Model Recommendations

The wizard auto-recommends based on your unified memory:

| RAM | Recommended LLM |
|-----|----------------|
| 8 GB | gemma3:4b |
| 16 GB | qwen2.5:7b |
| 32 GB | qwen2.5:14b |
| 64 GB | gemma3:27b |
| 96 GB+ | qwen2.5:72b |

## Deployment Profiles

| Profile | Description |
|---------|-------------|
| `lan` | Local network access, no TLS |
| `offline` | Air-gapped, no internet required |

## Stack Components

| Component | How It Runs | Port |
|-----------|------------|------|
| Dify (API + Worker + Web) | Docker | 80 (via nginx) |
| Open WebUI | Docker | 80 (via nginx) |
| Ollama | **Native** (brew) | 11434 |
| Weaviate or Qdrant | Docker | internal |
| PostgreSQL | Docker | internal |
| Redis | Docker | internal |
| Nginx | Docker | 80 |

## CLI Tool

After installation, manage the stack with `agmind`:

```bash
agmind status      # Service states, Ollama status, LAN IP
agmind doctor      # Health checks with PASS/WARN/FAIL
agmind start       # Start Ollama first, then Docker Compose
agmind stop        # Docker Compose down, then stop Ollama
agmind restart     # Stop + Start
agmind logs        # Docker Compose logs (tail 50)
agmind logs api    # Follow specific service logs
agmind backup      # Manual backup to ~/Library/Application Support/AGMind/backups/
agmind uninstall   # Full removal with confirmation
```

## File Structure

```
agmind-macos/
├── install.sh                  # 9-phase orchestrator
├── lib/
│   ├── common.sh               # Logging, error handling, BSD-safe utilities
│   ├── detect.sh               # Hardware/software detection, preflight
│   ├── wizard.sh               # Interactive configuration wizard
│   ├── docker.sh               # Colima/Docker Desktop setup
│   ├── ollama.sh               # Native Ollama install/start
│   ├── config.sh               # Template rendering, secret generation
│   ├── compose.sh              # Docker Compose orchestration
│   ├── health.sh               # Container health polling
│   ├── models.sh               # Ollama model pull
│   ├── openwebui.sh            # Open WebUI admin initialization
│   └── backup.sh               # LaunchAgent management
├── scripts/
│   ├── agmind.sh               # CLI tool
│   ├── backup.sh               # Scheduled backup script
│   └── health-gen.sh           # Health report generator
├── templates/
│   ├── docker-compose.yml      # Compose template with profiles
│   ├── env.lan.template        # Environment for LAN profile
│   ├── env.offline.template    # Environment for offline profile
│   ├── nginx.conf.template     # Nginx reverse proxy config
│   ├── versions.env            # Image version pinning
│   └── launchd/                # LaunchAgent plist templates
└── tests/
    ├── integration-test.sh     # Full 9-phase sandboxed test
    ├── unit/                   # 216 BATS tests
    └── helpers/                # Mock executables for testing
```

## Paths

| Path | Purpose |
|------|---------|
| `/opt/agmind/` | Installation directory |
| `/opt/agmind/.env` | Generated environment (mode 600) |
| `/opt/agmind/credentials.txt` | Secrets file (mode 600) |
| `~/Library/LaunchAgents/com.agmind.*.plist` | Scheduled tasks |
| `~/Library/Application Support/AGMind/backups/` | Backup archives |
| `/usr/local/bin/agmind` | CLI symlink |

## Testing

```bash
# Unit tests (216 tests, mocked external commands)
bats tests/unit/

# Integration test (full 9-phase run in sandbox, no sudo needed)
bash tests/integration-test.sh

# Lint
shellcheck lib/*.sh scripts/*.sh install.sh
```

## macOS-Specific Design

- **Bash 3.2** — compatible with stock macOS `/bin/bash` (no bash 4+ features)
- **BSD sed** — `sed -i ''` throughout (no GNU sed dependency)
- **No `timeout` command** — counter-based poll loops
- **LaunchAgents** — replaces cron/systemd for scheduled tasks
- **`lsof`** — replaces `ss` for port detection
- **`sysctl hw.memsize`** — replaces `/proc/meminfo` for RAM detection
- **Idempotent** — safe to re-run `install.sh` on existing installation

## License

MIT
