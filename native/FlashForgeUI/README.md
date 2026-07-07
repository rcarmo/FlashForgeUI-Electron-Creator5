# FlashForgeUI Native

Native SwiftUI migration scaffold for FlashForgeUI.

The project is intentionally split into:

- `FlashForgeNativeKit`: shared SwiftUI views, models, stores, and services for
  macOS now and iPad/iOS later.
- `FlashForgeUI`: macOS app lifecycle, commands, and foreground app launch.
- `FlashForgeMobile`: iPad/iOS-oriented SwiftUI app shell that reuses the
  shared kit without AppKit.

`Docs/UI.md` incorporates the `praeclarum/ui.md` design rules as the local
native UI contract.

## Build

```bash
swift build
swift test
./script/build_and_run.sh --verify
```

## Future iPad and iOS Readiness

The reusable app layer lives in `FlashForgeNativeKit`, and `FlashForgeMobile`
keeps an AppKit-free app shell available for later mobile work. Mobile compile
health is not part of the Mac beta gate; check it only when intentionally
working on iPad/iOS:

```bash
./script/verify_ios_kit.sh
```

The script cross-compiles the shared kit and mobile shell for
`arm64-apple-ios17.0-simulator` using the installed iPhone Simulator SDK. It
does not require a booted Simulator service.

## Package

Create and validate a local release `.app` bundle:

```bash
./script/package_app.sh --verify
```

Create a zipped release archive:

```bash
./script/package_app.sh
```

Install a locally built app bundle:

```bash
./script/package_app.sh install
```

By default, install mode copies `FlashForgeUI.app` to `/Applications`. It will
not replace an existing app unless you opt in:

```bash
INSTALL_REPLACE=1 ./script/package_app.sh install
```

For a dry local install target, override `INSTALL_DIR`:

```bash
INSTALL_DIR="$PWD/dist/local-install" ./script/package_app.sh install
```

The package script ad-hoc signs by default so the local bundle has a coherent
signature for validation. Use `SIGN_IDENTITY=none ./script/package_app.sh` to
skip signing, or pass a Developer ID identity when preparing a notarizable build:

```bash
SIGN_IDENTITY="Developer ID Application: Example Team (TEAMID)" ./script/package_app.sh
```

Developer ID signing and notarization are separate distribution steps; the
current script prepares a validated local archive under `dist/archive/`.

## Mac Beta Smoke

After packaging, generate the real-printer smoke checklist used for the Mac
beta gate:

```bash
./script/mac_beta_smoke.sh --record
```

Use `--print` to show the checklist without writing a report. The smoke pass is
Mac-only and covers discovery, setup, status, upload/control, and camera flows
with a local printer.

## Job Files

The macOS bundle declares `.gcode`, `.gx`, and `.3mf` as job file inputs. Opening
one of those files with FlashForgeUI selects it for the currently selected
printer, using the same upload readiness checks as the in-app file picker.
