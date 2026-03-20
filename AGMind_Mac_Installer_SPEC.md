# AGMind macOS Installer — First Spec v0.1

> Референс: Linux installer v3.0 (difyowebinstaller).
> Цель: нативный установщик AGMind RAG-стека для macOS (Apple Silicon + Intel).
> Основной use-case: Mac Studio / Mac Pro как локальный AI-сервер.

---

## 1. Контекст и цели

### Зачем отдельный инсталлер под macOS?

Linux-инсталлер использует `apt-get`, `systemctl`, `ufw`, `fail2ban`, `/etc/cron.d` — на macOS этого нет. Попытка запустить его на macOS даёт баги (DEPLOY_PROFILE unbound, socket not found и т.д.).

Mac Studio / Mac Pro на M4 Ultra — реальная продакшн-машина для локального RAG:
- 192 GB unified memory (M4 Ultra) — достаточно для 70B моделей
- Apple Silicon: Metal GPU нативно, но Docker не имеет доступа к Metal
- Мощная машина, 24/7 uptime, тихая

### Что разворачивается

Тот же AI-стек что и на Linux:
- **Dify** (API + Worker + Web + Plugin Daemon)
- **Open WebUI** (чат-интерфейс)
- **Ollama** (LLM инференс, единственный провайдер на macOS)
- **Weaviate** или **Qdrant** (векторная БД)
- **PostgreSQL** + **Redis** (база + кэш)
- **Nginx** (реверс-прокси)
- **Squid** (SSRF-защита)
- Опционально: Grafana + Portainer + Prometheus (мониторинг)

### Что НЕ входит в v1

- vLLM — нет CUDA на macOS
- TEI — нет CUDA на macOS
- Authelia — излишне для локального использования
- UFW / fail2ban — не применимо на macOS
- Certbot / Let's Encrypt — Mac Studio не на публичном IP (только LAN-профиль)
- Tunnel (reverse SSH) — не в v1
- Dify API automation — как в Linux-версии, вне scope

---

## 2. Профили развёртывания

Только два профиля (vs 4 на Linux):

| Профиль | Доступ | TLS | Use-case |
|---------|--------|-----|----------|
| **lan** | Локальная сеть | none / self-signed | Mac Studio в офисе |
| **offline** | Изолированная сеть | none | Air-gapped, без интернета |

VPS и VPN профили — не в v1 (macOS не для серверов).

---

## 3. macOS-специфика vs Linux

### 3.1 Пакетный менеджер → Homebrew

```
Linux:  apt-get / yum / dnf
macOS:  brew install ...
```

Homebrew обязателен. Установка `brew` если не найден — в preflight.

### 3.2 Сервисы → launchd

```
Linux:  systemctl enable --now service
macOS:  launchctl load ~/Library/LaunchAgents/com.agmind.*.plist
```

Каждый фоновый сервис (health-gen, backup cron, update check) — LaunchAgent plist.

### 3.3 Docker

На macOS нет Docker CE daemon. Два варианта:

| Вариант | Плюсы | Минусы |
|---------|-------|--------|
| **Docker Desktop** | GUI, привычный | Платный для компаний, тяжёлый |
| **Colima** | Бесплатный, легче, нативный ARM64 | CLI-only |

**Решение:** поддержать оба. Detect → автоинсталл Colima если нет Docker.

Socket:
```
Docker Desktop: ~/.docker/run/docker.sock
Colima:         ~/.colima/default/docker.sock
```

### 3.4 Память

```
Linux:  /proc/meminfo
macOS:  sysctl hw.memsize / vm.stat
```

Unified Memory на Apple Silicon — не надо разделять CPU/GPU память при расчёте доступности моделей.

### 3.5 Порты

```
Linux:  ss -tlnp
macOS:  lsof -iTCP -sTCP:LISTEN
```

### 3.6 Пути установки

```
Linux:  /opt/agmind/                    (требует sudo)
macOS:  /opt/agmind/                    (sudo, как и на Linux)
        альтернатива: ~/Library/Application Support/AGMind/
```

**Решение:** использовать `/opt/agmind/` для совместимости с Linux-скриптами. `sudo` на macOS нормально.

### 3.7 Cron → launchd

```
Linux:  /etc/cron.d/agmind-health  (1-min health check)
        crontab -l (backup)
macOS:  ~/Library/LaunchAgents/com.agmind.health.plist
        ~/Library/LaunchAgents/com.agmind.backup.plist
```

### 3.8 GNU coreutils

macOS uses BSD sed, BSD awk, нет `timeout`. Нужно:

```bash
brew install coreutils gnu-sed
```

Или писать без GNU-зависимостей (предпочтительно).

### 3.9 Ollama

На macOS Ollama запускается **нативно** (не в Docker) и использует Metal GPU. Два варианта:

**Вариант A: Нативный Ollama** (рекомендуется)
- `brew install ollama` → `brew services start ollama`
- Слушает на `localhost:11434`
- Работает с Metal (быстро, правильно)
- Docker не нужен для LLM

**Вариант B: Ollama в Docker**
- Как на Linux, но без GPU passthrough
- Медленнее (нет Metal)

**Решение v1:** Вариант A. Нативный Ollama для macOS — главное преимущество перед Linux DinD.

Тогда Dify/Open WebUI коннектятся к `http://host.docker.internal:11434` (Docker изнутри контейнера обращается к хосту).

### 3.10 Apple Silicon — модели

Ollama на M-series поддерживает все те же модели через Metal. Рекомендации:

| Unified Memory | Рекомендуемая модель |
|---------------|----------------------|
| 8 GB          | gemma3:4b, qwen2.5:3b |
| 16 GB         | qwen2.5:7b, llama3.1:8b |
| 32 GB         | qwen2.5:14b, phi-4:14b |
| 64 GB         | qwen2.5:32b, gemma3:27b |
| 96 GB+        | qwen2.5:72b, llama3.1:70b |
| 192 GB        | любая |

---

## 4. Архитектура инсталлера

### 4.1 Структура файлов

```
agmind-mac/
├── install.sh              # Оркестратор (9 фаз)
├── lib/
│   ├── common.sh           # Логирование, утилиты, валидация
│   ├── detect.sh           # macOS-диагностика
│   ├── wizard.sh           # Интерактивный конфиг
│   ├── docker.sh           # Colima / Docker Desktop setup
│   ├── ollama.sh           # Нативный Ollama (новое!)
│   ├── config.sh           # Генерация .env, nginx.conf и т.д.
│   ├── compose.sh          # docker compose up/down
│   ├── health.sh           # Healthchecks
│   ├── models.sh           # Pull моделей через Ollama API
│   ├── backup.sh           # Backup + launchd plist
│   └── openwebui.sh        # Open WebUI admin init
├── templates/
│   ├── docker-compose.yml  # Адаптированный: без ollama-контейнера
│   ├── env.lan.template
│   ├── env.offline.template
│   ├── nginx.conf.template
│   ├── versions.env
│   └── launchd/            # (новое!)
│       ├── com.agmind.health.plist.template
│       └── com.agmind.backup.plist.template
├── scripts/
│   ├── agmind.sh           # CLI (agmind status/doctor/backup/...)
│   ├── backup.sh
│   ├── health-gen.sh
│   └── update.sh
└── tests/
    ├── test_detect.bats
    ├── test_wizard.bats
    ├── test_config.bats
    ├── test_docker.bats
    ├── test_ollama.bats     # (новое!)
    └── ...
```

### 4.2 Фазы установки (9)

| # | Название | Описание | Отличие от Linux |
|---|----------|----------|-----------------|
| 1 | Diagnostics | OS, CPU, RAM, диск, Docker, порты | macOS-специфичные проверки |
| 2 | Wizard | Выбор профиля, модели, мониторинга | Упрощён (нет VPS, Authelia, UFW) |
| 3 | Prerequisites | Homebrew, Docker/Colima, GNU tools | **Новое**: нет apt-get |
| 4 | Ollama Setup | `brew install ollama`, `brew services start` | **Новое**: нативный Ollama |
| 5 | Configuration | Генерация .env, nginx.conf, docker-compose | Адаптированы пути и шаблоны |
| 6 | Start | `docker compose up` (без ollama-контейнера) | compose профили без ollama |
| 7 | Health | Healthchecks всех контейнеров | Проверка Ollama на :11434 |
| 8 | Models | `ollama pull` через `brew services` Ollama | `ollama` прямо на хосте |
| 9 | Complete | Admin init, credentials, CLI, LaunchAgents | `launchctl` вместо cron |

---

## 5. Модули — контракты

### 5.1 `lib/detect.sh`

**Обязанности:**
- `detect_os()` → `DETECTED_OS=macos`, `DETECTED_OS_VERSION`, `DETECTED_ARCH`
- `detect_ram()` → `sysctl hw.memsize` / `vm_stat`
- `detect_gpu()` → Apple Silicon Metal, Intel integrated
- `detect_disk()` → `df -k /`
- `detect_ports()` → `lsof -iTCP -sTCP:LISTEN` (порты 80, 443, 3000, 11434)
- `detect_docker()` → Docker Desktop (`.docker/run/docker.sock`) или Colima (`.colima/default/docker.sock`)
- `detect_ollama()` → нативный Ollama уже запущен?
- `detect_homebrew()` → brew установлен?
- `preflight_checks()` → RAM ≥ 8GB, диск ≥ 30GB, CPU ≥ 4 (arm64 или x86_64)

**ENV overrides:** `SKIP_PREFLIGHT`, `FORCE_GPU_TYPE`

---

### 5.2 `lib/wizard.sh`

**Обязанности:** Те же что в Linux, но упрощённый набор вопросов:

1. **Профиль:** lan | offline (только два)
2. **Модель LLM:** Меню с рекомендацией по RAM (список адаптирован под Ollama/Metal)
3. **Модель эмбеддингов:** Ollama (nomic-embed-text | bge-m3 | mxbai-embed-large)
4. **Векторная БД:** Weaviate | Qdrant
5. **ETL:** Стандартный | Расширенный (Docling)
6. **Мониторинг:** none | local (Grafana + Portainer)
7. **Бэкапы:** local | remote; расписание

**Убрать из wizard:**
- VPS / VPN профили
- Authelia 2FA
- UFW / fail2ban
- HF Token (нет TEI/vLLM)
- TLS (в v1 только none; self-signed в v2)
- Tunnel

**Экспортируемые переменные:** те же что в Linux, но урезанный набор.

---

### 5.3 `lib/docker.sh` (macOS-специфик)

**Обязанности:**
- `detect_docker_runtime()` → Docker Desktop или Colima
- `install_colima()` → `brew install colima docker` если нет Docker
- `start_colima()` → `colima start --arch aarch64 --cpu 8 --memory 16` с дефолтными параметрами
- `fix_docker_socket()` → создать симлинк `/var/run/docker.sock → ~/.colima/default/docker.sock`
- `verify_compose()` → `docker compose version`

**НЕ делает:**
- Не устанавливает docker-ce (нет на macOS)
- Не вызывает systemctl
- Не фиксит DNS (у macOS свой DNS resolver)

**ENV overrides:** `DOCKER_RUNTIME=colima|desktop`, `COLIMA_CPU`, `COLIMA_MEMORY`, `COLIMA_DISK`

---

### 5.4 `lib/ollama.sh` ← НОВЫЙ МОДУЛЬ

**Обязанности:**
- `install_ollama()` → `brew install ollama`
- `start_ollama()` → `brew services start ollama`
- `wait_for_ollama()` → poll `localhost:11434/api/tags` (timeout 60s)
- `configure_ollama_models()` → запись `OLLAMA_API_BASE=http://host.docker.internal:11434` в .env

**Не в Docker.** Ollama работает нативно на хосте. Docker-контейнеры (Dify, Open WebUI) обращаются к нему через `host.docker.internal`.

---

### 5.5 `lib/config.sh`

**Отличия от Linux:**
- Шаблоны: только `env.lan.template` и `env.offline.template`
- `OLLAMA_API_BASE=http://host.docker.internal:11434` (не `http://ollama:11434`)
- Нет шаблона для authelia
- Пути `/opt/agmind/` те же
- `generate_random()` → `/dev/urandom` (работает на macOS)
- `_atomic_sed()` → использовать `sed -i ''` (BSD sed) или `gsed -i` (GNU sed через brew)

**Важно:** BSD sed требует пустой аргумент после `-i`: `sed -i '' 's/a/b/' file`.
Выбрать один подход и придерживаться.

---

### 5.6 `lib/compose.sh`

**Отличия от Linux:**
- Профили compose: убрать `ollama` (он вне Docker)
- `OLLAMA_API_BASE` указывает на хост, не контейнер
- Нет `configure_docker_dns()` (не нужно на macOS)
- `docker compose up` — то же самое

**compose profiles (macOS):**
```
core + weaviate|qdrant + monitoring(опц.) + etl(опц.)
# без: ollama, vllm, tei, authelia, certbot
```

---

### 5.7 `lib/backup.sh`

**Отличия от Linux:**
- Нет `/var/backups/` → использовать `~/Library/Application Support/AGMind/backups/`
- Нет `crontab` системный → LaunchAgent plist
- `launchctl load ~/Library/LaunchAgents/com.agmind.backup.plist`

**LaunchAgent template:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC ...>
<plist version="1.0">
<dict>
    <key>Label</key>         <string>com.agmind.backup</string>
    <key>ProgramArguments</key>
    <array>
        <string>/opt/agmind/scripts/backup.sh</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>   <integer>3</integer>
        <key>Minute</key> <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>  <string>/opt/agmind/logs/backup.log</string>
    <key>StandardErrorPath</key> <string>/opt/agmind/logs/backup.log</string>
</dict>
</plist>
```

---

### 5.8 `scripts/agmind.sh` (CLI)

**Те же команды что на Linux:**
`status`, `doctor`, `logs`, `backup`, `restore`, `update`, `stop`, `start`, `restart`, `uninstall`

**macOS-адаптации:**
- `doctor`: проверяет `brew services list | grep ollama`, Colima/Docker Desktop статус
- `status`: IP через `ipconfig getifaddr en0`
- `logs`: работает через `docker logs` (то же)
- `stop`: `docker compose down` + `brew services stop ollama`
- `start`: `brew services start ollama` + `docker compose up -d`

---

## 6. docker-compose.yml (macOS)

### Ключевые отличия от Linux-версии

```yaml
# УБРАТЬ:
# - service ollama (нативный)
# - service vllm
# - service tei
# - service authelia
# - profile certbot

# ИЗМЕНИТЬ:
services:
  api:
    environment:
      OLLAMA_API_BASE: http://host.docker.internal:11434  # ← хост, не контейнер

  open-webui:
    environment:
      OLLAMA_BASE_URL: http://host.docker.internal:11434  # ← хост
    extra_hosts:
      - "host.docker.internal:host-gateway"               # ← macOS/Colima
```

`host.docker.internal` резолвится по-разному:
- Docker Desktop: автоматически
- Colima: нужен `extra_hosts: - "host.docker.internal:host-gateway"`

---

## 7. ENV шаблоны (macOS)

### `env.lan.template`

```env
# === Ключевые macOS-отличия ===
OLLAMA_API_BASE=http://host.docker.internal:11434
OLLAMA_HOST=http://host.docker.internal:11434

# Нет: ENABLE_UFW, ENABLE_FAIL2BAN, ENABLE_AUTHELIA
# Нет: TLS (v1)
# Нет: TUNNEL_*
```

Всё остальное идентично Linux LAN-шаблону.

---

## 8. Требования к системе

| Параметр | Минимум | Рекомендация |
|----------|---------|--------------|
| macOS | 13 Ventura | 14 Sonoma+ |
| Arch | Intel x86_64 | Apple Silicon (M1+) |
| RAM | 8 GB | 32 GB+ (64 GB для 32B моделей) |
| Disk | 30 GB | 100 GB+ SSD |
| Docker | Desktop 4.x или Colima 0.6+ | — |
| Homebrew | Любой | — |
| Internet | Для LAN-профиля | Нет для offline |

---

## 9. Preflight checklist

```
[PASS/WARN/FAIL] macOS 13+
[PASS/WARN/FAIL] Apple Silicon или Intel x86_64
[PASS/WARN/FAIL] Homebrew установлен
[PASS/WARN/FAIL] Docker (Desktop или Colima)
[PASS/WARN/FAIL] Docker socket доступен
[PASS/WARN/FAIL] docker compose v2
[PASS/WARN/FAIL] RAM ≥ 8 GB
[PASS/WARN/FAIL] Disk ≥ 30 GB
[PASS/WARN/FAIL] Port 80 свободен
[PASS/WARN/FAIL] Port 3000 свободен
[PASS/WARN/FAIL] Port 11434 (Ollama — ОК если уже запущен)
[PASS/WARN/FAIL] Internet (для LAN)
```

---

## 10. Быстрый старт (целевой UX)

```bash
git clone https://github.com/botAGI/agmind-mac.git
cd agmind-mac
bash install.sh
```

Non-interactive:
```bash
sudo DEPLOY_PROFILE=lan LLM_MODEL=qwen2.5:14b \
     EMBED_PROVIDER=ollama MONITORING_MODE=none \
     bash install.sh --non-interactive
```

После установки:
```
Open WebUI:   http://localhost/
Dify Console: http://localhost:3000/
Credentials:  /opt/agmind/credentials.txt

agmind status   # статус всех сервисов
agmind doctor   # диагностика
agmind stop     # остановить стек
agmind start    # запустить стек
```

---

## 11. Что берём из Linux-инсталлера AS-IS

| Модуль | Степень переиспользования |
|--------|--------------------------|
| `lib/common.sh` | ~95% — только BSD sed fix |
| `lib/wizard.sh` | ~70% — убрать VPS/Authelia/UFW секции |
| `lib/config.sh` | ~80% — адаптировать шаблоны и sed |
| `lib/compose.sh` | ~85% — убрать ollama профиль |
| `lib/health.sh` | ~90% — добавить Ollama healthcheck |
| `lib/models.sh` | ~80% — ollama pull через localhost |
| `lib/openwebui.sh` | ~95% — то же |
| `lib/backup.sh` | ~50% — launchd вместо cron |
| `lib/docker.sh` | ~20% — полностью переписать под macOS |
| `lib/ollama.sh` | 0% — новый модуль |
| `lib/security.sh` | 0% — не нужен в v1 |
| `lib/authelia.sh` | 0% — не нужен в v1 |
| `lib/tunnel.sh` | 0% — не нужен в v1 |
| `templates/docker-compose.yml` | ~75% — убрать ollama/vllm/tei/authelia |
| `scripts/agmind.sh` | ~80% — macOS-адаптации |

---

## 12. Риски и открытые вопросы

| # | Вопрос | Статус |
|---|--------|--------|
| 1 | BSD sed vs GNU sed — выбрать один подход | Решить в impl |
| 2 | Colima CPU/Memory лимиты — какие дефолты? | 8 CPU / 12 GB |
| 3 | `host.docker.internal` в Colima — работает ли без extra_hosts? | Проверить |
| 4 | `/opt/agmind` требует sudo — приемлемо? | Да, как на Linux |
| 5 | Ollama уже запущен нативно — конфликт? | Detect + переиспользовать |
| 6 | `timeout` GNU не на macOS — нужен `gtimeout` или убрать | Убрать/заменить |
| 7 | LaunchAgent vs user crontab — что проще? | LaunchAgent |
| 8 | Intel Mac поддержка — нужна? | Да, но вторичная |
| 9 | Docker Desktop платный для компаний — push Colima? | Рекомендовать Colima |

---

## 13. Out of scope (v1)

- VPS / публичный доступ
- TLS / HTTPS (кроме none)
- Authelia 2FA
- UFW / fail2ban
- vLLM / TEI (нет CUDA)
- Reverse SSH tunnel
- SOPS encryption
- Dify API automation
- Мультиузловая установка
- GUI-инсталлер (только CLI)
