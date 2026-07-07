# FlashForgeUI Native Port Development Guide

**Last Updated:** 2026-07-07 18:55 EDT (America/New_York)

This file provides guidance to coding agents working in this repository.

---

## Current Product Goal

The active project is the native Swift port of FlashForgeUI:

- Finish a beta-quality macOS app first.
- Keep the app useful for local users managing FlashForge printers.
- Keep a future iPad/iOS port in mind, but do not spend Mac beta effort keeping
  iPad/iOS current. Mobile can go stale until the Mac beta goal is met.
- Do not track headless, WebUI, server, cloud, Discord, Spoolman, or other
  ancillary Electron-era features as native beta work unless the user explicitly
  reopens that scope.

Apply YAGNI aggressively. If a change does not help a local user discover,
set up, inspect, control, upload to, or view a camera from a printer, do not add
it to the native beta path.

---

## Scope Discipline

- Do not edit unrelated code.
- Prefer the smallest change that advances the Mac printer-management goal.
- Treat the existing Electron/TypeScript app as reference material, not as a
  parity checklist for the native beta.
- Avoid broad abstractions until there are at least two real native call sites
  with the same shape.
- Do not add preferences because implementation options exist. Choose a safe,
  predictable default first.
- Do not add new integration surfaces unless they are necessary for local
  printer management.

---

## Native Architecture

Primary project root:

- `native/FlashForgeUI/Package.swift`

Swift products:

- `FlashForgeNativeKit`: shared models, stores, services, and SwiftUI views for
  macOS now and iPad/iOS later.
- `FlashForgeUI`: macOS app lifecycle, menus, commands, foreground activation,
  packaging, and desktop-specific affordances.
- `FlashForgeMobile`: iPad/iOS-oriented shell for future work. It is not part
  of the Mac beta gate and may lag while local Mac printer workflows stabilize.

Important native references:

- `native/FlashForgeUI/Docs/PORT_STATUS.md`: current platform coverage,
  functionality matrix, Mac beta gate, and next slices.
- `native/FlashForgeUI/Docs/UI.md`: local incorporation of
  `praeclarum/ui.md` design rules for FlashForgeUI.
- `https://github.com/praeclarum/ui.md/blob/main/UI.md`: upstream UI
  guideline source. Re-check it when changing native UI behavior or when the
  local UI contract drifts.
- `native/FlashForgeUI/README.md`: build, run, package, and optional future
  iOS-readiness commands.

---

## UI Guideline References

The native app follows `praeclarum/ui.md` as a product constraint, not an
optional styling note. Its prime directive is that a UI is good when the program
behaves the way the user expected it to behave. For this printer app, that
means every screen and action should optimize user control, predictability, and
task completion.

Use these upstream rules when implementing or reviewing native UI:

- Match the user's mental model. A printer is the primary object; protocol
  details, polling mechanics, cache state, and backend choices should stay out
  of the UI unless they help recovery.
- Design around activities, not feature lists. Prioritize discover, add,
  identify, refresh status, choose a job file, upload, pause/resume/cancel, open
  camera, and recover from mistakes.
- Reduce decisions. Do not expose preferences because the implementation has
  multiple code paths. Choose safe defaults unless the choice is central to
  managing printers or harmless personalization.
- Be consistent. Prefer native SwiftUI/macOS controls, labels, shortcuts, menu
  placement, forms, file opening, drag and drop, and confirmation behavior.
- Make actions visually obvious. Clickable controls must look clickable,
  disabled actions need understandable readiness text, and primary printer
  actions should be visible in the detail pane, toolbar, or menus.
- Respect limited attention and imperfect motor control. Keep copy short, avoid
  long instructional dialogs, use full-size targets, and provide keyboard paths
  for repeated printer workflows.
- Prefer recognition over recall. Show printer names, addresses, serial
  numbers, selected job files, recent files, camera URL state, and saved check
  code state instead of making users remember them.
- Make errors actionable. Say what failed and what to do next; keep discovery,
  setup, upload, status refresh, and job control recoverable.

Before shipping a native UI slice, verify the upstream checklist in
`UI.md` against the actual printer workflow, then keep
`native/FlashForgeUI/Docs/UI.md` aligned with any local product-specific
interpretation.

---

## Mac Beta Gate

The native Mac app is not beta-complete until these local workflows are stable:

- Discovery: find printers on the local network, preserve saved identity, and
  clearly handle empty or failed discovery.
- Setup: manually add printers, save check codes, remember camera settings,
  forget printers safely, and recover from invalid setup input.
- Status: identify printers, refresh selected/all printer status, show
  temperatures, active job state, camera availability, material station state,
  and stale/missing credential reasons.
- Control: upload supported job files, remember recent jobs, start uploaded
  prints, pause/resume/cancel active jobs, and open or recover camera streams.
- Stability: pass Swift tests, package verification, launch verification, and a
  real-printer smoke pass before calling the beta complete.

---

## Key Native Files

### App Entry

- `native/FlashForgeUI/Sources/FlashForgeUI/App/FlashForgeUIApp.swift`:
  macOS app scene, commands, settings scene, and app delegate.
- `native/FlashForgeUI/Sources/FlashForgeMobile/App/FlashForgeMobileApp.swift`:
  future iPad/iOS shell.

### Shared Model and State

- `native/FlashForgeUI/Sources/FlashForgeNativeKit/Stores/AppModel.swift`:
  root app state and printer workflows.
- `native/FlashForgeUI/Sources/FlashForgeNativeKit/Stores/PrinterProfileStore.swift`:
  saved printer profiles and credentials.
- `native/FlashForgeUI/Sources/FlashForgeNativeKit/Models/PrinterSnapshot.swift`:
  native status model.
- `native/FlashForgeUI/Sources/FlashForgeNativeKit/Models/JobFileSummary.swift`:
  selected and recent job file metadata.

### Printer Services

- `native/FlashForgeUI/Sources/FlashForgeNativeKit/Services/Discovery/`:
  UDP discovery transport and response parsing.
- `native/FlashForgeUI/Sources/FlashForgeNativeKit/Services/TCPPrinterBootstrapClient.swift`:
  unauthenticated TCP identity bootstrap.
- `native/FlashForgeUI/Sources/FlashForgeNativeKit/Services/ModernPrinterHTTPClient.swift`:
  modern printer status reads.
- `native/FlashForgeUI/Sources/FlashForgeNativeKit/Services/ModernPrinterCommandClient.swift`:
  pause, resume, cancel, start, and other local printer commands.
- `native/FlashForgeUI/Sources/FlashForgeNativeKit/Services/ModernPrinterUploadClient.swift`:
  local job upload.
- `native/FlashForgeUI/Sources/FlashForgeNativeKit/Services/CameraStreamResolver.swift`:
  local camera URL resolution.

### Native Views

- `native/FlashForgeUI/Sources/FlashForgeNativeKit/Views/ContentView.swift`:
  macOS split-view shell.
- `native/FlashForgeUI/Sources/FlashForgeNativeKit/Views/MobileContentView.swift`:
  iPad/iOS shell foundation.
- `native/FlashForgeUI/Sources/FlashForgeNativeKit/Views/DashboardView.swift`:
  overview and multi-printer refresh.
- `native/FlashForgeUI/Sources/FlashForgeNativeKit/Views/PrinterDetailView.swift`:
  selected printer status, upload, job controls, and camera controls.
- `native/FlashForgeUI/Sources/FlashForgeNativeKit/Views/AddPrinterFormView.swift`:
  manual setup flow.
- `native/FlashForgeUI/Sources/FlashForgeNativeKit/Views/SettingsView.swift`:
  durable native preferences.

### Native Tests and Scripts

- `native/FlashForgeUI/Tests/FlashForgeNativeKitTests/`: Swift tests for the
  shared kit.
- `native/FlashForgeUI/script/build_and_run.sh`: build and launch verification.
- `native/FlashForgeUI/script/package_app.sh`: local `.app` and zip packaging.
- `native/FlashForgeUI/script/verify_ios_kit.sh`: optional iPad/iOS
  cross-compile check for future mobile work.

---

## Workflow Expectations

- Use SwiftPM as the default native build system.
- Keep reusable printer logic in `FlashForgeNativeKit`.
- Keep AppKit usage out of `FlashForgeNativeKit`; limit AppKit to the macOS
  app target when SwiftUI cannot express the required Mac behavior cleanly.
- Prefer portable shared code when it is free, but do not block Mac beta work on
  iPad/iOS compile-readiness. Revisit mobile after the Mac beta gate is met.
- Use native macOS affordances: `WindowGroup`, `NavigationSplitView`,
  `Settings`, command menus, keyboard shortcuts, open panels, file importer,
  drag and drop, confirmation dialogs, and standard controls.
- Keep state ownership narrow: `@State` for root-owned observable state,
  `@Binding` for child mutation, durable storage in the store layer, and
  environment only for genuinely shared dependencies.
- Prefer direct, user-facing recovery messages over raw transport errors.
- Preserve ASCII in edited files unless the file already uses non-ASCII for a
  clear reason.

---

## Verification

For native code changes, run the smallest meaningful checks first, then expand
as the change warrants. The full native verification baseline is:

```sh
cd native/FlashForgeUI
env CLANG_MODULE_CACHE_PATH=.build/module-cache swift build --disable-sandbox
env CLANG_MODULE_CACHE_PATH=.build/module-cache swift test --disable-sandbox
./script/package_app.sh --verify
./script/build_and_run.sh --verify
```

Run `./script/verify_ios_kit.sh` only when intentionally working on the mobile
shell or when preparing to resume the iPad/iOS port after the Mac beta.

For documentation-only changes, inspect the diff and verify that references to
removed agent-specific documents are gone.

When packaging after a successful native change:

```sh
cd native/FlashForgeUI
./script/package_app.sh
```

---

## Legacy Electron Reference

The root TypeScript/Electron app and the documents under `ai_docs/`, `docs/`,
and `ai_specs/` remain useful for understanding printer behavior, protocol
history, and prior implementation choices. They are no longer the default
implementation target for the native Mac beta.

Only touch Electron-era code when the user explicitly asks for it or when a
native printer workflow requires checking behavior against the old app. If an
Electron-era feature is not necessary for local native printer management, leave
it alone.

---

Keep this guide synchronized with the native port as the Mac beta stabilizes.
