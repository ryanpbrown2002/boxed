# boxed (native macOS)

A menubar helper that stays out of your way. It does **not** auto-arrange your
windows. When you open a new window, a small tooltip-style pill appears near it
with a single **⧉ Organize tabs** button. Click it to tile all your windows into a
layout that adapts to how many are open (1 → full, 2 → split, 3 → thirds, 4 →
quad…). Ignore it and it fades away, leaving everything where macOS put it.
Tier 1: needs only Accessibility permission, no SIP.

## One-time setup

```bash
cd mac
./scripts/setup-signing.sh   # create a stable local signing identity (run once)
./scripts/make-app.sh        # build boxed.app (menubar agent, no dock icon)
open boxed.app
```

Grant **Accessibility** when prompted (or System Settings → Privacy & Security →
Accessibility → toggle `boxed` on), then relaunch:

```bash
killall boxed 2>/dev/null; open boxed.app
```

`setup-signing.sh` matters: it signs boxed with a stable self-signed identity so
the Accessibility grant **survives every rebuild**. Without it the app is ad-hoc
signed and macOS forgets the grant each time you rebuild. (Undo any time with
`security delete-keychain ~/Library/Keychains/boxed-dev.keychain-db`.)

## What it does

- **Suggests, never forces.** A transient, non-activating pill near each newly
  opened window. It steals no focus and fades out after ~9s.
- **One action: Organize.** Clicking **⧉ Organize tabs** BSP-tiles every window on
  the active display. The layout is derived from the window count, so opening more
  windows and re-organizing gives you a denser layout automatically.
- **Summon on demand:**
  - **⌥ (Option) + right-click anywhere** → pop the Organize pill at your cursor.
    (Gated on Option so normal right-clicks / context menus are untouched.)
  - **⌥⌘T** → organize immediately, no pill.
  - Menubar **`▣` → Organize tabs now**.
- **Menubar toggle:** *Offer to organize on new windows* (turn the pill on/off).

> Normal macOS workflow is untouched — opening apps behaves exactly as before
> unless you click Organize (or use a shortcut).

## Code map

- [`WindowManager.swift`](Sources/boxed/WindowManager.swift) — discovers windows
  (Accessibility API), watches for new ones (`AXObserver`), applies frames. Acts
  only on your click; `tidyAll()` is the organize-everything pass.
- [`Layout.swift`](Sources/boxed/Layout.swift) — pure BSP tiling math (verified
  with a standalone `swiftc` check).
- [`SuggestionPanel.swift`](Sources/boxed/SuggestionPanel.swift) — the transient
  pill (non-activating `NSPanel`, lingers then fades, screen-clamped).
- [`AppDelegate.swift`](Sources/boxed/AppDelegate.swift) — menubar, permission
  prompt, shortcuts, ⌥ right-click summon.
- [`Log.swift`](Sources/boxed/Log.swift) — file logger at `/tmp/boxed.log` (handy
  for debugging an `open`-launched build whose stderr goes nowhere).

## Dev

```bash
swift build        # debug build (no signing/bundle)
tail -f /tmp/boxed.log   # watch what the running app is doing
```

## Known limitations / things to play with

- Active display only; cross-Space moves are Phase 2 (SIP).
- BSP order follows window-enumeration order; no manual reorder/swap yet.
- No persisted layouts, no per-app float rules, no "managed set reflows when a
  window closes" yet — natural follow-ups.
- `swift test`/XCTest needs full Xcode (CLT only here); pure logic is verified via
  standalone `swiftc` checks.
