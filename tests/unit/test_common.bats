#!/usr/bin/env bats
# tests/unit/test_common.bats
# Tests for lib/common.sh
# Must be Bash 3.2 compatible -- no declare -A, mapfile, ${var,,}

load "../helpers/setup"

# =============================================================================
# Logging tests (FNDTN-02)
# =============================================================================

@test "log_info produces [INFO] formatted output" {
  run log_info "test message"
  assert_success
  assert_output --partial "[INFO]"
  assert_output --partial "test message"
}

@test "log_warn produces [WARN] formatted output" {
  run log_warn "warning msg"
  assert_success
  assert_output --partial "[WARN]"
  assert_output --partial "warning msg"
}

@test "log_error produces [ERROR] formatted output" {
  run log_error "error msg"
  assert_success
  assert_output --partial "[ERROR]"
  assert_output --partial "error msg"
}

@test "log_step produces phase banner" {
  run log_step 1 "Diagnostics"
  assert_success
  assert_output --partial "Phase 1"
  assert_output --partial "Diagnostics"
}

@test "log_debug is silent when VERBOSE=0" {
  VERBOSE=0
  run log_debug "hidden"
  assert_success
  assert_output ""
}

@test "log_debug shows output when VERBOSE=1" {
  VERBOSE=1
  run log_debug "visible"
  assert_success
  assert_output --partial "[DEBUG]"
  assert_output --partial "visible"
}

@test "log_info writes to log file" {
  log_info "file test"
  run cat "$LOG_FILE"
  assert_success
  assert_output --partial "file test"
}

# =============================================================================
# Error handling tests (FNDTN-05)
# =============================================================================

@test "die exits with code 1 and shows message" {
  run die "fatal error" "try this"
  assert_failure 1
  assert_output --partial "fatal error"
}

@test "die shows hint when provided" {
  run die "fatal" "remediation step"
  assert_output --partial "Hint:"
  assert_output --partial "remediation step"
}

@test "die works without hint" {
  run die "fatal only"
  assert_failure 1
  assert_output --partial "fatal only"
}

# =============================================================================
# BSD sed tests (FNDTN-03)
# =============================================================================

@test "_atomic_sed performs basic substitution" {
  local testfile="${BATS_TEST_TMPDIR}/sedtest.txt"
  echo "KEY=old" > "$testfile"
  _atomic_sed 's/^KEY=.*/KEY=new/' "$testfile"
  run cat "$testfile"
  assert_output "KEY=new"
}

@test "_atomic_sed handles URL patterns with pipe delimiter" {
  local testfile="${BATS_TEST_TMPDIR}/urltest.txt"
  echo "URL=http://old.example.com:8080" > "$testfile"
  _atomic_sed 's|^URL=.*|URL=http://host.docker.internal:11434|' "$testfile"
  run cat "$testfile"
  assert_output "URL=http://host.docker.internal:11434"
}

@test "_atomic_sed creates no backup files" {
  local testfile="${BATS_TEST_TMPDIR}/nobackup.txt"
  echo "DATA=before" > "$testfile"
  _atomic_sed 's/before/after/' "$testfile"
  [ ! -f "${testfile}-e" ]
  [ ! -f "${testfile}.bak" ]
  run cat "$testfile"
  assert_output "DATA=after"
}

@test "_atomic_sed dies on nonexistent file" {
  run _atomic_sed 's/a/b/' "/nonexistent/file"
  assert_failure
}

# =============================================================================
# Idempotency tests (FNDTN-06)
# =============================================================================

@test "_is_phase_done returns false for untracked phase" {
  run _is_phase_done "phase_99"
  assert_failure
}

@test "_mark_phase_done then _is_phase_done returns true" {
  _mark_phase_done "phase_1"
  run _is_phase_done "phase_1"
  assert_success
}

@test "_is_phase_done does not partial match" {
  _mark_phase_done "phase_1"
  run _is_phase_done "phase_10"
  assert_failure
}

# =============================================================================
# Directory helper tests
# =============================================================================

@test "ensure_directory creates new directory" {
  local target="${BATS_TEST_TMPDIR}/newdir"
  [ ! -d "$target" ]
  ensure_directory "$target"
  [ -d "$target" ]
}

@test "ensure_directory is idempotent" {
  local target="${BATS_TEST_TMPDIR}/existingdir"
  mkdir -p "$target"
  run ensure_directory "$target"
  assert_success
}

# =============================================================================
# Mock infrastructure tests (TEST-02)
# =============================================================================

@test "mock brew is in PATH and overrides real brew" {
  run which brew
  assert_output --partial "tests/helpers/bin/brew"
  run brew --prefix
  assert_output "/opt/homebrew"
}

# =============================================================================
# Log file ANSI stripping test
# =============================================================================

@test "log file does not contain ANSI escape sequences" {
  log_info "ansi test"
  # Check for ESC character (octal 033) in log file
  run /usr/bin/grep -c "$(printf '\033')" "$LOG_FILE"
  # grep -c returns 0 lines matching = exit 1 (no matches found)
  assert_failure
}
