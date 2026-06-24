# boxed (native macOS)

A menubar helper that stays out of your way. It does **not** auto-arrange your
windows. Instead, when you open a new window, a small tooltip-style prompt appears
near it — *"Snap into layout?"* — with a couple of context-aware options. Click one
to place the window; ignore it and it disappears on its own, leaving the window
exactly where macOS put it. Tier 1: needs only Accessibility permission, no SIP.

## Build & run

```bash
cd mac
./scripts/make-app.sh        # builds boxed.app (a menubar agent, no dock icon)
open boxed.app
```

On first launch macOS prompts for **Accessibility** permission (or grant it in
**System Settings → Privacy & Security → Accessibility**, toggle `boxed` on).
Window control is impossible without it. After granting, relaunch:

```bash
killall boxed 2>/dev/null; open boxed.app
```

Then open a new window somewhere and the prompt should appear next to it.

## What it does

- **Suggests, never forces.** A transient, non-activating prompt near each newly
  opened window. It steals no focus and auto-dismisses after a few seconds.
- **Context-aware options.** If one window already fills the screen, you get
  *Split* choices (placing the newcomer beside it and nudging the incumbent to the
  other half). Otherwise you get quick spots (*Left / Right / Fill*).
- **Menubar `▣`:**
  - **Suggest layouts for new windows** — toggle the prompt on/off.
  - **Tidy all windows (⌥⌘T)** — the one *active* command: BSP-tile everything on
    the current display. User-initiated only; also bound to the global hotkey.
  - **Quit boxed**.

> Normal macOS workflow is untouched: opening apps behaves exactly as before
> unless you click a suggestion. Only **Tidy all** moves windows en masse.

## Code map

- [`Suggester.swift`](Sources/boxed/Suggester.swift) — pure geometry that decides
  which placement options to offer (verified with a standalone `swiftc` check).
- [`SuggestionPanel.swift`](Sources/boxed/SuggestionPanel.swift) — the transient
  prompt (non-activating `NSPanel`, auto-dismiss, screen-clamped positioning).
- [`WindowManager.swift`](Sources/boxed/WindowManager.swift) — discovers windows,
  watches for new ones (`AXObserver`), applies frames. Holds no opinions of its
  own; only acts on your clicks (or Tidy all).
- [`Layout.swift`](Sources/boxed/Layout.swift) — pure BSP math used by Tidy all.
- [`AppDelegate.swift`](Sources/boxed/AppDelegate.swift) — menubar, permission
  prompt, hotkey.

## Dev

```bash
swift build                  # debug build
```

## Known limitations / things to play with

- Suggestions consider the single largest existing window; richer "fit into the
  free space" logic is the obvious next experiment.
- A new window opened by an app that *just* launched can be missed (we attach the
  observer a beat after launch).
- No persisted layouts, manual reorder, or "managed set reflows when a window
  closes" yet — that auto-reflow-on-close idea is a natural follow-up for windows
  you explicitly snapped.
- Active display only; cross-Space moves are Phase 2 (SIP).
- `swift test`/XCTest needs full Xcode (CLT only here); pure logic is verified via
  standalone `swiftc` checks.
