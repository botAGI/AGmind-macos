#!/bin/bash
# tests/integration-test.sh -- Run full installer in sandboxed tmpdir (no sudo needed)
# Replaces sudo with no-op, Docker/Ollama/brew with mocks, paths with tmpdir
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TESTDIR=$(mktemp -d)
trap 'rm -rf "$TESTDIR"' EXIT

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Integration Test — Full 9-Phase Install + Optional Tools"
echo " Sandbox: ${TESTDIR}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Create mock bin directory with all needed mocks
MOCK_BIN="${TESTDIR}/mockbin"
mkdir -p "$MOCK_BIN"

# sudo mock — run command without sudo, skip /var/run writes
cat > "${MOCK_BIN}/sudo" << 'MOCK'
#!/bin/bash
# sudo mock: skip writes to protected paths, execute everything else
case "$*" in
    *"/var/run/"*) echo "mock: sudo $*" ;;
    *) "$@" ;;
esac
MOCK
chmod +x "${MOCK_BIN}/sudo"

# brew mock
cat > "${MOCK_BIN}/brew" << 'MOCK'
#!/bin/bash
case "$1" in
    --prefix) echo "/opt/homebrew" ;;
    install) echo "mock: brew install $*" ;;
    services)
        case "$2" in
            start|restart) echo "mock: brew services $2 $3" ;;
            stop) echo "mock: brew services stop $3" ;;
            list) echo "ollama started gbot ~/Library/LaunchAgents/homebrew.mxcl.ollama.plist" ;;
        esac
        ;;
    info)
        if [ "${3:-}" = "--json" ]; then
            echo '[{"installed":[{"version":"0.17.0"}]}]'
        fi
        ;;
    *) echo "mock: brew $*" ;;
esac
MOCK
chmod +x "${MOCK_BIN}/brew"

# ln mock — wrap real ln but skip /var/run writes
cat > "${MOCK_BIN}/ln" << MOCK
#!/bin/bash
case "\$*" in
    *"/var/run/"*) echo "mock: ln \$*" ;;
    *) /bin/ln "\$@" ;;
esac
MOCK
chmod +x "${MOCK_BIN}/ln"

# docker mock
cat > "${MOCK_BIN}/docker" << 'MOCK'
#!/bin/bash
case "$1" in
    info) echo "Server Version: 29.0.0" ;;
    compose)
        shift
        case "$1" in
            version) echo "Docker Compose version v2.30.0" ;;
            up) echo "mock: docker compose up $*" ;;
            down) echo "mock: docker compose down $*" ;;
            ps)
                if [ "${2:-}" = "-q" ]; then
                    echo "abc123mock"
                elif [ "${2:-}" = "--services" ]; then
                    echo "api"
                    echo "worker"
                    echo "web"
                    echo "db_postgres"
                    echo "redis"
                    echo "weaviate"
                    echo "nginx"
                    echo "open-webui"
                    echo "sandbox"
                    echo "plugin_daemon"
                else
                    echo ""
                fi
                ;;
            logs) echo "mock: docker compose logs $*" ;;
            *) echo "mock: docker compose $*" ;;
        esac
        ;;
    inspect)
        # Support --format for health and state checks
        case "$*" in
            *Health.Status*) echo "healthy" ;;
            *State.Status*)  echo "running" ;;
            *)               echo "healthy" ;;
        esac
        ;;
    logs) echo "mock: docker logs $*" ;;
    *) echo "mock: docker $*" ;;
esac
MOCK
chmod +x "${MOCK_BIN}/docker"

# ollama mock
cat > "${MOCK_BIN}/ollama" << 'MOCK'
#!/bin/bash
case "$1" in
    --version) echo "ollama version is 0.17.0" ;;
    pull) echo "mock: ollama pull $2 ... success" ;;
    list) echo "NAME                    SIZE" ;;
    *) echo "mock: ollama $*" ;;
esac
MOCK
chmod +x "${MOCK_BIN}/ollama"

# curl mock
cat > "${MOCK_BIN}/curl" << 'MOCK'
#!/bin/bash
for arg in "$@"; do
    case "$arg" in
        */api/v1/auths/signup*)
            echo '{"id":"mock-admin","email":"admin@agmind.local"}'
            exit 0 ;;
        http://localhost/)
            echo '<html>Open WebUI</html>'
            exit 0 ;;
        *11434*)
            echo '{"models":[]}'
            exit 0 ;;
    esac
done
echo "mock-curl-ok"
MOCK
chmod +x "${MOCK_BIN}/curl"

# sw_vers mock
cat > "${MOCK_BIN}/sw_vers" << 'MOCK'
#!/bin/bash
case "$1" in
    -productVersion) echo "15.4" ;;
    *) echo "15.4" ;;
esac
MOCK
chmod +x "${MOCK_BIN}/sw_vers"

# sysctl mock (24GB RAM)
cat > "${MOCK_BIN}/sysctl" << 'MOCK'
#!/bin/bash
echo "34359738368"
MOCK
chmod +x "${MOCK_BIN}/sysctl"

# lsof mock — all ports free
cat > "${MOCK_BIN}/lsof" << 'MOCK'
#!/bin/bash
exit 1
MOCK
chmod +x "${MOCK_BIN}/lsof"

# uname mock
cat > "${MOCK_BIN}/uname" << 'MOCK'
#!/bin/bash
case "$1" in
    -m) echo "arm64" ;;
    *) /usr/bin/uname "$@" ;;
esac
MOCK
chmod +x "${MOCK_BIN}/uname"

# ipconfig mock
cat > "${MOCK_BIN}/ipconfig" << 'MOCK'
#!/bin/bash
echo "192.168.1.100"
MOCK
chmod +x "${MOCK_BIN}/ipconfig"

# launchctl mock
cat > "${MOCK_BIN}/launchctl" << 'MOCK'
#!/bin/bash
case "$1" in
    bootstrap) echo "mock: launchctl bootstrap $*" ;;
    load) echo "mock: launchctl load $*" ;;
    list) exit 0 ;;
    *) echo "mock: launchctl $*" ;;
esac
MOCK
chmod +x "${MOCK_BIN}/launchctl"

# plutil mock
cat > "${MOCK_BIN}/plutil" << 'MOCK'
#!/bin/bash
echo "$2: OK"
exit 0
MOCK
chmod +x "${MOCK_BIN}/plutil"

# python3 — use real python3 (needed for JSON ops)
ln -sf "$(which python3)" "${MOCK_BIN}/python3"

# df mock
cat > "${MOCK_BIN}/df" << 'MOCK'
#!/bin/bash
echo "Filesystem 1024-blocks      Used Available Capacity  Mounted on"
echo "/dev/disk1  976000000 604000000 372000000    62%    /"
MOCK
chmod +x "${MOCK_BIN}/df"

# id mock
cat > "${MOCK_BIN}/id" << 'MOCK'
#!/bin/bash
echo "501"
MOCK
chmod +x "${MOCK_BIN}/id"

# sleep mock — instant (no waiting in tests)
cat > "${MOCK_BIN}/sleep" << 'MOCK'
#!/bin/bash
# no-op sleep for fast testing
MOCK
chmod +x "${MOCK_BIN}/sleep"

# whoami — use real
ln -sf "$(which whoami)" "${MOCK_BIN}/whoami"
# hostname — use real
ln -sf "$(which hostname)" "${MOCK_BIN}/hostname"
# date — use real
ln -sf "$(which date)" "${MOCK_BIN}/date"
# cat, mkdir, cp, chmod, chown, touch, grep, awk, sed, printf, tee, tr, dd, ln, rm, readlink — use real
for cmd in cat mkdir cp chmod chown touch grep awk sed printf tee tr dd ln rm readlink basename dirname head tail wc cut sort; do
    real=$(which "$cmd" 2>/dev/null) || continue
    ln -sf "$real" "${MOCK_BIN}/${cmd}"
done

# Setup AGMIND_DIR in tmpdir
AGMIND="${TESTDIR}/agmind"
mkdir -p "${AGMIND}/logs" "${AGMIND}/scripts"
mkdir -p "${TESTDIR}/LaunchAgents"
mkdir -p "${TESTDIR}/Library/LaunchAgents"

# Create fake Docker Desktop socket (fix_docker_socket checks -S)
mkdir -p "${TESTDIR}/.docker/run"
python3 -c "import socket,os; s=socket.socket(socket.AF_UNIX); p='${TESTDIR}/.docker/run/docker.sock'; os.path.exists(p) or s.bind(p)"

echo ""
echo "Running installer..."
echo ""

# Run installer with mocked PATH
PATH="${MOCK_BIN}:/usr/bin:/bin" \
AGMIND_DIR="$AGMIND" \
AGMIND_LOG_DIR="${AGMIND}/logs" \
LOG_FILE="${AGMIND}/logs/install.log" \
STATE_FILE="${AGMIND}/.install-state" \
HOME="$TESTDIR" \
NON_INTERACTIVE=1 \
DEPLOY_PROFILE=lan \
VERBOSE=1 \
DOCKER_RUNTIME=desktop \
INSTALL_OPEN_NOTEBOOK=1 \
INSTALL_DBGPT=1 \
/bin/bash "${SCRIPT_DIR}/install.sh" 2>&1

EXIT_CODE=$?

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ $EXIT_CODE -eq 0 ]; then
    echo " ✓ INTEGRATION TEST PASSED (exit $EXIT_CODE)"
else
    echo " ✗ INTEGRATION TEST FAILED (exit $EXIT_CODE)"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo "Generated files:"
find "$AGMIND" -type f | sort | while read -r f; do
    size=$(wc -c < "$f" | tr -d ' ')
    echo "  $(echo "$f" | sed "s|$AGMIND|/opt/agmind|") (${size} bytes)"
done

echo ""
echo "Verifying optional tools configuration..."
VERIFY_PASS=0
VERIFY_FAIL=0

# Check COMPOSE_PROFILES contains optional tool profiles
if grep -q "opennotebook" "${AGMIND}/.env" && grep -q "dbgpt" "${AGMIND}/.env"; then
    echo "  [PASS] COMPOSE_PROFILES includes opennotebook and dbgpt"
    VERIFY_PASS=$((VERIFY_PASS + 1))
else
    echo "  [FAIL] COMPOSE_PROFILES missing optional tool profiles"
    VERIFY_FAIL=$((VERIFY_FAIL + 1))
fi

# Check nginx.conf has optional tool location blocks
if grep -q "/notebook/" "${AGMIND}/nginx.conf" && grep -q "/dbgpt/" "${AGMIND}/nginx.conf"; then
    echo "  [PASS] nginx.conf has /notebook/ and /dbgpt/ location blocks"
    VERIFY_PASS=$((VERIFY_PASS + 1))
else
    echo "  [FAIL] nginx.conf missing optional tool location blocks"
    VERIFY_FAIL=$((VERIFY_FAIL + 1))
fi

# Check DB-GPT TOML config was generated
if [ -f "${AGMIND}/dbgpt-proxy-ollama.toml" ]; then
    echo "  [PASS] dbgpt-proxy-ollama.toml generated"
    VERIFY_PASS=$((VERIFY_PASS + 1))
else
    echo "  [FAIL] dbgpt-proxy-ollama.toml not generated"
    VERIFY_FAIL=$((VERIFY_FAIL + 1))
fi

echo ""
echo "Optional tools verification: ${VERIFY_PASS} passed, ${VERIFY_FAIL} failed"

if [ "$VERIFY_FAIL" -gt 0 ]; then
    EXIT_CODE=1
fi

exit $EXIT_CODE
