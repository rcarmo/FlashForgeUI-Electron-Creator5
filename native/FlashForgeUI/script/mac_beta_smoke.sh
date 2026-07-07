#!/usr/bin/env bash
set -euo pipefail

MODE="${1:---record}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="FlashForgeUI"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
SMOKE_DIR="$ROOT_DIR/dist/smoke"

commit_sha() {
  git -C "$ROOT_DIR/../.." rev-parse --short HEAD 2>/dev/null || echo "unknown"
}

build_stamp() {
  date +"%Y-%m-%d %H:%M:%S %Z"
}

print_checklist() {
  cat <<'CHECKLIST'
# FlashForgeUI Mac Beta Real-Printer Smoke

Use a local FlashForge printer on the same LAN as this Mac. Use a harmless
throwaway job file when testing upload and print controls.

Result key: PASS, FAIL, or NOT RUN.

## Preflight

- [ ] PASS/FAIL - Packaged app launches from `dist/FlashForgeUI.app`.
- [ ] PASS/FAIL - App starts as a regular Mac app with a visible main window.
- [ ] PASS/FAIL - No Electron, WebUI, headless, cloud, Discord, or Spoolman setup is required.

## Discovery

- [ ] PASS/FAIL - Discover Printers finds at least one powered-on local printer.
- [ ] PASS/FAIL - Empty or failed discovery shows a recoverable message.
- [ ] PASS/FAIL - Saved printers remain visible when discovery finds nothing.

## Setup

- [ ] PASS/FAIL - Add Printer accepts a valid address or URL and normalizes it.
- [ ] PASS/FAIL - Invalid manual addresses are rejected before saving.
- [ ] PASS/FAIL - Check code is saved per printer and can be cleared.
- [ ] PASS/FAIL - Forget Printer asks for confirmation and removes saved credentials.

## Status

- [ ] PASS/FAIL - Connect identifies model and serial number.
- [ ] PASS/FAIL - Refresh Status shows printer state, nozzle and bed temperatures.
- [ ] PASS/FAIL - Refresh All Statuses updates every refreshable saved printer.
- [ ] PASS/FAIL - Switching printers does not reuse another printer's cached status.
- [ ] PASS/FAIL - Missing check code, serial number, or network failures explain recovery.
- [ ] PASS/FAIL - AD5X material station status is readable when available.

## Upload And Control

- [ ] PASS/FAIL - Choose Job File accepts `.gcode`, `.gx`, and `.3mf`.
- [ ] PASS/FAIL - Unsupported files are rejected with a clear message.
- [ ] PASS/FAIL - Recent job files are remembered per printer.
- [ ] PASS/FAIL - Upload only sends the file without starting the printer.
- [ ] PASS/FAIL - Upload and start begins a throwaway print.
- [ ] PASS/FAIL - Pause, Resume, and Cancel controls reflect the active job state.
- [ ] PASS/FAIL - Cancel Print asks for confirmation before sending the command.
- [ ] PASS/FAIL - Rejected or unreachable job commands show actionable recovery.

## Camera

- [ ] PASS/FAIL - Open Camera resolves the reported or fallback local stream.
- [ ] PASS/FAIL - Inline MJPEG preview renders when the printer exposes it.
- [ ] PASS/FAIL - RTSP or external streams open in the system handler.
- [ ] PASS/FAIL - Custom camera URL can be set, validated, reset, and reopened.

## Notes

- Printer model(s):
- Firmware version(s):
- macOS version:
- Network type:
- Failures or follow-up work:
CHECKLIST
}

record_checklist() {
  mkdir -p "$SMOKE_DIR"
  local report_path="$SMOKE_DIR/mac-beta-smoke-$(date +"%Y%m%d-%H%M%S").md"
  {
    echo "# FlashForgeUI Mac Beta Real-Printer Smoke"
    echo
    echo "- Created: $(build_stamp)"
    echo "- Commit: $(commit_sha)"
    echo "- App bundle: $APP_BUNDLE"
    echo
    print_checklist | sed '1,2d'
  } >"$report_path"
  echo "$report_path"
}

case "$MODE" in
  --print|print)
    print_checklist
    ;;
  --record|record)
    record_checklist
    ;;
  *)
    echo "usage: $0 [--print|--record]" >&2
    exit 2
    ;;
esac
