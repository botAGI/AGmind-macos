# Architecture: Open Notebook + DB-GPT Integration

**Domain:** Integrating optional AI tools into existing macOS bash installer
**Researched:** 2026-03-24
**Confidence:** HIGH (existing codebase analyzed, upstream Docker configs verified)

## Integration Strategy

Both Open Notebook and DB-GPT integrate as **Docker Compose profile-gated services** -- the same pattern already used for weaviate/qdrant, etl-extended, and monitoring. No new architectural patterns needed. The existing wizard -> config.sh -> compose profiles pipeline handles everything.

### Key Principle: Minimal Blast Radius

Existing files need **modification**, not rewriting. New tools add:
- New services in docker-compose.yml (profile-gated)
- New wizard questions (questions 8 and 9)
- New WIZARD_* exports and COMPOSE_PROFILES entries
- New nginx upstream/location blocks
- New health check targets
- New CLI status/URL output lines

No changes to install.sh phase structure, no new lib/*.sh modules, no new phases.

## Existing Architecture (for reference)

```
install.sh orchestrator
  |
  +-- Phase 2: wizard.sh --> exports WIZARD_* vars
  +-- Phase 5: config.sh --> reads WIZARD_*, renders templates
  |     +-- _build_compose_profiles() --> COMPOSE_PROFILES string
  |     +-- _render_env_file()        --> .env from template
  |     +-- _render_nginx_conf()      --> nginx.conf from template
  |     +-- _render_compose_file()    --> docker-compose.yml from template
  +-- Phase 6: compose.sh --> docker compose up -d
  +-- Phase 7: health.sh  --> polls container health
  +-- Phase 9: install.sh --> prints summary URLs
```

## File Change Map

### MODIFIED FILES (existing)

| File | Changes | Complexity |
|------|---------|------------|
| `lib/wizard.sh` | Add `_wizard_ask_open_notebook()` (Q8) and `_wizard_ask_dbgpt()` (Q9), y/N prompts. Add to `run_wizard()` and `_wizard_non_interactive()`. Export `WIZARD_OPEN_NOTEBOOK`, `WIZARD_DBGPT`. | Low |
| `lib/config.sh` | Extend `_build_compose_profiles()` to append `open-notebook` and/or `dbgpt` profiles. Add `{{OPEN_NOTEBOOK_ENCRYPTION_KEY}}` and `{{DBGPT_SECRET_KEY}}` to `_render_env_file()`. Add new secrets to `_load_or_generate_secrets()` and `_write_credentials_file()`. Conditionally render `dbgpt-ollama.toml` config. | Medium |
| `templates/docker-compose.yml` | Add 3 new service blocks: `surrealdb`, `open-notebook`, `dbgpt`. All profile-gated. Add 3 new volumes. | Medium |
| `templates/nginx.conf.template` | Add 2 upstream blocks and 2 location blocks. Make optional blocks conditional or always-present (nginx handles upstream-down gracefully with error). | Low |
| `templates/env.lan.template` | Add Open Notebook and DB-GPT env var sections with placeholders. | Low |
| `templates/env.offline.template` | Same additions as env.lan.template. | Low |
| `templates/versions.env` | Add `SURREALDB_VERSION`, `OPEN_NOTEBOOK_VERSION`, `DBGPT_VERSION` pins. | Low |
| `lib/health.sh` | Extend `phase_7_health()` to conditionally check `open-notebook` and `dbgpt` services when their profiles are active. | Low |
| `scripts/agmind.sh` | Add Open Notebook and DB-GPT URLs to `cmd_status()` output (conditional on running). | Low |
| `install.sh` | Add Open Notebook and DB-GPT URLs to Phase 9 summary output (conditional). | Low |

### NEW FILES

| File | Purpose | Complexity |
|------|---------|------------|
| `templates/dbgpt-ollama.toml` | DB-GPT TOML config for Ollama provider with `proxy/ollama` and `host.docker.internal:11434` | Low |
| `tests/test_wizard_optional.bats` | BATS tests for new wizard questions 8-9 | Low |
| `tests/test_config_optional.bats` | BATS tests for profile building with optional tools, new secrets | Low |

### UNCHANGED FILES

All other files remain untouched: `lib/common.sh`, `lib/detect.sh`, `lib/docker.sh`, `lib/ollama.sh`, `lib/compose.sh` (it just calls `docker compose up -d`), `lib/models.sh`, `lib/openwebui.sh`, `lib/backup.sh`, `scripts/backup.sh`, `scripts/health-gen.sh`, `scripts/update.sh`, LaunchAgent templates.

## Component Details

### 1. Docker Compose Services

#### Open Notebook (profile: `open-notebook`)

Open Notebook requires two containers: SurrealDB (its database) and the app itself.

```yaml
# SurrealDB (Open Notebook's database -- profile-gated with open-notebook)
surrealdb:
  image: surrealdb/surrealdb:${SURREALDB_VERSION}
  restart: always
  profiles:
    - open-notebook
  command: start --user ${SURREAL_USER:-root} --pass ${SURREAL_PASSWORD} file:/mydata/database.db
  volumes:
    - surrealdb_data:/mydata
  healthcheck:
    test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
    interval: 10s
    timeout: 5s
    retries: 5
    start_period: 10s

# Open Notebook
open-notebook:
  image: lfnovo/open_notebook:${OPEN_NOTEBOOK_VERSION}
  restart: always
  profiles:
    - open-notebook
  environment:
    OPEN_NOTEBOOK_ENCRYPTION_KEY: ${OPEN_NOTEBOOK_ENCRYPTION_KEY}
    SURREAL_URL: ws://surrealdb:8000/rpc
    SURREAL_USER: root
    SURREAL_PASSWORD: ${SURREAL_PASSWORD}
    SURREAL_NAMESPACE: open_notebook
    SURREAL_DATABASE: open_notebook
    OLLAMA_BASE_URL: http://host.docker.internal:11434
  depends_on:
    surrealdb:
      condition: service_healthy
  volumes:
    - opennotebook_data:/app/data
  extra_hosts:
    - "host.docker.internal:host-gateway"
```

**Ports:** Open Notebook exposes 8502 (web UI) and 5055 (API) internally. Since v1.1.0, port 8502 proxies API requests internally via Next.js rewrites, so nginx only needs to proxy to port 8502.

**No external port exposure** -- nginx handles routing via `/notebook/` location.

#### DB-GPT (profile: `dbgpt`)

DB-GPT can run with SQLite (no MySQL needed), using a mounted TOML config for Ollama.

```yaml
# DB-GPT
dbgpt:
  image: eosphorosai/dbgpt:${DBGPT_VERSION}
  restart: always
  profiles:
    - dbgpt
  command: dbgpt start webserver --config /app/configs/dbgpt-ollama.toml
  volumes:
    - dbgpt_data:/app/pilot/data
    - dbgpt_message:/app/pilot/message
    - ./dbgpt-ollama.toml:/app/configs/dbgpt-ollama.toml:ro
  extra_hosts:
    - "host.docker.internal:host-gateway"
```

**Ports:** DB-GPT web UI on 5670 internally. nginx routes via `/dbgpt/`.

**SQLite mode** -- avoids adding a MySQL container. DB-GPT supports SQLite out of the box via TOML config `[service.web.database] type = "sqlite"`.

### 2. DB-GPT TOML Config Template

New file `templates/dbgpt-ollama.toml`:

```toml
[service.web]
host = "0.0.0.0"
port = 5670

[service.web.database]
type = "sqlite"
path = "pilot/meta_data/dbgpt.db"

[[models.llms]]
name = "{{WIZARD_LLM_MODEL}}"
provider = "proxy/ollama"
api_base = "http://host.docker.internal:11434"
api_key = ""

[[models.embeddings]]
name = "{{WIZARD_EMBED_MODEL}}"
provider = "proxy/ollama"
api_url = "http://host.docker.internal:11434"
api_key = ""
```

This template is rendered by config.sh with the same `_atomic_sed` pattern used for other templates. Copied to `/opt/agmind/dbgpt-ollama.toml` only when `WIZARD_DBGPT=yes`.

### 3. Nginx Location Blocks

```nginx
# Open Notebook (conditional -- only works when container is running)
upstream open-notebook-app {
    server open-notebook:8502;
}

location /notebook/ {
    proxy_pass http://open-notebook-app/;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}

# DB-GPT
upstream dbgpt-app {
    server dbgpt:5670;
}

location /dbgpt/ {
    proxy_pass http://dbgpt-app/;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

**Critical consideration:** Nginx fails to start if an upstream server DNS cannot be resolved. Since `open-notebook` and `dbgpt` services are profile-gated and may not be running, the upstream blocks will cause nginx startup failure.

**Solution options:**

1. **Dynamic nginx.conf rendering** (recommended) -- config.sh conditionally includes upstream/location blocks based on WIZARD_OPEN_NOTEBOOK and WIZARD_DBGPT. This matches the existing pattern where nginx.conf is rendered from a template.
2. **`resolver` directive with variable** -- use a variable in proxy_pass to defer DNS resolution. Works but adds complexity.
3. **Separate nginx include files** -- config.sh drops include files. Adds file management complexity.

**Recommended approach: Option 1** -- modify `_render_nginx_conf()` in config.sh to conditionally inject blocks. Use sed to append blocks after a marker comment in the template. The template gets a `# {{OPTIONAL_UPSTREAMS}}` marker before the server block and a `# {{OPTIONAL_LOCATIONS}}` marker inside the server block.

### 4. Wizard Integration

Two new yes/no questions added after existing question 7 (backup mode):

```
Question 8: Install Open Notebook? [y/N]
  Open Notebook -- AI research notebook (alternative to Google Notebook LM)
  Adds ~1GB Docker images (SurrealDB + Open Notebook)

Question 9: Install DB-GPT? [y/N]
  DB-GPT -- AI database assistant (Text-to-SQL, data analysis)
  Adds ~2GB Docker image
```

**Pattern:** Simple y/N prompts (not numbered menus). New function `_wizard_ask_yesno()` for reusability. Returns "yes" or "no".

**Non-interactive env vars:** `OPEN_NOTEBOOK=yes|no` (default: no), `DBGPT=yes|no` (default: no).

**Exports:** `WIZARD_OPEN_NOTEBOOK`, `WIZARD_DBGPT`.

### 5. Config.sh Changes

#### _build_compose_profiles()

Add after monitoring block:

```bash
if [ "${WIZARD_OPEN_NOTEBOOK}" = "yes" ]; then
    profiles="${profiles},open-notebook"
fi
if [ "${WIZARD_DBGPT}" = "yes" ]; then
    profiles="${profiles},dbgpt"
fi
```

#### _load_or_generate_secrets() / _write_credentials_file()

Two new secrets:
- `OPEN_NOTEBOOK_ENCRYPTION_KEY` (for Open Notebook data encryption)
- `SURREAL_PASSWORD` (for SurrealDB auth, replaces default "root")

No new secrets needed for DB-GPT (SQLite mode, no auth).

#### _render_env_file()

Add substitutions for new placeholders in env templates:
- `{{OPEN_NOTEBOOK_ENCRYPTION_KEY}}`
- `{{SURREAL_PASSWORD}}`

#### _render_nginx_conf() (modified)

Conditional injection of upstream/location blocks based on wizard choices.

#### _render_dbgpt_config() (new internal function)

Only called when `WIZARD_DBGPT=yes`. Renders `dbgpt-ollama.toml` from template, substituting `{{WIZARD_LLM_MODEL}}` and `{{WIZARD_EMBED_MODEL}}`.

### 6. Health.sh Changes

In `phase_7_health()`, extend the profile-conditional check:

```bash
case "$profiles" in
    *open-notebook*)
        healthcheck_services="$healthcheck_services surrealdb"
        # open-notebook checked via _wait_for_running (no healthcheck)
        ;;
esac
# dbgpt checked via _wait_for_running (no healthcheck)
```

### 7. CLI and Summary Changes

`scripts/agmind.sh` `cmd_status()` -- add conditional URL output:

```bash
# Check if open-notebook is running
if (cd "$AGMIND_DIR" && docker compose ps --status running open-notebook 2>/dev/null | grep -q running); then
    printf "  %-20s %s\n" "Open Notebook:" "http://${ip_addr}/notebook/"
fi
```

Same pattern for DB-GPT. Phase 9 summary gets the same conditional lines.

## Data Flow: New Tool Installation

```
User runs install.sh
  |
  v
Phase 2: Wizard
  Q1-Q7 (existing) -> WIZARD_* exports
  Q8: "Install Open Notebook? [y/N]" -> WIZARD_OPEN_NOTEBOOK=yes|no
  Q9: "Install DB-GPT? [y/N]"        -> WIZARD_DBGPT=yes|no
  |
  v
Phase 5: Configuration
  _build_compose_profiles() adds "open-notebook" and/or "dbgpt" to COMPOSE_PROFILES
  _load_or_generate_secrets() generates OPEN_NOTEBOOK_ENCRYPTION_KEY, SURREAL_PASSWORD
  _render_env_file() substitutes new placeholders in .env
  _render_nginx_conf() conditionally injects upstream/location blocks
  _render_dbgpt_config() renders dbgpt-ollama.toml (if DB-GPT selected)
  |
  v
Phase 6: docker compose up -d
  COMPOSE_PROFILES="postgresql,weaviate,open-notebook,dbgpt" activates services
  Docker pulls surrealdb, open-notebook, dbgpt images
  |
  v
Phase 7: Health
  Polls surrealdb healthcheck (if open-notebook profile active)
  Waits for open-notebook running state
  Waits for dbgpt running state
  |
  v
Phase 9: Summary
  Prints Open Notebook URL: http://<ip>/notebook/
  Prints DB-GPT URL: http://<ip>/dbgpt/
```

## Docker Compose Volume Additions

```yaml
volumes:
  # ... existing volumes ...
  surrealdb_data:     # SurrealDB persistent data
  opennotebook_data:  # Open Notebook app data
  dbgpt_data:         # DB-GPT SQLite + pilot data
  dbgpt_message:      # DB-GPT message storage
```

## Network Topology

All services share the default Docker Compose network. No custom networks needed.

```
                    ┌─────────────────────────┐
                    │     nginx (port 80)      │
                    │                         │
                    │  /          -> open-webui:8080
                    │  /apps/     -> web:3000
                    │  /api/      -> api:5001
                    │  /notebook/ -> open-notebook:8502 (optional)
                    │  /dbgpt/    -> dbgpt:5670 (optional)
                    └────────────┬────────────┘
                                 │
              ┌──────────────────┼──────────────────┐
              │                  │                  │
     ┌────────┴────────┐ ┌──────┴──────┐ ┌────────┴────────┐
     │  Core Services   │ │  Open       │ │  DB-GPT          │
     │  api, web,       │ │  Notebook   │ │  (SQLite mode)   │
     │  redis, pg,      │ │  + SurrealDB│ │                  │
     │  open-webui      │ │             │ │                  │
     └────────┬────────┘ └──────┬──────┘ └────────┬────────┘
              │                  │                  │
              └──────────────────┼──────────────────┘
                                 │
                    host.docker.internal:11434
                                 │
                    ┌────────────┴────────────┐
                    │    Ollama (native)       │
                    │    brew service          │
                    │    Metal GPU             │
                    └─────────────────────────┘
```

## Anti-Patterns to Avoid

### Anti-Pattern 1: MySQL Container for DB-GPT
**What:** Adding a MySQL service for DB-GPT's metadata store.
**Why bad:** Adds container overhead, port conflicts with PostgreSQL, secret management complexity. DB-GPT supports SQLite natively.
**Instead:** Use SQLite via TOML config `type = "sqlite"`.

### Anti-Pattern 2: Always-Present Nginx Upstreams
**What:** Including upstream blocks for optional services in nginx.conf regardless of selection.
**Why bad:** Nginx fails to start when upstream DNS cannot resolve (container not running). Unlike `proxy_pass` with variables, `upstream` blocks resolve at startup.
**Instead:** Conditionally inject blocks in `_render_nginx_conf()`.

### Anti-Pattern 3: New lib/*.sh Modules for Each Tool
**What:** Creating `lib/open-notebook.sh` and `lib/dbgpt.sh` modules.
**Why bad:** Adds source lines to install.sh, new phase functions, test file proliferation. These tools are simple Docker services with no host-side installation (unlike Ollama).
**Instead:** All logic lives in existing modules: wizard.sh (questions), config.sh (rendering), health.sh (checks).

### Anti-Pattern 4: Exposing Tool Ports Directly
**What:** Mapping `8502:8502` and `5670:5670` in docker-compose.yml.
**Why bad:** Bypasses nginx, multiple ports to remember, no consistent access pattern.
**Instead:** Route through nginx at `/notebook/` and `/dbgpt/`. Only nginx exposes port 80.

## Scalability Considerations

| Concern | 1 user | 5 users | Notes |
|---------|--------|---------|-------|
| Memory overhead | ~1-2GB extra | ~2-4GB extra | SurrealDB is lightweight; DB-GPT SQLite mode is light |
| Disk for images | ~3GB total | Same | One-time pull |
| Ollama contention | Minimal | Queue builds | All 3 tools (Open WebUI, Open Notebook, DB-GPT) hit same Ollama instance |

**Ollama contention note:** With 3 tools sharing one Ollama, concurrent requests will queue. This is acceptable for LAN/local use. No mitigation needed in v1.1.

## Path Sensitivity: Sub-Path Proxying

Both Open Notebook and DB-GPT are designed to run at root path (`/`). Proxying them under sub-paths (`/notebook/`, `/dbgpt/`) may cause issues with:
- Hardcoded asset paths in frontend JavaScript
- API calls using absolute paths
- WebSocket connection URLs

**Mitigation strategies (in priority order):**
1. Test sub-path proxying first -- many modern apps handle it via `proxy_set_header Host` and `X-Forwarded-Prefix`.
2. If sub-path fails: use separate ports (e.g., nginx listens on 8502 for Open Notebook, 5670 for DB-GPT) as virtual hosts.
3. If virtual hosts fail: use port-based routing with direct port exposure.

**Research flag:** Sub-path behavior needs validation during implementation. This is the highest-risk integration point.

## Version Pins

| Image | Recommended Pin | Notes |
|-------|----------------|-------|
| `surrealdb/surrealdb` | `v2` | Major version pin, stable |
| `lfnovo/open_notebook` | `v1-latest` | Tracks v1.x releases |
| `eosphorosai/dbgpt` | `latest` | No stable semver tags found; pin to specific SHA after testing |

**Confidence:** MEDIUM for DB-GPT version pin. Docker Hub tags are sparse; may need to use `latest` initially and pin after validation.

## Sources

- [Open Notebook Docker Compose docs](https://github.com/lfnovo/open-notebook/blob/main/docs/1-INSTALLATION/docker-compose.md)
- [Open Notebook .env.example](https://github.com/lfnovo/open-notebook/blob/main/.env.example)
- [Open Notebook v1.1.0 release (simplified reverse proxy)](https://github.com/lfnovo/open-notebook/releases/tag/v1.1.0)
- [DB-GPT docker-compose.yml](https://github.com/eosphoros-ai/DB-GPT/blob/main/docker-compose.yml)
- [DB-GPT Ollama integration docs](http://docs.dbgpt.cn/docs/next/installation/advanced_usage/ollama/)
- [DB-GPT Docker Hub](https://hub.docker.com/r/eosphorosai/dbgpt)
- [Open Notebook Docker Hub](https://hub.docker.com/r/lfnovo/open_notebook)
