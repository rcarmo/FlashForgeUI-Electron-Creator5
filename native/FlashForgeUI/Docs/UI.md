# Native FlashForgeUI UI Contract

This native app incorporates the design rules from `praeclarum/ui.md`:
https://github.com/praeclarum/ui.md

For current platform coverage and Mac beta status, see
[`PORT_STATUS.md`](PORT_STATUS.md).

The upstream rule set is intentionally simple: a UI is good when the program
behaves the way the user expected. FlashForgeUI should therefore optimize for
user control, predictability, and task completion rather than novelty, density,
or internal implementation exposure.

## Design Priorities

1. Match the user's mental model.
   - Use native macOS conventions for windows, sidebars, menus, settings,
     keyboard shortcuts, file opening, drag and drop, and destructive-action
     confirmation.
   - Treat a printer as the primary object users recognize. Backend choice,
     polling details, protocol selection, and cache mechanics should stay out
     of the UI unless needed for recovery.

2. Design around activities, not feature lists.
   - The first activities are discover printers, select a printer, connect,
     inspect current status, choose a job file, upload it, monitor progress,
     open the camera, and recover from job-control mistakes.
   - Settings exist only for durable preferences and per-printer connection
     details, not as a dumping ground for every implementation toggle.

3. Reduce decisions.
   - Default to discovering printers on launch.
   - Default upload options should be safe and visible.
   - Add a preference only when it is central to the user's task or harmless
     personalization.

4. Be consistent.
   - Prefer SwiftUI `NavigationSplitView`, `Form`, `TabView`, `Settings`,
     `CommandMenu`, `Button`, `Toggle`, `Picker`, and `fileImporter` before
     custom controls.
   - Keep shared views and state in `FlashForgeNativeKit` when it helps the
     Mac app. Do not let future iPad/iOS reuse slow Mac beta completion.

5. Make actions visually obvious.
   - Primary actions must be visible in the toolbar or printer detail pane.
   - Upload supports standard picker, File menu opening, bundle document
     opening, and drag and drop so the user can use the behavior they expect.
   - Disabled actions must pair with nearby readiness text when the reason is
     not obvious.

6. Respect limited attention.
   - Use short labels and status messages.
   - Avoid long instructional dialogs.
   - Confirmation copy should explain consequences briefly, then give a clear
     cancel path.

7. Respect imperfect motor control.
   - Use full-size buttons and standard controls.
   - Do not hide core workflows behind tiny icons or precise pointer gestures.
   - Make repeated workflows available through keyboard shortcuts and menus.

8. Prefer recognition over recall.
   - Show printer names, addresses, status, selected job file, resolved camera
     stream, and saved connection context instead of making users remember them.
   - Preserve entered check codes and per-printer camera settings.

## Product Rules

- Sidebar rows stay lightweight: one familiar icon, printer name, and status.
- Detail panes may carry richer telemetry, job controls, camera state, and
  material-station state.
- Destructive printer actions are allowed only when the app has enough native
  state to make the consequence clear, the action is disabled when unavailable,
  and a confirmation path exists for hard-to-undo behavior.
- Errors should help the user regain control: say what failed and what to do
  next without exposing raw implementation details unless that detail is useful.
- Do not add preferences because the code has multiple possible behaviors.
  Choose the least surprising default first.
- Do not make users type exact values when the app can discover, remember, or
  show them.

## Native Review Checklist

Before considering a native UI slice complete, verify:

- Can a new user tell the screen is for FlashForge printer monitoring and
  control?
- Can they discover or manually add a printer without reading documentation?
- Is the current location visible: overview, selected printer, or settings?
- Are the common activities easiest to perform?
- Are standard controls, shortcuts, file-open behavior, and platform
  conventions preserved?
- Are clickable things visibly clickable, and static information visually
  non-clickable?
- Are click targets large enough for imprecise pointing?
- Are disabled actions understandable without long explanations?
- Are confirmations reserved for destructive or hard-to-undo actions?
- Does the UI show information the user would otherwise need to remember?
- Did the change stay focused on the Mac printer workflow needed for beta?
