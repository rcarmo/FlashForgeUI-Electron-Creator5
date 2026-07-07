# FlashForgeUI Native

Native SwiftUI migration scaffold for FlashForgeUI.

The project is intentionally split into:

- `FlashForgeNativeKit`: shared SwiftUI views, models, stores, and services for
  macOS now and iPad/iOS later.
- `FlashForgeNative`: macOS app lifecycle, commands, and foreground app launch.
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

## iPad and iOS Readiness

The reusable app layer lives in `FlashForgeNativeKit`, and `FlashForgeMobile`
keeps an AppKit-free app shell compiling against it. Check both with:

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

The package script ad-hoc signs by default so the local bundle has a coherent
signature for validation. Use `SIGN_IDENTITY=none ./script/package_app.sh` to
skip signing, or pass a Developer ID identity when preparing a notarizable build:

```bash
SIGN_IDENTITY="Developer ID Application: Example Team (TEAMID)" ./script/package_app.sh
```

Developer ID signing and notarization are separate distribution steps; the
current script prepares a validated local archive under `dist/archive/`.
