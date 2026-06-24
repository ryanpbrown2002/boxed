# boxed (native macOS)

A menubar tiling window manager. Grabs your real windows, tiles them BSP-style to
fill the active display, and **reflows automatically** when a window opens or
closes. Tier 1: needs only Accessibility permission — no SIP changes.

## Build & run

```bash
cd mac
./scripts/make-app.sh        # builds boxed.app (a menubar agent, no dock icon)
open boxed.app
```

On first launch macOS will prompt for **Accessibility** permission (or grant it
in **System Settings → Privacy & Security → Accessibility**, toggle `boxed` on).
Window control is impossible without it. After granting, relaunch:

```bash
killall boxed 2>/dev/null; open boxed.app
```

You'll see a `▣` in the menubar:

- **Tile now** — tile the current windows immediately.
- **Auto-tile** — toggle live reflow on window open/close.
- **⌥⌘T** — global re-tile hotkey from anywhere.
- **Quit boxed**.

> Heads up: turning this on rearranges every standard window on your active
> display. That's the point — but expect your windows to jump on first run.

## Dev

```bash
swift build                  # debug build
swift run boxed              # run from the terminal (also rearranges windows)
```

## Layout model

[`Sources/boxed/Layout.swift`](Sources/boxed/Layout.swift) holds the pure tiling
math (no window APIs), so it can be reasoned about and checked in isolation.
Frames are recomputed purely from the current window count, which is what makes
reflow free — there's no tree state to keep in sync.

- [`WindowManager.swift`](Sources/boxed/WindowManager.swift) — discovers windows
  (Accessibility API), applies frames, and observes open/close/focus events.
- [`AppDelegate.swift`](Sources/boxed/AppDelegate.swift) — menubar, permission
  prompt, hotkey.

## Known limitations (Phase 1)

- Active display only; doesn't move windows across Spaces (that's Phase 2 / SIP).
- Tiling order follows app/window enumeration order; no manual reordering yet.
- No persisted layouts or per-app float rules yet.
- Requires full Xcode to run `swift test` with XCTest; the layout math is
  currently verified with a standalone `swiftc` check.
