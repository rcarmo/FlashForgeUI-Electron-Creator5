# Native FlashForgeUI Design Contract

This native app follows the UI rules from `praeclarum/ui.md`:
https://github.com/praeclarum/ui.md

The migration should optimize for user control, predictability, and task
completion over feature density. The first native screens are organized around
the core activities users already understand:

- See which printers are available.
- Know whether a printer is ready, printing, paused, or needs attention.
- Inspect the current job without hunting through settings.
- Start common actions from obvious toolbar or detail-pane controls.

## Product Rules

- Use standard SwiftUI navigation, sidebars, forms, buttons, commands, and
  keyboard shortcuts before custom controls.
- Keep the sidebar lightweight: printer name, status, and one familiar icon.
- Prefer safe defaults. Do not expose preferences until they represent a choice
  users understand.
- Make disabled actions explain themselves through context, not long dialogs.
- Keep destructive printer actions out of the first native scaffold until native
  connection, job state, and recovery behavior are implemented.
- Preserve shared views and state in `FlashForgeNativeKit` so macOS, iPad, and
  iOS targets can reuse the same mental model.

## First Review Checklist

- Can a new user tell this screen is for printer monitoring and control?
- Can they discover printers without reading docs?
- Are common actions visible in the toolbar or printer detail pane?
- Are clickable controls visibly clickable and large enough for imprecise input?
- Does the UI show status instead of making the user remember printer details?
- Are settings limited to harmless, understandable preferences?
