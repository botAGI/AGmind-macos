#!/bin/bash
# scripts/health-gen.sh -- AGMind health report generator
# Invoked by LaunchAgent com.agmind.health (every 60 seconds)
# Compatible with /bin/bash 3.2.57 (stock macOS)
#
# Generates JSON health report at /opt/agmind/logs/health.json
# Checks: Docker containers, Ollama API, disk space

set -euo pipefail

# =============================================================================
# Constants
# =============================================================================

AGMIND_DIR="${AGMIND_DIR:-/opt/agmind}"
HEALTH_FILE="${AGMIND_DIR}/logs/health.json"
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# =============================================================================
# Ensure output directory exists
# =============================================================================

mkdir -p "${AGMIND_DIR}/logs"

# =============================================================================
# Check Docker containers
# =============================================================================

docker_ok="false"
docker_containers="[]"

if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    docker_ok="true"
    # Get container status as JSON-ish array
    docker_containers="["
    first=true
    while IFS='|' read -r name state health; do
        if [ "$first" = "true" ]; then
            first=false
        else
            docker_containers="${docker_containers},"
        fi
        # Clean up whitespace
        name=$(echo "$name" | tr -d ' ')
        state=$(echo "$state" | tr -d ' ')
        health=$(echo "$health" | tr -d ' ')
        if [ -z "$health" ]; then
            health="none"
        fi
        docker_containers="${docker_containers}{\"name\":\"${name}\",\"state\":\"${state}\",\"health\":\"${health}\"}"
    done < <(cd "$AGMIND_DIR" && docker compose ps --format '{{.Name}}|{{.State}}|{{.Health}}' 2>/dev/null || true)
    docker_containers="${docker_containers}]"
fi

# =============================================================================
# Check Ollama API
# =============================================================================

ollama_ok="false"
ollama_models=""

if curl -sf http://localhost:11434/api/tags >/dev/null 2>&1; then
    ollama_ok="true"
    ollama_models=$(curl -sf http://localhost:11434/api/tags 2>/dev/null | \
        python3 -c "import sys,json; d=json.load(sys.stdin); print(','.join(m['name'] for m in d.get('models',[])))" 2>/dev/null || echo "")
fi

# =============================================================================
# Check disk space
# =============================================================================

disk_free_gb=$(df -k / | awk 'NR==2 {printf "%.0f", $4/1048576}')
disk_warning="false"
if [ "$disk_free_gb" -lt 10 ]; then
    disk_warning="true"
fi

# =============================================================================
# Write health report
# =============================================================================

cat > "$HEALTH_FILE" <<EOF
{
  "timestamp": "${TIMESTAMP}",
  "overall": "$([ "$docker_ok" = "true" ] && [ "$ollama_ok" = "true" ] && [ "$disk_warning" = "false" ] && echo "healthy" || echo "degraded")",
  "docker": {
    "available": ${docker_ok},
    "containers": ${docker_containers}
  },
  "ollama": {
    "available": ${ollama_ok},
    "models": "${ollama_models}"
  },
  "disk": {
    "free_gb": ${disk_free_gb},
    "warning": ${disk_warning}
  }
}
EOF
