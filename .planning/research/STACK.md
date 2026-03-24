# Stack Research

**Domain:** macOS Bash Installer for Docker-based AI/RAG Stack
**Researched:** 2026-03-24
**Confidence:** HIGH (verified on live macOS 26.3 / Apple M4 Pro system)
**Update scope:** v1.1 -- Open Notebook + DB-GPT additions only

---

## Existing Stack (v1.0, DO NOT change)

| Technology | Version | Purpose |
|------------|---------|---------|
| Bash 3.2.57 | macOS built-in | Installer scripting |
| Homebrew 5.x | latest | Package manager |
| Colima 0.10.x | latest | Docker runtime (primary) |
| Docker CLI + Compose | CLI 29.x / Compose 5.x | Container orchestration |
| Ollama | 0.17+ (native brew) | LLM inference, Metal GPU |
| BATS-core | 1.13.0 | Bash testing |
| Dify | 1.13.2 | RAG/workflow platform |
| Open WebUI | main | Chat interface |
| PostgreSQL | 15-alpine | Dify database |
| Redis | 6-alpine | Dify cache |
| Weaviate/Qdrant | 1.27.0 / v1.8.3 | Vector DB |
| Nginx | latest | Reverse proxy |

---

## New Stack for v1.1

### Open Notebook

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| lfnovo/open_notebook | v1-latest (pinned v1.8.1) | AI research notebook (NotebookLM alternative) | Official Docker image. `v1-latest` tag tracks latest v1.x stable. Current release v1.8.1 (2025-03-11). Supports Ollama natively via UI credential system. |
| surrealdb/surrealdb | v2 | Document database for Open Notebook | Required dependency -- Open Notebook stores all data in SurrealDB. No alternative supported. Lightweight, single-binary DB with embedded RocksDB storage. |

**Confidence:** HIGH -- docker-compose.yml verified from [official docs](https://github.com/lfnovo/open-notebook/blob/main/docs/1-INSTALLATION/docker-compose.md)

#### Docker Compose Service: surrealdb

```yaml
surrealdb:
  image: surrealdb/surrealdb:v2
  command: start --log info --user root --pass root rocksdb:/mydata/mydatabase.db
  user: root
  ports:
    - "${SURREALDB_PORT:-8000}:8000"
  volumes:
    - surreal_data:/mydata
  environment:
    - SURREAL_EXPERIMENTAL_GRAPHQL=true
  restart: unless-stopped
  profiles:
    - open-notebook
  networks:
    - agmind
```

#### Docker Compose Service: open_notebook

```yaml
open_notebook:
  image: lfnovo/open_notebook:${OPEN_NOTEBOOK_VERSION:-v1-latest}
  ports:
    - "${OPEN_NOTEBOOK_WEB_PORT:-8502}:8502"
    - "${OPEN_NOTEBOOK_API_PORT:-5055}:5055"
  environment:
    - OPEN_NOTEBOOK_ENCRYPTION_KEY=${OPEN_NOTEBOOK_ENCRYPTION_KEY}
    - SURREAL_URL=ws://surrealdb:8000/rpc
    - SURREAL_USER=${SURREAL_USER:-root}
    - SURREAL_PASSWORD=${SURREAL_PASSWORD:-root}
    - SURREAL_NAMESPACE=open_notebook
    - SURREAL_DATABASE=open_notebook
    - OLLAMA_BASE_URL=http://host.docker.internal:11434
  extra_hosts:
    - "host.docker.internal:host-gateway"
  volumes:
    - notebook_data:/app/data
  depends_on:
    - surrealdb
  restart: unless-stopped
  profiles:
    - open-notebook
  networks:
    - agmind
```

#### Environment Variables

| Variable | Default | Required | Purpose |
|----------|---------|----------|---------|
| `OPEN_NOTEBOOK_ENCRYPTION_KEY` | (generated) | YES | Encrypts stored API credentials. Min 16 chars. Installer MUST generate a random value. |
| `SURREAL_URL` | `ws://surrealdb:8000/rpc` | NO | SurrealDB connection. Hardcoded in compose, do not expose. |
| `SURREAL_USER` | `root` | NO | SurrealDB auth. |
| `SURREAL_PASSWORD` | `root` | YES (change) | SurrealDB password. Installer should generate random value. |
| `SURREAL_NAMESPACE` | `open_notebook` | NO | SurrealDB namespace. Keep default. |
| `SURREAL_DATABASE` | `open_notebook` | NO | SurrealDB database. Keep default. |
| `OLLAMA_BASE_URL` | `http://host.docker.internal:11434` | NO | Ollama API for model discovery. Set in compose, user configures models via UI. |
| `BASIC_AUTH_USERNAME` | (none) | NO | Optional HTTP basic auth. |
| `BASIC_AUTH_PASSWORD` | (none) | NO | Optional HTTP basic auth. |
| `CHUNK_SIZE` | `1500` | NO | Content chunking size. |
| `CHUNK_OVERLAP` | `150` | NO | Chunk overlap. |

#### Ports

| Port | Service | Protocol | Purpose |
|------|---------|----------|---------|
| 8502 | open_notebook | HTTP | Streamlit web UI |
| 5055 | open_notebook | HTTP | REST API |
| 8000 | surrealdb | WebSocket/HTTP | Database (internal only, can skip host mapping) |

#### Volumes

| Volume | Container Path | Purpose |
|--------|---------------|---------|
| `surreal_data` | `/mydata` | SurrealDB persistent storage (RocksDB) |
| `notebook_data` | `/app/data` | Open Notebook application data, uploaded files |

#### Ollama Integration Method

Open Notebook connects to Ollama via its **UI-based credential system**:
1. Set `OLLAMA_BASE_URL=http://host.docker.internal:11434` as env var (pre-configures default)
2. User opens Settings -> API Keys -> Add Credential -> selects "Ollama" provider
3. Base URL: `http://host.docker.internal:11434` (no API key needed)
4. Click "Discover Models" to auto-register available Ollama models
5. Select default LLM and embedding models in Settings -> Models

**No TOML or config files needed.** All configuration happens via UI after first launch.

---

### DB-GPT

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| eosphorosai/dbgpt-openai | latest (pinned v0.7.5) | Text-to-SQL, database RAG, AI data assistant | Lightweight proxy-only image (CPU, no GPU required). Uses SQLite internally by default -- no MySQL dependency needed. Connects to Ollama via `proxy/ollama` provider in TOML config. |

**Confidence:** MEDIUM -- Docker image verified on [Docker Hub](https://hub.docker.com/r/eosphorosai/dbgpt-openai), but Ollama integration via Docker has a [known networking issue](https://github.com/eosphoros-ai/DB-GPT/issues/2894) that requires `host.docker.internal` + `extra_hosts`. TOML config format verified from [official docs](http://docs.dbgpt.cn/docs/installation/advanced_usage/More_proxyllms/).

**IMPORTANT: Use `eosphorosai/dbgpt-openai` NOT `eosphorosai/dbgpt`.** The `dbgpt` image is 10+ GB and requires GPU. The `dbgpt-openai` image is lightweight, CPU-only, proxy-mode -- it delegates all inference to Ollama. Perfect for our use case.

#### TOML Config File: `dbgpt-proxy-ollama.toml`

The installer must generate this file and volume-mount it into the container:

```toml
[models]
[[models.llms]]
name = "${LLM_MODEL}"
provider = "proxy/ollama"
api_base = "http://host.docker.internal:11434"
api_key = ""

[[models.embeddings]]
name = "${EMBED_MODEL}"
provider = "proxy/ollama"
api_base = "http://host.docker.internal:11434"
api_key = ""
```

Where `${LLM_MODEL}` and `${EMBED_MODEL}` come from the wizard (existing AGMind env vars).

#### Docker Compose Service: dbgpt

```yaml
dbgpt:
  image: eosphorosai/dbgpt-openai:${DBGPT_VERSION:-latest}
  command: "dbgpt start webserver --config /app/configs/dbgpt-proxy-ollama.toml"
  ports:
    - "${DBGPT_PORT:-5670}:5670"
  extra_hosts:
    - "host.docker.internal:host-gateway"
  volumes:
    - dbgpt_data:/app/pilot/data
    - dbgpt_message:/app/pilot/message
    - ./configs/dbgpt-proxy-ollama.toml:/app/configs/dbgpt-proxy-ollama.toml:ro
  restart: unless-stopped
  profiles:
    - dbgpt
  networks:
    - agmind
```

#### Environment Variables

| Variable | Default | Required | Purpose |
|----------|---------|----------|---------|
| `DBGPT_VERSION` | `latest` | NO | Docker image tag. Pin to `v0.7.5` in versions.env. |
| `DBGPT_PORT` | `5670` | NO | Web UI port. |
| `LLM_MODEL` | (from wizard) | YES | Ollama model name for TOML config generation. Reuses existing AGMind variable. |
| `EMBED_MODEL` | (from wizard) | YES | Ollama embedding model for TOML config generation. Reuses existing AGMind variable. |

**Note:** DB-GPT does NOT need API keys for Ollama. The TOML config `api_key = ""` is correct.

#### Ports

| Port | Service | Protocol | Purpose |
|------|---------|----------|---------|
| 5670 | dbgpt | HTTP | Web UI + API |

#### Volumes

| Volume | Container Path | Purpose |
|--------|---------------|---------|
| `dbgpt_data` | `/app/pilot/data` | SQLite database, user data |
| `dbgpt_message` | `/app/pilot/message` | Chat message history |
| TOML config (bind mount) | `/app/configs/dbgpt-proxy-ollama.toml` | Ollama provider config (read-only) |

#### Ollama Integration Method

DB-GPT uses **TOML config files** for LLM provider configuration:
1. Installer generates `dbgpt-proxy-ollama.toml` from template using existing `LLM_MODEL` and `EMBED_MODEL` vars
2. TOML file is bind-mounted read-only into the container
3. Container starts with `--config /app/configs/dbgpt-proxy-ollama.toml`
4. DB-GPT connects to `http://host.docker.internal:11434` for both LLM and embeddings
5. **No MySQL needed** -- SQLite is the default internal database

**Known issue:** DB-GPT in Docker may fail to resolve `host.docker.internal` on some setups ([GitHub #2894](https://github.com/eosphoros-ai/DB-GPT/issues/2894)). Mitigation: always include `extra_hosts: ["host.docker.internal:host-gateway"]` and ensure Colima is configured with `host.docker.internal` support (already done in AGMind v1.0).

---

## Version Pinning (additions to versions.env)

```bash
# v1.1 Optional Tools
OPEN_NOTEBOOK_VERSION=v1-latest
SURREALDB_VERSION=v2
DBGPT_VERSION=latest
```

**Rationale for tag choices:**
- `v1-latest` for Open Notebook: tracks latest stable in v1.x line, avoids breaking v2.x changes
- `v2` for SurrealDB: Open Notebook requires SurrealDB v2 specifically (v1 API incompatible)
- `latest` for DB-GPT: project has infrequent releases (v0.7.5 is latest, Feb 2025), `latest` is acceptable; can pin to specific SHA if needed

---

## Nginx Routes (additions)

| Tool | Upstream | Suggested Route |
|------|----------|-----------------|
| Open Notebook | `http://open_notebook:8502` | `/notebook/` or subdomain `notebook.{HOST}` |
| Open Notebook API | `http://open_notebook:5055` | `/notebook-api/` |
| DB-GPT | `http://dbgpt:5670` | `/dbgpt/` or subdomain `dbgpt.{HOST}` |

**Note:** Both tools are Streamlit/React SPAs. Nginx proxy_pass with WebSocket upgrade headers required for Open Notebook (Streamlit uses WebSocket).

---

## Port Conflict Analysis

| Port | Service | Conflict Risk |
|------|---------|---------------|
| 8502 | Open Notebook Web | LOW -- unique port, not used by existing stack |
| 5055 | Open Notebook API | LOW -- unique port |
| 8000 | SurrealDB | MEDIUM -- Weaviate also uses 8000 by default. **If both enabled, remap SurrealDB to 8001 or skip host mapping** |
| 5670 | DB-GPT | LOW -- unique port |

**Critical:** SurrealDB port 8000 conflicts with Weaviate's default port 8000. Solution: do not expose SurrealDB to host -- it only needs container-to-container networking. Remove the `ports` mapping from surrealdb service if Weaviate is also enabled (which is the common case).

---

## Docker Compose Profiles Strategy

Use Compose profiles to make tools optional:

```yaml
# Activate with: docker compose --profile open-notebook --profile dbgpt up -d
profiles:
  - open-notebook   # surrealdb + open_notebook services
  - dbgpt           # dbgpt service
```

The installer's wizard sets `INSTALL_OPEN_NOTEBOOK=1` and `INSTALL_DBGPT=1`, which the compose module translates to `--profile` flags.

---

## Installation Commands (for installer scripts)

```bash
# No new brew packages needed -- all tools are Docker-only

# Generate encryption key for Open Notebook
OPEN_NOTEBOOK_ENCRYPTION_KEY=$(openssl rand -hex 32)

# Generate SurrealDB password
SURREAL_PASSWORD=$(openssl rand -hex 16)

# Generate DB-GPT TOML config
cat > /opt/agmind/configs/dbgpt-proxy-ollama.toml << TOML_EOF
[models]
[[models.llms]]
name = "${LLM_MODEL}"
provider = "proxy/ollama"
api_base = "http://host.docker.internal:11434"
api_key = ""

[[models.embeddings]]
name = "${EMBED_MODEL}"
provider = "proxy/ollama"
api_base = "http://host.docker.internal:11434"
api_key = ""
TOML_EOF
```

---

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Open Notebook DB | SurrealDB v2 | None | Only supported backend. No choice. |
| DB-GPT image | dbgpt-openai (proxy) | dbgpt (full) | Full image is 10+ GB, requires GPU. Proxy image is ~2 GB, CPU-only, delegates to Ollama. |
| DB-GPT database | SQLite (default) | MySQL | MySQL adds another container. SQLite works out of the box, zero config. Sufficient for single-user local deployment. |
| DB-GPT LLM | proxy/ollama | SiliconFlow API | We run local Ollama. No external API keys needed. |

---

## Sources

- [Open Notebook Docker Compose docs](https://github.com/lfnovo/open-notebook/blob/main/docs/1-INSTALLATION/docker-compose.md) -- HIGH confidence
- [Open Notebook .env.example](https://github.com/lfnovo/open-notebook/blob/main/.env.example) -- HIGH confidence
- [Open Notebook AI providers docs](https://github.com/lfnovo/open-notebook/blob/main/docs/5-CONFIGURATION/ai-providers.md) -- HIGH confidence
- [Open Notebook releases](https://github.com/lfnovo/open-notebook/releases) -- v1.8.1 latest (2025-03-11)
- [DB-GPT Docker Hub (dbgpt-openai)](https://hub.docker.com/r/eosphorosai/dbgpt-openai) -- HIGH confidence
- [DB-GPT docker-compose.yml](https://github.com/eosphoros-ai/DB-GPT/blob/main/docker-compose.yml) -- HIGH confidence
- [DB-GPT Ollama proxy config](http://docs.dbgpt.cn/docs/installation/advanced_usage/More_proxyllms/) -- MEDIUM confidence (docs site slow/intermittent)
- [DB-GPT releases](https://github.com/eosphoros-ai/DB-GPT/releases) -- v0.7.5 latest (2025-02-11)
- [DB-GPT Ollama networking issue](https://github.com/eosphoros-ai/DB-GPT/issues/2894) -- MEDIUM confidence (issue open, workaround known)
