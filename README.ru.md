# AGMind macOS Installer

[![Лицензия](https://img.shields.io/badge/Лицензия-Apache%202.0-blue.svg)](LICENSE)
[![Тесты](https://img.shields.io/badge/тесты-230%20пройдено-brightgreen.svg)]()
[![macOS](https://img.shields.io/badge/macOS-13%20Ventura%2B-000000.svg)]()
[![Bash](https://img.shields.io/badge/bash-3.2%20совместим-4EAA25.svg)]()

**[English version (README.md)](README.md)**

Установщик полного локального AI/RAG стека на macOS одной командой.
Разворачивает **Dify, Open WebUI, Ollama, Weaviate/Qdrant, PostgreSQL, Redis, Nginx** — с опциональными **Open Notebook** и **DB-GPT** — оптимизирован для Mac Studio и Mac Pro с нативным ускорением Metal GPU.

```bash
git clone https://github.com/botAGI/AGmind-macos.git
cd AGmind-macos
bash install.sh
```

> **Тестовый прогон** — проверяет весь 9-фазный флоу без sudo, Docker и любых изменений в системе:
> ```bash
> bash install.sh --dry-run
> ```

## Зачем AGMind?

Запуск AI локально на macOS — это борьба с Docker-особенностями, сетью Ollama, Compose-профилями, nginx-роутингом, LaunchAgents вместо systemd и BSD-утилитами вместо GNU. AGMind решает всё это одной командой.

- **Ускорение Metal GPU** — Ollama работает нативно через Homebrew, не в Docker
- **Без настройки** — мастер определяет оборудование и рекомендует модели
- **Опциональные инструменты** — Open Notebook или DB-GPT одним "да"
- **Готов ко второму дню** — CLI `agmind` для статуса, диагностики, бэкапа, остановки/запуска

## Что делает

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

## Требования

| | Минимум |
|--|---------|
| **macOS** | 13 Ventura+ |
| **Архитектура** | Apple Silicon (arm64) или Intel (x86_64) |
| **RAM** | 8 ГБ (рекомендуется 24+ ГБ) |
| **Диск** | 30 ГБ свободно |
| **Порты** | 80, 3000 свободны |

## Быстрый старт

### Интерактивный режим

```bash
bash install.sh
```

Мастер задаёт 9 вопросов с умными значениями по умолчанию на основе вашего оборудования.

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

| Флаг | Описание |
|------|----------|
| `--verbose` | Подробный вывод |
| `--non-interactive` | Без вопросов, читает из env vars |
| `--dry-run` | Полный 9-фазный прогон без изменений |
| `--force-phase N` | Перезапустить фазу N |
| `--help` | Показать справку |

## Стек

| Компонент | Запуск | Доступ |
|-----------|--------|--------|
| **Dify** (API + Worker + Web) | Docker | `http://<ip>/apps/` |
| **Open WebUI** | Docker | `http://<ip>/` |
| **Ollama** | **Нативный** (brew) | `http://localhost:11434` |
| **Weaviate** или **Qdrant** | Docker | внутренний |
| **PostgreSQL** + **Redis** | Docker | внутренний |
| **Nginx** | Docker | порт 80 |
| **Open Notebook** *(опц.)* | Docker | `http://<ip>/notebook/` |
| **DB-GPT** *(опц.)* | Docker | `http://<ip>/dbgpt/` |

## Опциональные инструменты

### Open Notebook

AI-блокнот для исследований ([lfnovo/open-notebook](https://github.com/lfnovo/open-notebook)) — open-source альтернатива Google NotebookLM. PDF, видео, аудио с векторным поиском и генерацией подкастов. Разворачивается с SurrealDB.

### DB-GPT

AI-ассистент для баз данных ([eosphoros-ai/DB-GPT](https://github.com/eosphoros-ai/DB-GPT)) — Text-to-SQL, RAG по базам данных, мульти-агентная оркестрация. SQLite-режим с Ollama proxy — GPU в Docker не нужен.

Оба устанавливаются через Docker Compose profiles при выборе в мастере. Подключаются к нативному Ollama через `host.docker.internal:11434`.

## Рекомендации моделей

Автовыбор на основе объёма единой памяти:

| RAM | LLM |
|-----|-----|
| 8 ГБ | gemma3:4b |
| 16 ГБ | qwen2.5:7b |
| 32 ГБ | qwen2.5:14b |
| 64 ГБ | gemma3:27b |
| 96 ГБ+ | qwen2.5:72b |

## CLI

```bash
agmind status      # Статус сервисов, Ollama, IP, опциональные тулзы
agmind doctor      # Проверки здоровья — PASS/WARN/FAIL
agmind start       # Сначала Ollama, потом Docker Compose
agmind stop        # Docker Compose down, затем Ollama
agmind restart     # Перезапуск
agmind logs [svc]  # Логи Compose (последние 50) или конкретный сервис
agmind backup      # Ручной бэкап с ротацией
agmind uninstall   # Полное удаление с подтверждением
```

## Профили

| Профиль | Описание |
|---------|----------|
| `lan` | Локальная сеть, без TLS |
| `offline` | Автономный, без интернета |

## Структура проекта

```
agmind-macos/
├── install.sh                          # 9-фазный оркестратор + dry-run
├── lib/                                # 11 bash-модулей
│   ├── common.sh                       #   логирование, ошибки, BSD-утилиты
│   ├── detect.sh                       #   определение оборудования, preflight
│   ├── wizard.sh                       #   интерактивная настройка (9 вопросов)
│   ├── docker.sh                       #   Colima / Docker Desktop
│   ├── ollama.sh                       #   нативный Ollama через brew
│   ├── config.sh                       #   шаблоны, секреты, TOML
│   ├── compose.sh, health.sh           #   деплой + проверка здоровья
│   ├── models.sh, openwebui.sh         #   загрузка моделей + админ
│   └── backup.sh                       #   управление LaunchAgents
├── scripts/
│   ├── agmind.sh                       # CLI (8 команд)
│   ├── backup.sh                       # бэкап по расписанию с ротацией
│   └── health-gen.sh                   # генерация JSON-отчётов
├── templates/                          # Compose, env, nginx, TOML, plists
└── tests/
    ├── unit/          (230 BATS-тестов)
    ├── integration-test.sh
    └── helpers/       (мок-исполняемые)
```

## Тестирование

```bash
bash install.sh --dry-run               # Полный флоу, без sudo, 1 секунда
bats tests/unit/                        # 230 юнит-тестов
bash tests/integration-test.sh          # Sandbox прогон 9 фаз
shellcheck lib/*.sh scripts/*.sh        # Линтер
```

## Безопасность

- Секреты из `/dev/urandom` (32 символа, буквенно-цифровые)
- `.env` и `credentials.txt` с правами 600, `umask 077`
- Белый список ключей при чтении `credentials.txt`
- Защита от sed-инъекций (`_sed_escape`)
- `sudo rm -rf` защищён проверкой пути + маркером `.install-state`
- Таймауты curl (5с подключение, 10с макс.) на всех запросах
- JSON через `python3 json.dumps`, не конкатенация строк

## Отличия macOS от Linux

| Linux | macOS (AGMind) |
|-------|----------------|
| `apt-get` | `brew` |
| `systemctl` / cron | LaunchAgents |
| `/proc/meminfo` | `sysctl hw.memsize` |
| `ss -tlnp` | `lsof -iTCP` |
| GNU sed | BSD `sed -i ''` |
| `timeout` | циклы со счётчиком |
| Docker GPU passthrough | Нативный Ollama (Metal) |
| bash 5+ | bash 3.2.57 (штатный) |

## Лицензия

[Apache 2.0](LICENSE)
