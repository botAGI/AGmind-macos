# Project Research Summary

**Project:** AGMind macOS Installer — v1.1 (Open Notebook + DB-GPT)
**Domain:** Optional AI tools integration into existing Docker Compose bash installer
**Researched:** 2026-03-20 (v1.0), updated 2026-03-24 (v1.1 full research)
**Confidence:** MEDIUM-HIGH (Open Notebook HIGH, DB-GPT MEDIUM)

## Executive Summary

Версия v1.1 расширяет существующий AGMind macOS стек двумя опциональными AI-инструментами: Open Notebook (аналог Google NotebookLM с поддержкой PDF/YouTube/аудио источников и генерацией подкастов) и DB-GPT (Text-to-SQL ассистент с 82.5% точностью на Spider benchmark). Оба инструмента интегрируются как Docker Compose profile-gated сервисы — паттерн уже используется для weaviate/qdrant/monitoring в v1.0, поэтому архитектурных нововведений не требуется. Существующий pipeline wizard -> config.sh -> compose profiles -> health checks охватывает всю необходимую логику.

Рекомендуемый подход: минимальное воздействие на существующий код (minimal blast radius). Open Notebook добавляет 2 контейнера (open-notebook + SurrealDB v2); DB-GPT — 1 контейнер в SQLite-режиме без MySQL (использовать lightweight `dbgpt-openai` образ ~2 GB CPU-only proxy mode, а не полный `dbgpt` с 10+ GB и GPU). Оба инструмента подключаются к нативному Ollama через `host.docker.internal:11434`. Новых brew-пакетов, новых фаз install.sh и новых lib/*.sh модулей не требуется.

Основные риски сосредоточены в трёх областях: (1) неподтверждённая поддержка arm64 у DB-GPT образа на Apple Silicon — требует проверки до начала реализации; (2) nginx падает при разрешении DNS для профильных сервисов, которые не запущены — решается условной генерацией nginx.conf через маркеры в шаблоне; (3) `OPEN_NOTEBOOK_ENCRYPTION_KEY` теряется при переустановке если не добавить его в существующую систему персистентных secrets в config.sh. Все три риска имеют конкретные митигации и не блокируют реализацию.

---

## Key Findings

### Recommended Stack

Стек v1.1 добавляет три новых Docker-образа к существующей v1.0 инфраструктуре. Никаких новых brew-пакетов не требуется. Open Notebook обязательно требует SurrealDB v2 (нет альтернатив; v1 API несовместим). DB-GPT в proxy/ollama режиме не нуждается в MySQL — SQLite достаточен для single-user локального развёртывания.

**v1.0 стек (без изменений):** Bash 3.2, Homebrew 5.x, Colima 0.10.x, Docker CLI 29.x / Compose 5.x, Ollama 0.17+ (native brew), BATS 1.13.0, Dify 1.13.2, Open WebUI, PostgreSQL 15, Redis 6, Weaviate/Qdrant, Nginx.

**v1.1 новые технологии:**
- `lfnovo/open_notebook:v1-latest` — AI research notebook (NotebookLM альтернатива) — официальный Docker образ, стабильный v1.x track, v1.8.1 последний (2025-03-11)
- `surrealdb/surrealdb:v2` — Document DB для Open Notebook — обязательная зависимость, встроенный RocksDB, легковесный single-binary
- `eosphorosai/dbgpt-openai:latest` — Text-to-SQL ассистент — CPU proxy mode, делегирует inference в Ollama, ~2 GB (не полный `dbgpt` 10+ GB)

**Версионный пининг (additions to versions.env):**
```
OPEN_NOTEBOOK_VERSION=v1-latest
SURREALDB_VERSION=v2
DBGPT_VERSION=latest
```
Примечание: `latest` для DB-GPT приемлем краткосрочно; пин к конкретному SHA рекомендован после тестирования arm64.

### Expected Features

Полный список в `.planning/research/FEATURES.md`.

**Must have (table stakes) — v1.1 (13 TS-фич):**
- Docker Compose profiles `open-notebook` и `dbgpt` (паттерн уже установлен weaviate/monitoring)
- Wizard вопросы 8-9 с y/N и RAM-хинтами (RAM savings указаны явно: ~500 MB и ~2 GB)
- `INSTALL_OPEN_NOTEBOOK=0` / `INSTALL_DBGPT=0` env vars для non-interactive режима
- Расширение COMPOSE_PROFILES string в `_build_compose_profiles()`
- Nginx reverse proxy `/notebook/` (с WebSocket для Streamlit) и `/dbgpt/`
- Health checks в phase_7 условно для новых сервисов
- `agmind status` показывает optional tools с URL или `[SKIP]` если не установлен
- Генерация secrets: `OPEN_NOTEBOOK_ENCRYPTION_KEY`, `SURREAL_PASSWORD` — персистентно в credentials.txt
- Post-install summary с URL доступа

**Should have (дифференциаторы):**
- `OLLAMA_BASE_URL=http://host.docker.internal:11434` в env (auto-connect для Open Notebook, trivial)
- DB-GPT TOML config `dbgpt-ollama.toml` автогенерация (Ollama без ручной настройки; сложность MEDIUM)
- RAM preflight warning для систем с 8 GB при выборе обоих инструментов

**Defer to v1.2:**
- Backup integration для новых volumes (surrealdb_data, notebook_data, dbgpt_data) — Питфол 5 (SurrealDB durability) делает это важным, но не блокирующим v1.1
- DB-GPT healthcheck endpoint верификация

**Anti-features (НЕ строить):**
- MySQL контейнер для DB-GPT — SQLite достаточен, MySQL adds unnecessary complexity
- Auto-provision AI providers в Open Notebook через env — deprecated в v1.7+, UI-only
- DB-GPT local model loading — требует GPU в Docker, невозможно на macOS
- Wizard deep-configuration для tools — перегрузка; только y/N, настройка через web UI

### Architecture Approach

Интеграция следует принципу "minimal blast radius": модифицируются 10 существующих файлов, добавляются 3 новых файла (2 BATS теста + 1 TOML шаблон). Никаких новых lib/*.sh модулей, никаких новых фаз install.sh. Весь новый код встраивается в существующий pipeline.

**Модифицируемые файлы и сложность:**

| Файл | Изменения | Сложность |
|------|-----------|-----------|
| `lib/wizard.sh` | Добавить вопросы 8-9, `_wizard_ask_yesno()`, экспортировать `WIZARD_OPEN_NOTEBOOK`, `WIZARD_DBGPT` | LOW |
| `lib/config.sh` | Расширить profile builder, добавить secrets, conditional nginx rendering, `_render_dbgpt_config()` | MEDIUM |
| `templates/docker-compose.yml` | 3 новых service blocks, 4 новых volumes | MEDIUM |
| `templates/nginx.conf.template` | Маркеры `{{OPTIONAL_UPSTREAMS}}` и `{{OPTIONAL_LOCATIONS}}` | LOW |
| `templates/env.lan.template` + `env.offline.template` | Новые секции для optional tools | LOW |
| `templates/versions.env` | 3 новых версионных пина | LOW |
| `lib/health.sh` | Условные проверки по активным профилям | LOW |
| `scripts/agmind.sh` | `cmd_status()` читает COMPOSE_PROFILES, показывает optional tools | LOW |
| `install.sh` | URLs в Phase 9 summary (условно) | LOW |

**Новые файлы:**

| Файл | Назначение |
|------|-----------|
| `templates/dbgpt-ollama.toml` | TOML конфиг DB-GPT для proxy/ollama mode с `{{WIZARD_LLM_MODEL}}` и `{{WIZARD_EMBED_MODEL}}` |
| `tests/test_wizard_optional.bats` | BATS тесты для вопросов 8-9 |
| `tests/test_config_optional.bats` | BATS тесты для profile building и secrets |

**Сетевая топология:** Все сервисы в одной Docker network. Nginx — единственная точка входа (порт 80). Новые сервисы НЕ экспонируют порты на хост. Open Notebook: только порт 8502 (Streamlit v1.1+ объединяет web UI и API через Next.js rewrites). DB-GPT: только порт 5670. SurrealDB: внутренний только (не экспонировать из-за конфликта с Weaviate:8000).

**Data flow:**
```
Wizard (Q8-Q9)
  -> WIZARD_OPEN_NOTEBOOK, WIZARD_DBGPT
    -> config.sh: profile строка, secrets, nginx.conf, dbgpt-ollama.toml
      -> docker compose up (COMPOSE_PROFILES="...,open-notebook,dbgpt")
        -> phase_7_health: условные проверки
          -> Phase 9 summary: URLs
```

### Critical Pitfalls

Полный список (15 питфолов) в `.planning/research/v1.1-PITFALLS.md`.

**Критические (rewrite-level):**

1. **DB-GPT arm64 поддержка не подтверждена** — `eosphorosai/dbgpt-openai` — amd64-first проект. На Apple Silicon возможна Rosetta эмуляция с 3-5x падением производительности или полным отказом запуска. Проверить `docker manifest inspect eosphorosai/dbgpt-openai:latest | grep architecture` до начала реализации. При отсутствии arm64: добавить `platform: linux/amd64` в compose + предупреждение в wizard. Фаза: **Preflight**.

2. **Nginx упадёт при отсутствии optional upstream** — Nginx резолвит все upstream hostnames при старте. Profile-gated контейнер не запущен = DNS не существует = весь nginx (и весь стек) падает. Решение: `_render_nginx_conf()` условно инжектирует upstream/location блоки через маркеры в шаблоне. Фаза: **Config Generation**.

3. **Open Notebook encryption key теряется при переустановке** — Если `OPEN_NOTEBOOK_ENCRYPTION_KEY` не добавлен в whitelist `_load_or_generate_secrets()` в config.sh, при каждой переустановке генерируется новый ключ — все сохранённые credentials в UI становятся нечитаемы. Добавить в case-statement в config.sh. Фаза: **Config Generation**.

4. **DB-GPT требует TOML файл, не env vars** — DB-GPT игнорирует `OLLAMA_BASE_URL` env var; LLM provider настраивается через TOML config с `api_base` полем. Без смонтированного TOML файла DB-GPT стартует без LLM. Фаза: **Config Generation**.

5. **depends_on с profiled сервисами ломает Compose** — До Docker Compose 2.20.2, `depends_on` на профильный сервис падает с "service is disabled". Не добавлять `open-notebook`/`dbgpt` в depends_on nginx. При необходимости: `required: false` (Compose >= 2.20.2). Проверить `docker compose version` в preflight. Фаза: **Config Generation / Preflight**.

**Умеренные (workaround exists):**

6. **SurrealDB durability риски** — Молодая БД (v2.x), community concerns по fsync. Пин к конкретной версии `v2.2.1` вместо floating `v2`. Data loss при crash — включить в backup в v1.2.
7. **COMPOSE_PROFILES строка** — fragile string concatenation в Bash 3.2. Profile names должны точно совпадать (openhyphen-notebook, не opennotebook). BATS тесты для всех комбинаций.
8. **Streamlit sub-path routing** — Highest-risk integration point. Тест `/notebook/` path prefix первым делом при реализации. Запасной план: отдельный порт через nginx listener.
9. **DB-GPT SiliconFlow API key** — Default entrypoint требует `SILICONFLOW_API_KEY`. Override command в compose для Ollama-only режима.
10. **Память на 8-16 GB системах** — Open Notebook + SurrealDB ~500 MB, DB-GPT ~2 GB. Wizard должен предупреждать при 8 GB + оба инструмента.

---

## Implications for Roadmap

v1.1 реализация укладывается в существующую фазовую структуру v1.0. Новых фаз install.sh не требуется. Все изменения — расширения существующих модулей в той же dependency order что и v1.0.

### Phase 1: Wizard Extension
**Rationale:** Wizard — первый шаг pipeline. Без `WIZARD_OPEN_NOTEBOOK` и `WIZARD_DBGPT` экспортов ни один последующий компонент не знает что устанавливать.
**Delivers:** `_wizard_ask_yesno()` helper (переиспользуемый), вопросы 8-9 с RAM hints, non-interactive env vars поддержка
**Addresses:** TS-3, TS-4, TS-5
**Avoids:** Питфол 14 (RAM pressure warning в wizard для систем с 8 GB)
**Research flag:** Стандартный паттерн — дополнительное исследование не нужно

### Phase 2: Config Generation Extensions
**Rationale:** Центральный модуль. Здесь решается самый большой класс питфолов (nginx, secrets, TOML, profile string assembly).
**Delivers:** Расширение `_build_compose_profiles()`, persistent secrets generation, conditional nginx.conf rendering, `_render_dbgpt_config()` для TOML шаблона
**Uses:** Точные форматы env vars и TOML структуры из STACK.md
**Implements:** Архитектурные компоненты 2, 4, 5
**Avoids:** Питфолы 7, 8, 9, 10 (nginx DNS, encryption key persistence, TOML config, profile string)
**Research flag:** DB-GPT TOML embedding section (`api_url` vs `api_base`) — верифицировать при реализации

### Phase 3: Docker Compose Template
**Rationale:** После config.sh решений — нужны сами сервисные определения.
**Delivers:** 3 новых profile-gated сервиса, 4 новых Docker volumes, healthcheck definitions
**Uses:** Верифицированные Docker compose snippets из STACK.md
**Avoids:** Питфолы 2, 3, 6 (без MySQL, без host port exposure для SurrealDB, depends_on без cross-profile refs)
**Research flag:** arm64 поддержка DB-GPT — `docker manifest inspect` ОБЯЗАТЕЛЬНО до начала этой фазы

### Phase 4: Nginx Routing
**Rationale:** После compose сервисов — маршруты трафика через существующий nginx.
**Delivers:** Conditional upstream/location blocks для `/notebook/` и `/dbgpt/`, WebSocket headers для Streamlit
**Avoids:** Питфол 7 (nginx DNS failure) через conditional template rendering
**Research flag:** Sub-path routing для Streamlit — ТЕСТИРОВАТЬ ПЕРВЫМ при реализации. Запасной план готов.

### Phase 5: Health Checks + CLI
**Rationale:** Замыкание integration loop — health.sh и agmind.sh должны видеть optional tools.
**Delivers:** Условные health check targets, `agmind status` с optional tool URLs, Phase 9 summary extensions
**Addresses:** TS-8, TS-9, TS-13, D-3 (RAM warning)
**Avoids:** Питфолы 13, 15 (health gaps, CLI unawareness)
**Research flag:** DB-GPT healthcheck endpoint не задокументирован — тестировать `/api/health`, fallback на running state check

### Phase 6: Tests
**Rationale:** Верификация корректности profile string assembly и wizard logic для всех комбинаций.
**Delivers:** `test_wizard_optional.bats`, `test_config_optional.bats` с покрытием всех 4 профильных комбинаций
**Avoids:** Питфол 10 (fragile COMPOSE_PROFILES string)
**Research flag:** Стандартный BATS паттерн — дополнительное исследование не нужно

### Phase Ordering Rationale

- Wizard первый: все остальные компоненты зависят от `WIZARD_*` экспортов
- Config Generation второй: nginx/secrets/TOML — самый критичный класс питфолов; лучше решить централизованно перед написанием compose шаблонов
- Compose Template третий: опирается на решения config.sh (названия profiles, volume names)
- Nginx четвёртым: зависит от compose service names и выбора sub-path vs port routing
- Health/CLI пятыми: расширения, не блокирующие core functionality
- Тесты финально: охватывают полный pipeline после написания

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack (v1.0) | HIGH | Верифицирован на live macOS 26.3 / M4 Pro / Colima 0.10.1 |
| Stack (v1.1 Open Notebook) | HIGH | Официальная документация, docker-compose.yml верифицирован, .env.example верифицирован |
| Stack (v1.1 DB-GPT) | MEDIUM | Proxy образ верифицирован на Docker Hub; docs.dbgpt.cn нестабилен (таймауты); TOML формат из нескольких вторичных источников |
| Features | HIGH | Прямо выведены из project spec и существующих паттернов; 13 TS-фич чётко определены |
| Architecture | HIGH | Существующий codebase проанализирован; integration pattern идентичен weaviate/monitoring; никаких новых паттернов |
| Pitfalls | MEDIUM-HIGH | Nginx DNS и depends_on питфолы HIGH (задокументированные баги). DB-GPT arm64 и SurrealDB durability MEDIUM (требуют тестирования) |

**Overall confidence:** MEDIUM-HIGH

### Gaps to Address

- **DB-GPT arm64:** `docker manifest inspect eosphorosai/dbgpt-openai:latest` ОБЯЗАТЕЛЕН до начала Phase 3. Если arm64 нет — решить: платформенная эмуляция с предупреждением или исключить DB-GPT из v1.1.
- **DB-GPT TOML embedding field:** `api_url` vs `api_base` — поле для embeddings section. Использовать оба в template как safety, верифицировать при тестировании.
- **Streamlit sub-path routing:** Тест `/notebook/` prefix первым шагом Phase 4. При неудаче — nginx listener на отдельном порту (запасной план задокументирован в ARCHITECTURE.md).
- **DB-GPT healthcheck endpoint:** `/api/health` — предположение. При реализации: попробовать, если 404 — использовать running state check.
- **SurrealDB version pin:** floating `v2` tag несёт risk. Пин к `v2.2.1` или digest рекомендован в versions.env.
- **Open Notebook v2.x compatibility:** `v1-latest` tag защищает, но мониторить upstream релизы.

---

## Sources

### Primary (HIGH confidence)
- Live macOS 26.3 (Tahoe), Apple M4 Pro, 24 GB RAM — верифицированное системное поведение
- [Open Notebook Docker Compose docs](https://github.com/lfnovo/open-notebook/blob/main/docs/1-INSTALLATION/docker-compose.md)
- [Open Notebook .env.example](https://github.com/lfnovo/open-notebook/blob/main/.env.example)
- [Open Notebook AI providers config](https://github.com/lfnovo/open-notebook/blob/main/docs/5-CONFIGURATION/ai-providers.md)
- [Open Notebook v1.1.0 release (simplified reverse proxy)](https://github.com/lfnovo/open-notebook/releases/tag/v1.1.0)
- [Open Notebook releases](https://github.com/lfnovo/open-notebook/releases) — v1.8.1 latest (2025-03-11)
- [DB-GPT docker-compose.yml](https://github.com/eosphoros-ai/DB-GPT/blob/main/docker-compose.yml)
- [DB-GPT Docker Hub (dbgpt-openai)](https://hub.docker.com/r/eosphorosai/dbgpt-openai)
- [Docker Compose profiles docs](https://docs.docker.com/compose/how-tos/profiles/)
- [Docker Compose depends_on profiles bug #10751](https://github.com/docker/compose/issues/10751)
- [Docker Compose optional depends_on v2.20.2+](https://nickjanetakis.com/blog/optional-depends-on-with-docker-compose-v2-20-2)

### Secondary (MEDIUM confidence)
- [DB-GPT releases](https://github.com/eosphoros-ai/DB-GPT/releases) — v0.7.5 latest (2025-02-11)
- [DB-GPT Ollama proxy config](http://docs.dbgpt.cn/docs/installation/advanced_usage/More_proxyllms/) — docs сайт нестабилен
- [DB-GPT Ollama networking issue #2894](https://github.com/eosphoros-ai/DB-GPT/issues/2894) — workaround подтверждён
- [SurrealDB Docker image](https://hub.docker.com/r/surrealdb/surrealdb) — v2 tag подтверждён
- [SurrealDB running with Docker](https://surrealdb.com/docs/surrealdb/installation/running/docker)

### Tertiary (LOW confidence)
- [SurrealDB data durability concerns (Lobsters)](https://lobste.rs/s/8tycd0/surrealdb_is_sacrificing_data) — structural risk, не Open Notebook-специфичные отчёты
- DB-GPT TOML `api_url` vs `api_base` для embeddings — нужна верификация при реализации

---
*Research completed: 2026-03-24 (v1.1 full research synthesis)*
*Ready for roadmap: yes*
