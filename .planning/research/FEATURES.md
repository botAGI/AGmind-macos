# Feature Landscape: Open Notebook + DB-GPT Integration (v1.1)

**Domain:** Optional AI tools for AGMind macOS installer
**Researched:** 2026-03-24
**Scope:** Only new features for v1.1 milestone. v1.0 features are shipped and not repeated here.
**Confidence:** HIGH for Open Notebook, MEDIUM for DB-GPT

---

## What These Tools Do

### Open Notebook (lfnovo/open-notebook)

Open-source аналог Google NotebookLM. Исследовательский AI-ноутбук:
- Загрузка источников: PDF, веб-страницы, YouTube, аудио
- Context-aware RAG-чат по загруженным материалам
- AI-заметки с цитированием источников
- Генерация подкастов (multi-speaker, управление скриптом)
- 16+ AI-провайдеров, включая Ollama
- REST API для интеграций
- Базовая аутентификация (username/password)
- i18n: китайский (simplified/traditional), расширяется

**Docker-стек:** Streamlit UI (порт 8502) + REST API (порт 5055) + SurrealDB v2 (порт 8000)
**Image:** `lfnovo/open_notebook:v1-latest`
**Source:** [GitHub](https://github.com/lfnovo/open-notebook), [Docker Hub](https://hub.docker.com/r/lfnovo/open_notebook), [Docs](https://github.com/lfnovo/open-notebook/blob/main/docs/1-INSTALLATION/docker-compose.md)

### DB-GPT (eosphoros-ai/DB-GPT)

Агентный AI-ассистент для работы с данными:
- Text-to-SQL: естественный язык -> SQL запросы (82.5% accuracy на Spider benchmark)
- Анализ данных с Python в песочнице
- Подключение к БД (MySQL, PostgreSQL, и др.)
- RAG по документам и knowledge bases
- AWEL: agentic workflow orchestration
- Визуализация данных (графики, дашборды)
- Поддержка proxy mode: Ollama, OpenAI, DeepSeek, и др.

**Docker-стек:** Webserver (порт 5670) + MySQL (порт 3306, собственная БД)
**Image:** `eosphorosai/dbgpt-openai:latest`
**Режим для macOS:** Proxy mode (LLM на хосте через Ollama, без GPU в Docker)
**Source:** [GitHub](https://github.com/eosphoros-ai/DB-GPT), [Docker Hub](https://hub.docker.com/r/eosphorosai/dbgpt), [docker-compose.yml](https://github.com/eosphoros-ai/DB-GPT/blob/main/docker-compose.yml)

---

## Table Stakes

Фичи, без которых интеграция будет ощущаться незаконченной. Пользователь сравнивает с паттернами v1.0 (weaviate/qdrant/monitoring profiles).

| ID | Feature | Why Expected | Complexity | Dependencies |
|----|---------|--------------|------------|-------------|
| TS-1 | Docker Compose profile `open-notebook` | Паттерн задан: weaviate, qdrant, monitoring, etl-extended | LOW | docker-compose.yml |
| TS-2 | Docker Compose profile `dbgpt` | Аналогично | MED | docker-compose.yml + MySQL service |
| TS-3 | Wizard вопрос 8: "Install Open Notebook? [y/N]" | Паттерн из monitoring/etl вопросов | LOW | lib/wizard.sh |
| TS-4 | Wizard вопрос 9: "Install DB-GPT? [y/N]" | Аналогично | LOW | lib/wizard.sh |
| TS-5 | Env vars `INSTALL_OPEN_NOTEBOOK=0`, `INSTALL_DBGPT=0` | NON_INTERACTIVE режим использует env vars для всего | LOW | env templates |
| TS-6 | COMPOSE_PROFILES расширение | Добавить `open-notebook`, `dbgpt` к существующей строке | LOW | lib/config.sh |
| TS-7 | Nginx reverse proxy routes | Все сервисы уже за nginx | LOW | nginx.conf.template |
| TS-8 | Health checks в phase_7 для optional tools | phase_7_health проверяет все запущенные сервисы | LOW | lib/health.sh |
| TS-9 | CLI `agmind status` показывает optional tools | Пользователь видит weaviate/qdrant -- ожидает видеть и новые | LOW | scripts/agmind.sh |
| TS-10 | Ollama connection через host.docker.internal | Уже работает для Dify/Open WebUI, паттерн задан | LOW | .env, compose |
| TS-11 | versions.env с пинами для новых образов | Централизованное управление версиями | LOW | templates/versions.env |
| TS-12 | Генерация secrets для Open Notebook | Аналог DIFY_SECRET_KEY, WEBUI_SECRET_KEY | LOW | lib/config.sh |
| TS-13 | Post-install сообщение с URL доступа | v1.0 выводит URLs для Dify/Open WebUI | LOW | install.sh |

---

## Differentiators

Фичи, повышающие ценность, но не блокирующие релиз.

| ID | Feature | Value Proposition | Complexity | Notes |
|----|---------|-------------------|------------|-------|
| D-1 | Open Notebook auto-configure Ollama | Ollama работает сразу, без ручной настройки в UI | LOW | `OLLAMA_BASE_URL=http://host.docker.internal:11434` в env |
| D-2 | DB-GPT TOML config для proxy-ollama | Ollama как LLM provider без ручной настройки | MED | Шаблон `configs/dbgpt-proxy-ollama.toml`, bind mount |
| D-3 | RAM preflight warning | Предупреждение если RAM < 16GB и выбраны оба инструмента | LOW | DB-GPT + MySQL ~2-3GB, Open Notebook + SurrealDB ~500MB |
| D-4 | Backup integration для новых volumes | `agmind backup` включает данные optional tools | MED | Расширить backup.sh: surrealdb_data, notebook_data, dbgpt_data |
| D-5 | `agmind doctor` проверяет optional tools | Doctor показывает полную картину здоровья | LOW | Проверять только если профиль активен |

---

## Anti-Features

Фичи, которые **не надо** строить.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Общая MySQL для Dify и DB-GPT | Dify использует PostgreSQL. Разные движки, разные данные | Отдельный `dbgpt-mysql` контейнер только для DB-GPT |
| Auto-provision AI providers в Open Notebook | Credentials -- через UI. env-based deprecation в v1.7.0+ | Post-install сообщение: "Откройте Settings -> AI Providers" |
| DB-GPT local model loading (не proxy) | Требует GPU в Docker, невозможно на macOS | Только proxy mode через host Ollama |
| Общий SurrealDB для других сервисов | SurrealDB специфичен для Open Notebook | Изолированный сервис и том |
| Wizard deep-configuration для tools | Перегрузит wizard (уже 7 вопросов) | Только y/N; настройка через web UI инструментов |
| DB-GPT database connection wizard | Подключение к пользовательским БД -- через web UI | Post-install hint: "Подключите свои БД через DB-GPT UI" |
| Streamlit path prefix override | Streamlit плохо поддерживает sub-path routing | Отдельный порт через nginx upstream, location `/notebook/` |

---

## Wizard Questions Design

### Существующие вопросы (1-7): без изменений

### Новые вопросы (8-9):

**Question 8: Open Notebook**
```
AI Research Notebook (Open Notebook):
  [1] No   (default) -- skip, saves ~500MB RAM
  [2] Yes  -- AI notes, PDF/web/YouTube RAG, podcast generation
Choice [1]:
```

**Question 9: DB-GPT**
```
AI Data Assistant (DB-GPT):
  [1] No   (default) -- skip, saves ~2GB RAM
  [2] Yes  -- Text-to-SQL, database analytics, data visualization
Choice [1]:
```

**Design rationale:**
- Default = No: оба инструмента опциональные, не core RAG stack
- Порядок: после backup (вопрос 7), перед confirmation summary
- Формат: совпадает с паттерном monitoring (default=none)
- RAM hint в описании: помогает пользователю с ограниченной памятью

### Non-Interactive Env Vars

| Variable | Default | Valid Values | Pattern Source |
|----------|---------|-------------|----------------|
| `INSTALL_OPEN_NOTEBOOK` | `0` | `0`, `1` | Аналог MONITORING_MODE |
| `INSTALL_DBGPT` | `0` | `0`, `1` | Аналог MONITORING_MODE |

---

## Nginx Routing

### Новые upstream блоки

```nginx
upstream open-notebook-ui {
    server open-notebook:8502;
}

upstream dbgpt {
    server dbgpt:5670;
}
```

### Новые location блоки

| Tool | Location | Notes |
|------|----------|-------|
| Open Notebook | `/notebook/` | Streamlit: нужен WebSocket upgrade (Upgrade + Connection headers) |
| DB-GPT | `/dbgpt/` | Стандартный HTTP proxy |

**Важно:** Streamlit (Open Notebook) использует WebSocket для hot-reload. Nginx config должен включать:
```nginx
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
```

### Условная генерация

Nginx upstream/location блоки добавляются в `nginx.conf` только если соответствующий инструмент выбран. Паттерн: config.sh уже условно генерирует конфиг (разные шаблоны для weaviate/qdrant).

---

## CLI Awareness

### `agmind status`

Добавить секцию "Optional Tools:" после основных сервисов:
```
Optional Tools:
  [UP]    open-notebook       http://mac-studio.local/notebook/
  [UP]    dbgpt               http://mac-studio.local/dbgpt/
```
Или если не установлен:
```
  [SKIP]  open-notebook       (not installed)
```

Определение: проверять COMPOSE_PROFILES в `.env` файле.

### `agmind start/stop/restart`

Никаких изменений -- `docker compose up/down` автоматически управляет всеми профилями через COMPOSE_PROFILES.

### `agmind doctor`

Добавить проверки (только если профиль активен):
- Open Notebook: `curl -sf http://localhost:8502/_stcore/health`
- DB-GPT: `curl -sf http://localhost:5670/api/health`
- SurrealDB: `curl -sf http://localhost:8000/health`
- DB-GPT MySQL: `docker exec dbgpt-mysql mysqladmin ping`

### `agmind logs`

Уже работает через `docker compose logs <service>`. Поддержать имена сервисов:
- `agmind logs open-notebook`
- `agmind logs dbgpt`
- `agmind logs surrealdb`
- `agmind logs dbgpt-mysql`

---

## Docker Compose Services

### Open Notebook (profile: open-notebook)

```yaml
surrealdb:
  image: surrealdb/surrealdb:${SURREALDB_VERSION}
  restart: always
  profiles: [open-notebook]
  command: start --log info file:/mydata/database.db
  volumes:
    - surrealdb_data:/mydata

open-notebook:
  image: lfnovo/open_notebook:${OPEN_NOTEBOOK_VERSION}
  restart: always
  profiles: [open-notebook]
  environment:
    OPEN_NOTEBOOK_ENCRYPTION_KEY: ${OPEN_NOTEBOOK_ENCRYPTION_KEY}
    SURREAL_URL: ws://surrealdb:8000/rpc
    SURREAL_USER: root
    SURREAL_PASSWORD: ${SURREAL_PASSWORD}
    SURREAL_NAMESPACE: open_notebook
    SURREAL_DATABASE: open_notebook
    OLLAMA_BASE_URL: http://host.docker.internal:11434
  volumes:
    - notebook_data:/app/data
  depends_on:
    - surrealdb
  extra_hosts:
    - "host.docker.internal:host-gateway"
```

### DB-GPT (profile: dbgpt)

```yaml
dbgpt-mysql:
  image: mysql/mysql-server:${DBGPT_MYSQL_VERSION}
  restart: always
  profiles: [dbgpt]
  environment:
    MYSQL_ROOT_PASSWORD: ${DBGPT_MYSQL_ROOT_PASSWORD}
    MYSQL_DATABASE: dbgpt
  volumes:
    - dbgpt_mysql_data:/var/lib/mysql
  healthcheck:
    test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
    interval: 10s
    timeout: 5s
    retries: 5
    start_period: 30s

dbgpt:
  image: eosphorosai/dbgpt-openai:${DBGPT_VERSION}
  restart: always
  profiles: [dbgpt]
  environment:
    MYSQL_HOST: dbgpt-mysql
    MYSQL_PORT: "3306"
    MYSQL_DATABASE: dbgpt
    MYSQL_USER: root
    MYSQL_PASSWORD: ${DBGPT_MYSQL_ROOT_PASSWORD}
  volumes:
    - dbgpt_data:/data
  depends_on:
    dbgpt-mysql:
      condition: service_healthy
  extra_hosts:
    - "host.docker.internal:host-gateway"
```

### Новые volumes

```yaml
volumes:
  # ... existing volumes ...
  surrealdb_data:
  notebook_data:
  dbgpt_mysql_data:
  dbgpt_data:
```

---

## New Environment Variables

### Добавить в .env templates

```bash
# =============================================================================
# Open Notebook (optional)
# =============================================================================
OPEN_NOTEBOOK_ENCRYPTION_KEY={{OPEN_NOTEBOOK_ENCRYPTION_KEY}}
SURREAL_PASSWORD={{SURREAL_PASSWORD}}

# =============================================================================
# DB-GPT (optional)
# =============================================================================
DBGPT_MYSQL_ROOT_PASSWORD={{DBGPT_MYSQL_ROOT_PASSWORD}}
```

### Добавить в versions.env

```bash
# Optional Tools
SURREALDB_VERSION=v2
OPEN_NOTEBOOK_VERSION=v1-latest
DBGPT_VERSION=latest
DBGPT_MYSQL_VERSION=latest
```

---

## Resource Impact

| Component | RAM (approx) | Disk (images) | Disk (data) |
|-----------|-------------|---------------|-------------|
| Open Notebook + SurrealDB | ~500MB | ~1.5GB | По мере использования |
| DB-GPT + MySQL | ~2GB | ~3GB | По мере использования |
| Оба вместе | ~2.5GB | ~4.5GB | По мере использования |

**Рекомендация:** В wizard для систем с 8GB RAM: если выбраны оба инструмента, показать предупреждение:
```
[WARN] With both optional tools, total RAM usage may reach ~6GB+.
       Your system has 8GB. Core stack requires ~4GB. Consider selecting one.
       Continue? [y/N]
```

---

## Feature Dependencies

```
INSTALL_OPEN_NOTEBOOK=1
  -> "open-notebook" добавляется в COMPOSE_PROFILES string
  -> surrealdb + open-notebook services в docker-compose.yml
  -> OPEN_NOTEBOOK_ENCRYPTION_KEY + SURREAL_PASSWORD генерируются в config.sh
  -> OLLAMA_BASE_URL=http://host.docker.internal:11434 в env
  -> upstream open-notebook-ui в nginx.conf.template
  -> location /notebook/ в nginx.conf.template
  -> health check в lib/health.sh (phase 7)
  -> status display в scripts/agmind.sh
  -> volumes: surrealdb_data, notebook_data

INSTALL_DBGPT=1
  -> "dbgpt" добавляется в COMPOSE_PROFILES string
  -> dbgpt-mysql + dbgpt services в docker-compose.yml
  -> DBGPT_MYSQL_ROOT_PASSWORD генерируется в config.sh
  -> upstream dbgpt в nginx.conf.template
  -> location /dbgpt/ в nginx.conf.template
  -> health check в lib/health.sh (phase 7)
  -> status display в scripts/agmind.sh
  -> volumes: dbgpt_mysql_data, dbgpt_data

Оба инструмента полностью независимы друг от друга.
Оба зависят от: Ollama на хосте (Phase 4), Docker runtime (Phase 3).
```

---

## MVP Recommendation (v1.1)

### Build Now

1. **TS-1,2:** Docker Compose profiles для обоих инструментов
2. **TS-3,4,5:** Wizard вопросы + non-interactive env vars
3. **TS-6:** COMPOSE_PROFILES расширение
4. **TS-7:** Nginx routing с WebSocket support
5. **TS-8:** Health checks в phase_7
6. **TS-9:** CLI status awareness
7. **TS-10,11,12:** Env vars, versions.env, secret generation
8. **TS-13:** Post-install сообщение с URLs
9. **D-1:** Open Notebook Ollama auto-config (env var -- trivial)

### Defer to v1.2

- **D-2:** DB-GPT TOML auto-config: формат конфига недостаточно документирован, MEDIUM confidence. Исследовать отдельно.
- **D-4:** Backup integration для новых volumes
- **D-3:** RAM preflight warning (nice-to-have)

---

## Open Questions

1. **DB-GPT TOML config format:** Документация частично на китайском. Нужно исследовать точный формат `configs/dbgpt-proxy-ollama.toml` для proxy mode с Ollama. Без этого DB-GPT потребует ручной настройки LLM provider через UI.

2. **Streamlit sub-path routing:** Streamlit по умолчанию не поддерживает sub-path (`/notebook/`). Может потребоваться `--server.baseUrlPath=/notebook/` флаг или проксирование на отдельный порт без path prefix. Нужно проверить при реализации.

3. **DB-GPT healthcheck endpoint:** `/api/health` -- предположение на основе общего паттерна. Нужно верифицировать конкретный endpoint из документации или тестирования.

4. **DB-GPT image variants:** `eosphorosai/dbgpt-openai:latest` -- для proxy mode. Есть другие варианты (`eosphorosai/dbgpt`). Нужно подтвердить, что `-openai` вариант работает с Ollama через OpenAI-compatible API.

---

## Sources

- [Open Notebook GitHub](https://github.com/lfnovo/open-notebook) -- HIGH confidence
- [Open Notebook Docker Compose docs](https://github.com/lfnovo/open-notebook/blob/main/docs/1-INSTALLATION/docker-compose.md) -- HIGH confidence
- [Open Notebook .env.example](https://github.com/lfnovo/open-notebook/blob/main/.env.example) -- HIGH confidence
- [Open Notebook Docker Hub](https://hub.docker.com/r/lfnovo/open_notebook) -- HIGH confidence
- [DB-GPT GitHub](https://github.com/eosphoros-ai/DB-GPT) -- MEDIUM confidence
- [DB-GPT Docker Hub](https://hub.docker.com/r/eosphorosai/dbgpt) -- MEDIUM confidence
- [DB-GPT docker-compose.yml](https://github.com/eosphoros-ai/DB-GPT/blob/main/docker-compose.yml) -- HIGH confidence
- [DB-GPT Proxy LLMs docs](http://docs.dbgpt.cn/docs/installation/advanced_usage/More_proxyllms/) -- LOW confidence (timeout при запросе)
- [DB-GPT Ollama issue #2894](https://github.com/eosphoros-ai/DB-GPT/issues/2894) -- MEDIUM confidence
