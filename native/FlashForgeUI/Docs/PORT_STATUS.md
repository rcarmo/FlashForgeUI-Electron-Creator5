# Native FlashForgeUI Port Status

Last reviewed: 2026-07-07

This document tracks the native Swift port against the current beta target.
It is intentionally evidence-based: a feature is marked implemented only when
there is current native code for the workflow, not merely a planned shape.

The current goal is Mac completion first: beta-quality local user workflows
for discovery, setup, full printer status, and printer control. Headless,
remote, and server workflows are intentionally out of scope for the native Mac
beta.

Apply YAGNI aggressively: if work does not help a local user manage printers,
do not track it as beta work.

## Overall State

The native port is a functional macOS alpha moving toward a local-use beta.
The package still contains a future iPad/iOS shell, but mobile readiness is
allowed to go stale until the Mac beta goal is met.

- `FlashForgeUI` is the packaged macOS SwiftUI app.
- `FlashForgeNativeKit` contains shared models, services, stores, and views.
- `FlashForgeMobile` is the iPad/iOS-oriented shell for future mobile work.
- macOS packaging produces `dist/FlashForgeUI.app` and
  `dist/archive/FlashForgeUI.zip`.
- iPad/iOS support is deferred; compile health is not part of the Mac beta gate.

## Platform Coverage

| Area | macOS | iPad/iOS |
| --- | --- | --- |
| App shell | Implemented with `WindowGroup`, `NavigationSplitView`, `Settings`, and command menus | Deferred until after Mac beta; may be stale |
| Shared app model | Implemented | Intended future reuse, not a current beta gate |
| Printer discovery | Implemented | Deferred; runtime local-network behavior not validated on simulator/device |
| Manual printer add | Implemented | Deferred |
| Saved profiles | Implemented with file-backed JSON store | Deferred; storage behavior needs future device validation |
| Status refresh | Implemented | Deferred; runtime network behavior needs future device validation |
| Upload workflow | Implemented | Deferred; document picker/runtime upload needs future device validation |
| Camera workflow | Partial | Deferred; inline rendering/runtime permissions need future device validation |
| Packaging | Local `.app`, ad hoc signing, zip archive | No non-Mac packaging tracked for Mac beta |
| Verification | Swift build/test, package verify, launch verify | Optional; run only when intentionally resuming mobile work |

## Functionality Matrix

| Feature | Native status | Evidence | Remaining work |
| --- | --- | --- | --- |
| UI principles from `praeclarum/ui.md` | Incorporated | `Docs/UI.md` captures user-control, predictability, recognition, standard controls, and recovery rules | Keep this doc updated as new UI surfaces land |
| Native macOS shell | Implemented | `Sources/FlashForgeUI/App/FlashForgeUIApp.swift` | Only polish shell behavior that improves printer workflows |
| Shared Swift kit | Implemented | `Sources/FlashForgeNativeKit/**` | Continue moving cross-platform logic into the kit |
| iPad/iOS shell | Deferred | `Sources/FlashForgeNativeKit/Views/MobileContentView.swift` and `Sources/FlashForgeMobile/App/FlashForgeMobileApp.swift` exist for future work | Let this go stale until the Mac beta is stable |
| Discovery | Implemented | `NativePrinterDiscoveryService`, `SocketDiscoveryTransport`, `DiscoveryResponseParser` | Validate on real macOS networks |
| Manual printer profiles | Implemented | `AddPrinterFormView`, `AppModel.addManualPrinter`, profile tests | Add richer edit flows if needed |
| Saved connection context | Implemented | `PrinterProfileStore`, check-code and camera config persistence | Consider migration/versioning once schema grows |
| TCP bootstrap identity | Implemented | `TCPPrinterBootstrapClient`, `PrinterInfoParser` | Harden against more firmware variants |
| Modern HTTP status refresh | Implemented | `ModernPrinterHTTPClient`, `AppModel.refreshSelectedPrinterStatus` | Broaden status decoding for more models/firmware |
| Multi-printer overview | Basic implemented | `DashboardView`, refresh/identify-all actions | Validate local multi-printer workflows with real printers |
| Auto-refresh | Basic implemented | `DashboardView` and `PrinterDetailView` `.task` loops | Add lifecycle/backoff controls if needed |
| Job file selection | Implemented | File importer, macOS open panel, document open, drag/drop, recent files | Validate Mac file-open and drag/drop flows with real use |
| Job upload | Implemented for modern printers | `ModernPrinterUploadClient`, upload tests | Wider firmware and real-printer testing |
| Print job controls | Implemented for modern printers | Pause, resume, cancel commands and tests | Wider firmware testing and richer state sync |
| Camera stream resolution | Partial | `CameraStreamResolver`, `CameraPreviewView`, custom URL settings | Robust inline/open-stream behavior for local Mac use |
| Material station display | Partial | `MaterialStationView`, modern status decoding | Validate local AD5X status display with real printers |
| Settings | Basic implemented | `SettingsView` | Split/expand settings as feature surface grows |
| Mac menus and shortcuts | Implemented for core flows | `FlashForgeUIApp.swift` command menus | Audit shortcut conflicts as features grow |
| Native UI automation | Not implemented | Native has unit tests and package launch verify only | Add UI tests for local Mac beta workflows |

## Current Verification Baseline

The expected verification sequence for native code changes is:

```sh
env CLANG_MODULE_CACHE_PATH=.build/module-cache swift build --disable-sandbox
env CLANG_MODULE_CACHE_PATH=.build/module-cache swift test --disable-sandbox
./script/package_app.sh --verify
./script/build_and_run.sh --verify
```

Run `./script/verify_ios_kit.sh` only when intentionally working on the mobile
shell or when restarting iPad/iOS port work after the Mac beta.

For documentation-only changes, inspect the diff and keep this matrix accurate.

## Mac Beta Completion Gate

Consider the native Mac beta stable only when these local workflows are
implemented and verified:

- Discovery: find printers on the local network, preserve saved identity, and
  clearly handle empty or failed discovery.
- Setup: manually add printers, save check codes, remember camera settings,
  forget printers safely, and recover from invalid setup input.
- Status: identify printers, refresh selected/all printer status, show
  temperatures, active job state, camera availability, material station state,
  and stale/missing credential reasons.
- Control: upload supported job files, remember recent jobs, start uploaded
  prints, pause/resume/cancel active jobs, and open or recover camera streams.
- Stability: pass Swift tests, package verification, launch verification, and
  a real-printer smoke pass before calling the beta complete.

## Next High-Value Slices

1. Add a real-printer Mac smoke checklist/script for discovery, setup, status,
   upload, job control, and camera open.
2. Harden modern printer status/control error handling around network loss,
   missing credentials, and rejected commands.
3. Fill any remaining local camera gaps needed for dependable Mac beta use
   without broadening scope into server/proxy workflows.
4. Add native UI automation that exercises discovery, manual add, upload file
   selection, and settings navigation.
