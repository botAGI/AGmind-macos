# AGMind macOS Installer

One-command installer for a full local AI/RAG stack on macOS.
Deploys **Dify, Open WebUI, Ollama, Weaviate/Qdrant, PostgreSQL, Redis, Nginx** — with optional **Open Notebook** and **DB-GPT** — optimized for Mac Studio and Mac Pro with native Metal GPU acceleration.

```bash
bash install.sh
```

> **Dry-run** (no sudo, no Docker, no installs — validates entire flow in 1 second):
> ```bash
> bash install.sh --dry-run
> ```

## What It Does

Runs 9 phases automatically:

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
| 9. Complete | LaunchAgents, CLI install, summary |

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

The wizard asks 9 questions with smart defaults based on your hardware:
deployment profile, LLM model, embedding model, vector DB, ETL mode, monitoring, backup, Open Notebook, DB-GPT.

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

```
--verbose           Debug-level output
--non-interactive   Skip prompts (read from env vars)
--dry-run           Full 9-phase run without system changes
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

## Stack Components

| Component | Runs as | Access |
|-----------|---------|--------|
| **Dify** (API + Worker + Web) | Docker | `http://<ip>/apps/` |
| **Open WebUI** | Docker | `http://<ip>/` |
| **Ollama** | **Native** (brew) | `http://localhost:11434` |
| **Weaviate** or **Qdrant** | Docker | internal |
| **PostgreSQL** + **Redis** | Docker | internal |
| **Nginx** | Docker | port 80 |
| **Open Notebook** (optional) | Docker | `http://<ip>/notebook/` |
| **DB-GPT** (optional) | Docker | `http://<ip>/dbgpt/` |

## Optional Tools

### Open Notebook
AI research notebook ([lfnovo/open-notebook](https://github.com/lfnovo/open-notebook)) — alternative to Google NotebookLM. Supports PDF, video, audio ingestion with vector search and podcast generation. Deployed with SurrealDB.

### DB-GPT
AI database assistant ([eosphoros-ai/DB-GPT](https://github.com/eosphoros-ai/DB-GPT)) — Text-to-SQL, RAG over databases, multi-agent orchestration. Runs in SQLite mode with Ollama proxy — no GPU needed in Docker.

Both tools are installed via Docker Compose profiles when selected in the wizard. They connect to native Ollama through `host.docker.internal:11434`.

## CLI Tool

```bash
agmind status      # Service states, Ollama status, LAN IP, optional tools
agmind doctor      # Health checks with PASS/WARN/FAIL
agmind start       # Start Ollama, then Docker Compose
agmind stop        # Docker Compose down, then stop Ollama
agmind restart     # Stop + Start
agmind logs        # Docker Compose logs (tail 50)
agmind logs api    # Follow specific service logs
agmind backup      # Backup to ~/Library/Application Support/AGMind/backups/
agmind uninstall   # Full removal with confirmation prompt
```

## Deployment Profiles

| Profile | Description |
|---------|-------------|
| `lan` | Local network, no TLS |
| `offline` | Air-gapped, no internet |

## File Structure

```
agmind-macos/
├── install.sh                  # 9-phase orchestrator (with --dry-run)
├── lib/
│   ├── common.sh               # Logging, error handling, BSD-safe utilities
│   ├── detect.sh               # Hardware/software detection, preflight
│   ├── wizard.sh               # Interactive config (9 questions)
│   ├── docker.sh               # Colima/Docker Desktop setup
│   ├── ollama.sh               # Native Ollama install/start
│   ├── config.sh               # Template rendering, secrets, TOML config
│   ├── compose.sh              # Docker Compose orchestration
│   ├── health.sh               # Container + Ollama health polling
│   ├── models.sh               # Ollama model pull
│   ├── openwebui.sh            # Open WebUI admin initialization
│   └── backup.sh               # LaunchAgent management
├── scripts/
│   ├── agmind.sh               # CLI tool (8 commands)
│   ├── backup.sh               # Scheduled backup with rotation
│   └── health-gen.sh           # JSON health report generator
├── templates/
│   ├── docker-compose.yml      # Compose with profiles (13+ services)
│   ├── env.lan.template        # Environment for LAN profile
│   ├── env.offline.template    # Environment for offline profile
│   ├── nginx.conf.template     # Reverse proxy with conditional blocks
│   ├── versions.env            # Image version pins
│   ├── dbgpt-proxy-ollama.toml.template  # DB-GPT Ollama config
│   └── launchd/                # LaunchAgent plist templates
└── tests/
    ├── integration-test.sh     # Full 9-phase sandboxed test
    ├── unit/                   # 230 BATS tests
    └── helpers/                # Mock executables
```

## Installation Paths

| Path | Purpose |
|------|---------|
| `/opt/agmind/` | Installation directory |
| `/opt/agmind/.env` | Generated environment (mode 600) |
| `/opt/agmind/credentials.txt` | Secrets (mode 600) |
| `/opt/agmind/dbgpt-proxy-ollama.toml` | DB-GPT config (if installed) |
| `~/Library/LaunchAgents/com.agmind.*.plist` | Scheduled tasks |
| `~/Library/Application Support/AGMind/backups/` | Backup archives |
| `/usr/local/bin/agmind` | CLI symlink |

## Testing

```bash
# Dry-run — full installer without sudo/docker (1 second)
bash install.sh --dry-run

# Unit tests — 230 tests with mocked external commands
bats tests/unit/

# Integration test — sandboxed 9-phase run with verification
bash tests/integration-test.sh

# Lint
shellcheck lib/*.sh scripts/*.sh install.sh
```

## Security

- All secrets generated from `/dev/urandom` (32-char alphanumeric)
- `.env` and `credentials.txt` are mode 600
- `umask 077` set during installation
- Credential keys whitelisted when reading `credentials.txt`
- User input escaped before sed substitution (injection prevention)
- `sudo rm -rf` protected by path validation + `.install-state` marker check
- curl timeouts on all HTTP requests (5s connect, 10s max)
- JSON payloads constructed via `python3 json.dumps` (no string concatenation)

## macOS-Specific Design

- **Bash 3.2** — stock macOS `/bin/bash`, no bash 4+ features
- **BSD sed** — `sed -i ''` throughout, no GNU sed
- **No `timeout` command** — counter-based poll loops
- **LaunchAgents** — replaces cron/systemd
- **`lsof`** — replaces `ss` for port detection
- **`sysctl hw.memsize`** — replaces `/proc/meminfo`
- **`python3 -c`** — ships with macOS, used for JSON ops (avoids jq dependency)
- **Idempotent** — safe to re-run on existing installation

## License

Apache 2.0

---

# AGMind macOS Installer (RU)

Установщик полного локального AI/RAG стека на macOS одной командой.
Разворачивает **Dify, Open WebUI, Ollama, Weaviate/Qdrant, PostgreSQL, Redis, Nginx** — с опциональными **Open Notebook** и **DB-GPT** — оптимизирован для Mac Studio и Mac Pro с нативным ускорением Metal GPU.

```bash
bash install.sh
```

> **Тестовый прогон** (без sudo, без Docker — проверяет весь флоу за 1 секунду):
> ```bash
> bash install.sh --dry-run
> ```

## Что делает

Автоматически проходит 9 фаз:

| Фаза | Что происходит |
|------|---------------|
| 1. Диагностика | Проверка macOS 13+, RAM, диск, порты, brew, Docker |
| 2. Мастер | Интерактивная или автоматическая настройка (профиль, модели, вектор БД, доп. инструменты) |
| 3. Подготовка | Docker (Colima или Desktop) + Compose v2 |
| 4. Ollama | Нативная установка через Homebrew — ускорение Metal GPU |
| 5. Конфигурация | Генерация `.env`, `nginx.conf`, `docker-compose.yml`, TOML, секреты |
| 6. Запуск | `docker compose up` + внедрение учётных данных администратора |
| 7. Здоровье | Опрос всех контейнеров + Ollama API до готовности |
| 8. Модели | Загрузка LLM + embedding моделей через Ollama |
| 9. Завершение | LaunchAgents, CLI, итоговая сводка |

## Почему нативный Ollama?

Docker на macOS не может пробросить Metal GPU. Ollama работает нативно через Homebrew и получает полную производительность Apple Silicon. Docker-контейнеры обращаются к нему через `host.docker.internal:11434`.

## Требования

| Требование | Минимум |
|-----------|---------|
| macOS | 13 Ventura+ |
| Архитектура | Apple Silicon (arm64) или Intel (x86_64) |
| RAM | 8 ГБ (рекомендуется 24+ ГБ) |
| Диск | 30 ГБ свободно |
| Порты | 80, 3000 свободны |

## Быстрый старт

### Интерактивный режим

```bash
git clone https://github.com/botAGI/AGmind-macos.git
cd AGmind-macos
bash install.sh
```

Мастер задаёт 9 вопросов с умными значениями по умолчанию на основе вашего оборудования:
профиль развёртывания, LLM-модель, модель эмбеддингов, векторная БД, режим ETL, мониторинг, бэкап, Open Notebook, DB-GPT.

### Автоматический режим

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

### Параметры

```
--verbose           Подробный вывод
--non-interactive   Без вопросов (читает из env vars)
--dry-run           Полный прогон без изменений в системе
--force-phase N     Перезапустить фазу N
--help              Показать справку
```

## Рекомендации моделей

Мастер автоматически рекомендует на основе объёма единой памяти:

| RAM | Рекомендуемая LLM |
|-----|-------------------|
| 8 ГБ | gemma3:4b |
| 16 ГБ | qwen2.5:7b |
| 32 ГБ | qwen2.5:14b |
| 64 ГБ | gemma3:27b |
| 96 ГБ+ | qwen2.5:72b |

## Компоненты стека

| Компонент | Запуск | Доступ |
|-----------|--------|--------|
| **Dify** (API + Worker + Web) | Docker | `http://<ip>/apps/` |
| **Open WebUI** | Docker | `http://<ip>/` |
| **Ollama** | **Нативный** (brew) | `http://localhost:11434` |
| **Weaviate** или **Qdrant** | Docker | внутренний |
| **PostgreSQL** + **Redis** | Docker | внутренний |
| **Nginx** | Docker | порт 80 |
| **Open Notebook** (опц.) | Docker | `http://<ip>/notebook/` |
| **DB-GPT** (опц.) | Docker | `http://<ip>/dbgpt/` |

## Опциональные инструменты

### Open Notebook
AI-блокнот для исследований ([lfnovo/open-notebook](https://github.com/lfnovo/open-notebook)) — альтернатива Google NotebookLM. Поддерживает PDF, видео, аудио с векторным поиском и генерацией подкастов. Разворачивается с SurrealDB.

### DB-GPT
AI-ассистент для баз данных ([eosphoros-ai/DB-GPT](https://github.com/eosphoros-ai/DB-GPT)) — Text-to-SQL, RAG по базам данных, мульти-агентная оркестрация. Работает в режиме SQLite с Ollama proxy — GPU в Docker не нужен.

Оба инструмента устанавливаются через Docker Compose profiles при выборе в мастере. Подключаются к нативному Ollama через `host.docker.internal:11434`.

## CLI

```bash
agmind status      # Статус сервисов, Ollama, IP, опциональные тулзы
agmind doctor      # Проверки здоровья PASS/WARN/FAIL
agmind start       # Запуск Ollama, затем Docker Compose
agmind stop        # Остановка Docker Compose, затем Ollama
agmind restart     # Перезапуск
agmind logs        # Логи Docker Compose (последние 50)
agmind logs api    # Логи конкретного сервиса
agmind backup      # Бэкап в ~/Library/Application Support/AGMind/backups/
agmind uninstall   # Полное удаление с подтверждением
```

## Тестирование

```bash
# Тестовый прогон — полный инсталлер без sudo/docker (1 секунда)
bash install.sh --dry-run

# Юнит-тесты — 230 тестов с моками внешних команд
bats tests/unit/

# Интеграционный тест — sandbox прогон 9 фаз с верификацией
bash tests/integration-test.sh

# Линтер
shellcheck lib/*.sh scripts/*.sh install.sh
```

## Безопасность

- Секреты генерируются из `/dev/urandom` (32 символа, буквенно-цифровые)
- `.env` и `credentials.txt` с правами 600
- `umask 077` при установке
- Белый список ключей при чтении `credentials.txt`
- Экранирование пользовательского ввода перед sed (защита от инъекций)
- `sudo rm -rf` защищён проверкой пути + маркером `.install-state`
- Таймауты curl на всех HTTP-запросах (5с подключение, 10с максимум)
- JSON формируется через `python3 json.dumps` (не конкатенация строк)

## Лицензия

MIT
