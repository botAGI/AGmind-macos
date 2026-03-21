#!/bin/bash
# tests/helpers/setup.bash -- shared BATS test setup
# Loaded by all test files via: load "../helpers/setup"
# Must be Bash 3.2 compatible
#
# IMPORTANT: BATS_TEST_TMPDIR is only available during setup/test/teardown,
# NOT during load. So directory creation and common.sh sourcing happen in setup().

# Determine project root from test file location
TEST_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
PROJECT_ROOT="$(cd "${TEST_DIR}/../.." && pwd)"

# Prepend mock bin to PATH (mocks override real commands)
export PATH="${PROJECT_ROOT}/tests/helpers/bin:${PATH}"

# Load bats assertion libraries (available at load time)
# Use `command brew` to bypass mock brew in PATH
if command -v brew >/dev/null 2>&1; then
  _BREW_PREFIX="$(command brew --prefix)"
  BATS_SUPPORT_LIB="${_BREW_PREFIX}/lib/bats-support"
  BATS_ASSERT_LIB="${_BREW_PREFIX}/lib/bats-assert"

  if [[ -d "$BATS_SUPPORT_LIB" ]]; then
    load "${BATS_SUPPORT_LIB}/load.bash"
  fi
  if [[ -d "$BATS_ASSERT_LIB" ]]; then
    load "${BATS_ASSERT_LIB}/load.bash"
  fi
fi

# setup() runs before each test -- BATS_TEST_TMPDIR is available here
setup() {
  # Override constants for testing (don't write to /opt/agmind during tests)
  export AGMIND_DIR="${BATS_TEST_TMPDIR}/agmind"
  export AGMIND_LOG_DIR="${AGMIND_DIR}/logs"
  export LOG_FILE="${AGMIND_LOG_DIR}/install.log"
  export STATE_FILE="${AGMIND_DIR}/.install-state"

  # Create test directories
  mkdir -p "$AGMIND_DIR" "$AGMIND_LOG_DIR"
  touch "$LOG_FILE" "$STATE_FILE"

  # Disable ERR trap before sourcing to avoid interference with bats
  trap - ERR

  # Source library under test
  source "${PROJECT_ROOT}/lib/common.sh"

  # Re-disable ERR trap after sourcing (common.sh sets one)
  trap - ERR
}
