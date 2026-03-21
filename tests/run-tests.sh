#!/bin/bash
# tests/run-tests.sh -- BATS test runner for AGMind
# Installs bats-core via brew if missing, then runs all unit tests
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Install bats-core if missing
if ! command -v bats >/dev/null 2>&1; then
  echo "Installing bats-core via Homebrew..."
  brew install bats-core
fi

# Install bats-assert and bats-support if missing
BREW_PREFIX="$(brew --prefix)"
if [[ ! -d "${BREW_PREFIX}/lib/bats-assert" ]]; then
  echo "Installing bats-assert and bats-support..."
  brew tap bats-core/bats-core 2>/dev/null || true
  brew install bats-support bats-assert
fi

# Run tests -- pass through any arguments (e.g., specific test file)
if [[ $# -gt 0 ]]; then
  echo "Running: bats $*"
  /bin/bash -c "bats $*"
else
  echo "Running all unit tests..."
  /bin/bash -c "bats ${PROJECT_ROOT}/tests/unit/"
fi
