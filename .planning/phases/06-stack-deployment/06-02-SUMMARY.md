---
phase: 06-stack-deployment
plan: 02
subsystem: infra
tags: [launchd, plist, launchctl, backup, health-check, macos]

# Dependency graph
requires:
  - phase: 01-project-setup
    provides: lib/common.sh logging, die(), ensure_directory()
provides:
  - LaunchAgent plist templates for scheduled backup (3 AM daily) and health checks (60s interval)
  - lib/backup.sh module for rendering, validating, and loading LaunchAgent plists
  - scripts/backup.sh for timestamped config backup with 7-backup rotation
  - scripts/health-gen.sh for container status and Ollama API health monitoring
affects: [06-stack-deployment, install.sh phase 9 wiring]

# Tech tracking
tech-stack:
  added: [launchctl, plutil]
  patterns: [launchctl-bootstrap-with-load-fallback, plist-template-rendering]

key-files:
  created:
    - templates/launchd/com.agmind.backup.plist.template
    - templates/launchd/com.agmind.health.plist.template
    - scripts/backup.sh
    - scripts/health-gen.sh
    - lib/backup.sh
  modified: []

key-decisions:
  - "launchctl bootstrap gui/<uid> as primary with launchctl load fallback for broad macOS compatibility"
  - "Plist templates are static XML (no sed rendering needed) since all paths are fixed at /opt/agmind/"
  - "health-gen.sh returns 0 even on failure to prevent LaunchAgent from disabling itself"

patterns-established:
  - "LaunchAgent bootstrap/load fallback: try modern launchctl bootstrap first, fall back to legacy launchctl load"
  - "Plist validation: always plutil -lint before launchctl load"
  - "Explicit PATH in plist EnvironmentVariables: /opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

requirements-completed: [LAUNCH-01, LAUNCH-02, LAUNCH-03, LAUNCH-04]

# Metrics
duration: 2min
completed: 2026-03-22
---

# Phase 6 Plan 2: LaunchAgent Infrastructure Summary

**LaunchAgent plist templates for daily backup and 60s health checks with launchctl bootstrap/load fallback and plutil validation**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-21T23:04:44Z
- **Completed:** 2026-03-21T23:06:50Z
- **Tasks:** 2
- **Files created:** 5

## Accomplishments
- Two plist templates with correct scheduling (3 AM daily, 60s interval) and explicit PATH including /opt/homebrew/bin
- Backup script with timestamped config file copies and 7-backup rotation pruning
- Health check script monitoring Docker container status and Ollama API availability
- lib/backup.sh module with plist rendering, plutil validation, and launchctl bootstrap/load fallback

## Task Commits

Each task was committed atomically:

1. **Task 1: Create LaunchAgent plist templates and helper scripts** - `2fd329f` (feat)
2. **Task 2: Create lib/backup.sh for LaunchAgent rendering, validation, and loading** - `bf0d6e4` (feat)

## Files Created/Modified
- `templates/launchd/com.agmind.backup.plist.template` - Daily backup LaunchAgent plist (StartCalendarInterval, 3 AM)
- `templates/launchd/com.agmind.health.plist.template` - Health check LaunchAgent plist (StartInterval, 60s)
- `scripts/backup.sh` - Timestamped backup of /opt/agmind/ config files with 7-backup rotation
- `scripts/health-gen.sh` - Docker container status and Ollama API health checks
- `lib/backup.sh` - LaunchAgent plist installation, plutil validation, launchctl loading

## Decisions Made
- Used launchctl bootstrap gui/<uid> as primary loading method with launchctl load as fallback for older macOS compatibility
- Plist templates are static XML files (no variable substitution needed) since all paths are fixed (/opt/agmind/)
- health-gen.sh always exits 0 even on health failures to prevent LaunchAgent from auto-disabling the check
- SCRIPT_DIR fallback via BASH_SOURCE for standalone sourcing of lib/backup.sh

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- LaunchAgent infrastructure ready for Phase 9 wiring via _install_launch_agents()
- Plist templates and helper scripts ready for deployment to /opt/agmind/
- lib/backup.sh exports _install_launch_agents for install.sh integration

## Self-Check: PASSED

All 5 created files verified on disk. Both task commits (2fd329f, bf0d6e4) verified in git log.

---
*Phase: 06-stack-deployment*
*Completed: 2026-03-22*
