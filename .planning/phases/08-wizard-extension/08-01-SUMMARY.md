---
phase: 08-wizard-extension
plan: 01
subsystem: wizard
tags: [bash, interactive, wizard, optional-tools, open-notebook, dbgpt]

# Dependency graph
requires:
  - phase: 02-wizard (v1.0)
    provides: lib/wizard.sh with _wizard_ask, _validate_choice, run_wizard
provides:
  - WIZARD_OPEN_NOTEBOOK and WIZARD_DBGPT exports (values 0 or 1)
  - _wizard_ask_yesno helper for yes/no prompts
  - _wizard_warn_ram_optional for low-RAM warnings
affects: [09-config-templates, 11-tests]

# Tech tracking
tech-stack:
  added: []
  patterns: [y/N prompt via _wizard_ask_yesno, RAM-aware optional tool warnings]

key-files:
  created: []
  modified: [lib/wizard.sh]

key-decisions:
  - "Used case statement for y/n parsing (Bash 3.2 compatible, no ${var,,})"
  - "Default to 'no' (0) for both optional tools -- conservative approach"
  - "RAM warning threshold at 16GB, displayed once before all optional questions"

patterns-established:
  - "_wizard_ask_yesno: reusable y/N prompt pattern for future optional tool additions"
  - "Non-interactive env vars use INSTALL_ prefix, wizard exports use WIZARD_ prefix"

requirements-completed: [ONBOOK-02, DBGPT-03]

# Metrics
duration: 1min
completed: 2026-03-24
---

# Phase 8 Plan 1: Wizard Extension Summary

**Interactive wizard extended with y/N questions for Open Notebook and DB-GPT, plus non-interactive env var support and RAM-aware warnings for systems under 16GB**

## Performance

- **Duration:** 1 min
- **Started:** 2026-03-24T10:54:15Z
- **Completed:** 2026-03-24T10:55:40Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments
- Added _wizard_ask_yesno reusable helper for yes/no prompts (Bash 3.2 compatible)
- Added RAM warning for systems with less than 16GB before optional tool questions
- Interactive mode asks two new y/N questions (Open Notebook, DB-GPT) after existing 7 questions
- Non-interactive mode reads INSTALL_OPEN_NOTEBOOK and INSTALL_DBGPT env vars (default 0)
- Both modes export WIZARD_OPEN_NOTEBOOK and WIZARD_DBGPT for downstream config generation

## Task Commits

Each task was committed atomically:

1. **Task 1: Add interactive y/N questions for Open Notebook and DB-GPT** - `ac671b8` (feat)
2. **Task 2: Add non-interactive env var support for optional tools** - `43a4808` (feat)

## Files Created/Modified
- `lib/wizard.sh` - Extended with _wizard_ask_yesno, _wizard_warn_ram_optional, _wizard_ask_open_notebook, _wizard_ask_dbgpt functions; updated run_wizard interactive/non-interactive branches and summary

## Decisions Made
- Used `case` statement for y/n input parsing to maintain Bash 3.2 compatibility (no `${var,,}` lowercase)
- Both optional tools default to "no" (0) -- conservative approach, user must opt in
- RAM warning displayed once before optional tool questions (not per-question) to avoid noise

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- WIZARD_OPEN_NOTEBOOK and WIZARD_DBGPT are exported and available for Phase 9 (config-templates) to consume
- Config generation can gate Docker Compose profiles based on these values
- Tests for the new wizard questions should be added in Phase 11

---
*Phase: 08-wizard-extension*
*Completed: 2026-03-24*
