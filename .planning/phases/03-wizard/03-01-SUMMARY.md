---
phase: 03-wizard
plan: 01
subsystem: config
tags: [bash, wizard, interactive, non-interactive, ollama, model-recommendation]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: "common.sh logging, die(), error handling patterns"
  - phase: 02-detection
    provides: "DETECTED_RAM_GB global for model recommendation"
provides:
  - "lib/wizard.sh with run_wizard() entry point"
  - "7 WIZARD_* exported variables for config generation"
  - "RAM-aware LLM model recommendation"
  - "Non-interactive mode for CI/automation"
  - "phase_2_wizard() wired into install.sh"
affects: [05-config, 06-deployment]

# Tech tracking
tech-stack:
  added: []
  patterns: ["stderr for menu prompts / stdout for return values", "pipe-delimited model data arrays", "generic _wizard_ask menu function"]

key-files:
  created: ["lib/wizard.sh", "tests/unit/test_wizard.bats"]
  modified: ["install.sh"]

key-decisions:
  - "Menu prompts output to stderr, return values to stdout -- enables clean $() capture in both production and BATS tests"
  - "Pipe delimiter for model data arrays -- avoids conflict with Ollama model tag colons"
  - "Any string accepted for LLM_MODEL in non-interactive mode -- allows custom model tags beyond the known list"

patterns-established:
  - "Menu function pattern: _wizard_ask() with numbered options, default selection, re-prompt on invalid input"
  - "Validation pattern: _validate_choice() with die() on invalid, listing valid options"
  - "Interactive test pattern: pipe input via printf | function, capture menu output via 2>&1"

requirements-completed: [WIZ-01, WIZ-02, WIZ-03, WIZ-04]

# Metrics
duration: 7min
completed: 2026-03-21
---

# Phase 3 Plan 01: Wizard Summary

**Interactive config wizard with 7 numbered menus, RAM-aware LLM recommendation, and NON_INTERACTIVE env var passthrough exporting WIZARD_* variables**

## Performance

- **Duration:** 7 min
- **Started:** 2026-03-21T18:54:14Z
- **Completed:** 2026-03-21T19:01:50Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments
- Full interactive wizard with 7 questions in fixed order: profile, LLM model, embed model, vector DB, ETL mode, monitoring, backup
- LLM model menu with star-marked recommendation based on DETECTED_RAM_GB and "requires NGB+" warnings for oversized models
- Non-interactive mode that reads from env vars with defaults, validates 6 of 7 params (LLM accepts any string), and dies with valid options on bad input
- 34 BATS tests covering all 4 requirements (WIZ-01 through WIZ-04) with zero failures
- Full test suite of 90 tests passes with no regressions

## Task Commits

Each task was committed atomically:

1. **Task 1: Create lib/wizard.sh with interactive wizard, model menu, non-interactive mode, and WIZARD_* exports**
   - `e32cde5` (test: RED phase -- failing tests)
   - `69ad50b` (feat: GREEN phase -- full implementation)
   - `8dd7f4e` (refactor: cleanup RED test file)

2. **Task 2: Create tests/unit/test_wizard.bats with comprehensive BATS tests**
   - `7251065` (test: 34 tests covering WIZ-01 through WIZ-04, plus stderr fix for menu prompts)

_Note: TDD tasks have multiple commits (test -> feat -> refactor)_

## Files Created/Modified
- `lib/wizard.sh` -- Interactive and non-interactive config wizard with run_wizard(), 7 ask functions, _get_recommended_model(), _validate_choice(), _wizard_non_interactive()
- `install.sh` -- Added source wizard.sh and phase_2_wizard() function
- `tests/unit/test_wizard.bats` -- 34 BATS tests covering model recommendation, validation, non-interactive defaults/overrides/errors, interactive menus, and WIZARD_* export verification

## Decisions Made
- Menu prompts (printf output) go to stderr so that $() subshell capture returns only the selected value on stdout -- this also makes BATS testing cleaner since menu text and return values are separated
- LLM_MODEL accepts any arbitrary string in non-interactive mode (user may have custom models not in the known list)
- For 192GB+ systems, recommend qwen2.5:72b (same as 96GB tier) since the highest model tier maxes out at 96GB

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Menu prompt output mixed with return values**
- **Found during:** Task 2 (interactive test writing)
- **Issue:** _wizard_ask() and _wizard_ask_llm_model() sent both menu display and return value to stdout, making $() capture unreliable
- **Fix:** Redirected all printf menu output to stderr (>&2), keeping only echo return values on stdout
- **Files modified:** lib/wizard.sh
- **Verification:** All 34 BATS tests pass, interactive functions return clean values
- **Committed in:** 7251065 (part of Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Essential fix for correct function behavior in both production and testing. No scope creep.

## Issues Encountered
- Bash pipe-to-subshell variable loss: `printf | run_wizard` causes WIZARD_* variables to be lost because the right side of a pipe runs in a subshell. Test was updated to verify wizard behavior via log output assertions rather than post-pipe variable checks.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- All 7 WIZARD_* variables are exported and ready for config.sh consumption in Phase 5
- lib/wizard.sh is fully Bash 3.2 compatible (verified with /bin/bash -n)
- phase_2_wizard() is wired into install.sh phase runner
- 90 total tests pass (21 common + 35 detect + 34 wizard)

## Self-Check: PASSED

- All 3 created files exist (lib/wizard.sh, tests/unit/test_wizard.bats, 03-01-SUMMARY.md)
- All 4 task commits verified (e32cde5, 69ad50b, 8dd7f4e, 7251065)
- Wizard test suite passes (34/34)
- Full test suite passes (90/90)

---
*Phase: 03-wizard*
*Completed: 2026-03-21*
