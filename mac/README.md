# boxed (native macOS)

A menubar helper that stays out of your way. Summon it (shortcut, ⌥ right-click, or
the menubar `▣`) and every window on the display under your cursor snaps into a
layout. A pill drops down under the `▣` (and fades on its own) to tweak the result:

- **Reformat** — a tiny diagram of the current layout; click to cycle to the next
  layout that fits (the diagram updates to match).
- **↺ Reset** — re-fill the screen from scratch, clearing any tweaks (also brings
  back any hidden windows).
- **hide** (button at each window's top-right) — pull that window out of the layout;
  it parks centered behind the others. Stays hidden when you re-organize.
- **↩ Undo** — restore every window to where it was before you organized (and boxed
  stops managing the display). The escape hatch.
- **Drag one window onto another** to swap their spots; **drag the handles** to
  resize a split.

boxed never moves anything on its own — only when you summon it. Tier 1: needs only
Accessibility permission, no SIP.

## Layouts (by window count)

The **first** layout per count is the default; Reformat cycles the rest, skipping
any that can't fit (a fixed-min-size window can make some impossible).

| Windows | Layouts (default first)                      |
| ------- | -------------------------------------------- |
| 1       | Full                                         |
| 2       | **Left / Right**, Top / Bottom               |
| 3       | **Main + stack**, Columns, Rows, Main + row  |
| 4       | **Grid**, Columns, Rows, Main + stack        |
| 5+      | Auto (binary-space-partition fallback)       |

## Fixed-min-size windows

Some apps won't shrink past a minimum (Docker Desktop floors at ~940×600). boxed
measures each window's floor (a quick one-time probe), then:

- **sizes the layout around it** — the fixed window keeps its footprint and the
  flexible windows stretch into the rest (Columns/Rows/Grid are weighted, not even);
- **stops a divider** at that window's edge instead of sliding its neighbor under;
- **skips layouts that can't fit** when you Reformat (e.g. three windows too wide to
  sit side by side), landing on ones that do.

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

- **⌥ (Option) + right-click anywhere** → organize the display under the cursor.
- **⌥⌘T** → organize immediately.
- Menubar **`▣` → Organize windows** (greyed out with fewer than two windows, or on
  a fullscreen Space). If the display is already tiled, it re-snaps any drifted
  windows and reopens the pill; a tidy display isn't reshuffled.

## Tests

```bash
./scripts/test.sh     # runs the XCTest suite (needs a full Xcode)
```

The geometry is pure and unit-tested in `BoxedKitTests` — layouts per count,
Left/Right vs Top/Bottom, quad order, main+stack, gap insets, the "every layout
tiles with no gaps/overlap" invariant, the 5+ BSP fallback, plus the rigid-window
math: `fitRatio` (split a rigid window's min from the rest), `weightedLengths` /
weighted Columns/Rows/Grid (stretch others around it), `fits` (skip impossible
layouts), `clampOnscreen`, and `maxOverlapIndex` (which display a window is on).
Window/AX behavior that can't be unit-tested is verified live via the `live-demo`
skill (the `$TMPDIR/boxed-cmd` hook + `CGWindowList`).

## Code map

- [`Sources/BoxedKit/Tiling.swift`](Sources/BoxedKit/Tiling.swift) — the layout
  system: which layouts per count, their names, slot geometry, weighted partitions
  for rigid windows, and feasibility. **Pure, tested.**
- [`Sources/BoxedKit/Layout.swift`](Sources/BoxedKit/Layout.swift) — BSP math for
  the 5+ fallback. Pure, tested.
- [`Sources/BoxedKit/Reconcile.swift`](Sources/BoxedKit/Reconcile.swift) — pure
  cross-display reconcile (which window belongs to which boxed display after a move).
- [`WindowManager.swift`](Sources/boxed/WindowManager.swift) — finds windows (AX
  API); organize / reorganize / reformat; fits rigid windows (probes their min
  size, weights the layout, clamps dividers); reconciles cross-display moves;
  applies frames.
- [`SuggestionPanel.swift`](Sources/boxed/SuggestionPanel.swift) — the transient
  pill (non-activating, lingers then fades; supports text or image buttons).
- [`LayoutPreview.swift`](Sources/boxed/LayoutPreview.swift) — draws the tiny layout
  diagram on the Reformat button (paints `Tiling.slots`).
- [`Splitter.swift`](Sources/boxed/Splitter.swift) — the draggable divider handles.
- [`AppDelegate.swift`](Sources/boxed/AppDelegate.swift) — menubar, permission
  prompt, shortcuts, the Organize → Organize/Reformat pill flow, drag-to-swap,
  cross-display reconcile monitor.
- [`Log.swift`](Sources/boxed/Log.swift) — file logger at `$TMPDIR/boxed.log`.

## Known limitations / things to play with

- **Cross-display** moves auto-tile when both displays are boxed; **cross-Space**
  (other Spaces / fullscreen apps) is Phase 2 — it needs a partial SIP disable.
- Closing a window prunes it from its layout but the survivors keep their sizes
  (no auto-grow to fill the gap — by design).
- 5+ windows use a generic BSP layout — hand-tuned layouts for higher counts are
  the obvious "we'll get there" follow-up.
