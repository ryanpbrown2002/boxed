# boxed (native macOS)

A menubar helper that stays out of your way. When you open a new window, a small
pill appears with **⧉ Organize tabs**. Click it and every window on the display
snaps into a layout. A second pill drifts in (bottom-center, fades on its own) to
tweak the result:

- **⇄ Swap** — rotate which window sits in which slot.
- **▦ Rebox** — cycle to the next layout for that window count.

Ignore the pills and nothing moves — your normal macOS workflow is untouched.
Tier 1: needs only Accessibility permission, no SIP.

## Layouts (by window count)

| Windows | Layouts you cycle through (Rebox)            |
| ------- | -------------------------------------------- |
| 1       | Full                                         |
| 2       | **Left / Right**, **Top / Bottom**           |
| 3       | Columns, Rows, Main + stack, Main + row      |
| 4       | Grid, Columns, Rows, Main + stack            |
| 5+      | Auto (binary-space-partition fallback)       |

## One-time setup

```bash
cd mac
./scripts/setup-signing.sh   # stable signing → grant Accessibility just once
./scripts/make-app.sh        # build boxed.app (menubar agent, no dock icon)
open boxed.app
```

Grant **Accessibility** when asked (System Settings → Privacy & Security →
Accessibility), relaunch, and a `▣` appears in your menubar. Open a window to see
the Organize pill.

## Shortcuts & menubar

- **⌥ (Option) + right-click anywhere** → Organize pill at your cursor.
- **⌥⌘T** → organize immediately.
- Menubar **`▣`** → *Organize tabs now*, or toggle the new-window pill off.

## Tests

```bash
./scripts/test.sh     # runs the XCTest suite (needs a full Xcode)
```

The snapping geometry is pure and unit-tested in `BoxedKitTests` — layouts per
count, Left/Right vs Top/Bottom, quad order, main+stack, gap insets, the
"every layout tiles with no gaps/overlap" invariant, and the 5+ BSP fallback.

## Code map

- [`Sources/BoxedKit/Tiling.swift`](Sources/BoxedKit/Tiling.swift) — the layout
  system: which layouts per count, their names, and slot geometry. **Pure, tested.**
- [`Sources/BoxedKit/Layout.swift`](Sources/BoxedKit/Layout.swift) — BSP math for
  the 5+ fallback. Pure, tested.
- [`WindowManager.swift`](Sources/boxed/WindowManager.swift) — finds windows (AX
  API), runs the organize session (organize / rebox / swap), applies frames.
- [`SuggestionPanel.swift`](Sources/boxed/SuggestionPanel.swift) — the transient
  pill (non-activating, lingers then fades; supports a title + keep-open buttons).
- [`AppDelegate.swift`](Sources/boxed/AppDelegate.swift) — menubar, permission
  prompt, shortcuts, the two-stage Organize → Swap/Rebox flow.
- [`Log.swift`](Sources/boxed/Log.swift) — file logger at `/tmp/boxed.log`.

## Known limitations / things to play with

- Active display only; cross-Space moves are Phase 2 (SIP).
- Organize captures the windows present at click time; if one closes mid-session,
  applying to it simply no-ops (a "reflow when a window closes" mode is a natural
  next step).
- 5+ windows use a generic BSP layout — hand-tuned layouts for higher counts are
  the obvious "we'll get there" follow-up.
