# Development rules for Claude — boxed

This file is the contract for working in this repo. Read it before making changes.

## What boxed is (and is not)

boxed is a **native macOS tiling window manager** — a menubar agent (`LSUIElement`,
no dock icon). Summon it and it tiles your real OS windows on the active display
into a clean layout. It never embeds anything, and it never moves a window on its
own. The guiding feeling is "gets out of the way."

- DO keep boxed's only presence the menubar `▣` and a small, transient pill.
- DO favor summon/dismiss (hotkey, ⌥ right-click, menubar) over persistent UI.
- DON'T auto-rearrange windows or disrupt the normal macOS workflow — tiling fires
  only on a user's click or shortcut.
- DON'T turn it into a heavy dashboard or a fullscreen app.

The app lives in [`mac/`](mac/) (Swift Package Manager). It is the whole product —
there is no web/Electron component.

## Architecture & boundaries

- **Pure layout logic lives in `Sources/BoxedKit` and is unit-tested** — no AppKit
  or Accessibility APIs in this target, so it stays testable. `Tiling.swift` (which
  layouts per count, names, slot geometry, weighted partitions for rigid windows,
  feasibility), `Layout.swift` (BSP fallback for 5+), `Reconcile.swift` (cross-display
  moves), `Undo.swift` (capture policy).
- **All window manipulation goes through the Accessibility API in `WindowManager`**
  (`Sources/boxed`), which acts only on a user's click or shortcut — never on its own.
- The UI is a menubar `NSStatusItem`, a transient non-activating `NSPanel` pill
  (`SuggestionPanel`), and draggable divider handles (`Splitter`); `AppDelegate`
  wires it together. Keep the chrome minimal.

## Conventions

- Swift; match the existing files' style, naming, and comment density.
- Comments explain *why*, not *what*. The terse, lowercase UI voice is intentional —
  keep copy lowercase and calm.

## Definition of done (run before every commit)

> **ALWAYS re-run the full test suite after ANY change — no exceptions.** A change
> that "obviously can't break anything" still must be verified green:
> ```bash
> cd mac && swift build && ./scripts/test.sh
> ```
> Tests passing is necessary but not sufficient: the suite covers the pure
> `BoxedKit` logic. If you touched window/AX behavior, ALSO re-verify the real
> behavior via the `live-demo` skill (the `$TMPDIR/boxed-cmd` hook + `CGWindowList`
> inspection; rebuild with `./scripts/make-app.sh` first) — and when a regression
> slips through, add a test that would have caught it.

## Test-driven development (do this)

When fixing a bug or adding logic with a testable core, write the test FIRST:

1. Extract the decision into pure code in `Sources/BoxedKit` (no AppKit/AX).
2. Add a failing test in `Tests/BoxedKitTests`; run `./scripts/test.sh` and watch it
   go red.
3. Implement until green. Don't edit the test to fit a wrong implementation.

If the behavior is inherently AppKit / Accessibility / window-server (z-order,
focus, real window placement) it can't be a pure unit test — verify it through the
`live-demo` skill instead, and say so explicitly.

**Large/multi-part features: write a short spec in `mac/docs/` first** (problem,
design, test plan) and confirm the approach before implementing — see the existing
specs there (e.g. `docs/docker-desktop-gate.md`).

## Git workflow

- Small, focused commits. Conventional-commit prefixes: `feat:`, `fix:`, `chore:`,
  `refactor:`, `test:`, `docs:`.
- Only commit/push when the user asks. The user wants to "push as we go" — expected
  here, but confirm the message intent if ambiguous.
- Never commit `mac/.build` or `mac/boxed.app` (see `.gitignore`).

## How it works

- The flow: **Organize windows** tiles every window on the display under the cursor
  with that count's default layout (the `WindowManager` "organize session"). A pill
  then offers **Reformat** (cycle to the next layout that *fits* — shown as a tiny
  diagram of the current layout via `LayoutPreview`, not a name), **↺ Reset** (re-fill
  from scratch, clearing tweaks), and **↩ Undo** (restore the pre-organize state).
  **Drag a window onto another** swaps them; **drag the handles** resize. Each window
  gets a small **"hide"** button (top-right, `HideButton`) that pulls it out of the
  layout — parked centered behind the rest, tracked in the session's `hidden` list so
  re-editing keeps it hidden. When any are hidden the pill shows **show N hidden**
  (`restoreHidden` — brings them all back, keeping tweaks); Reset also restores but
  re-fills fresh. Summoning when already tiled re-snaps drifted windows (a tidy
  display isn't disturbed).
- **Rigid (min-size) windows** (e.g. Docker Desktop floors at ~940×600):
  `WindowManager` learns each window's minimum as a side effect of tiling, then
  `Tiling` weights Columns/Rows/Grid so the rigid window keeps its footprint and the
  rest stretch around it (`weightedLengths`), dividers clamp at its edge (`fitRatio`),
  and Reformat skips layouts that can't fit it (`fits`). Resizable windows always
  fill their slot; only non-resizable ones keep their size.
- Summon paths: ⌥ right-click anywhere, ⌥⌘T (immediate), menubar. Keep ⌥ gating on
  the right-click so normal context menus are never hijacked.
- Each display gets its own layout; when both are boxed, dragging a window across
  auto-tiles it (`Reconcile`). The pill lands on the display you organized.
- **Signing (dev only):** `scripts/setup-signing.sh` creates a stable self-signed
  identity so the Accessibility grant persists across rebuilds; `make-app.sh` uses
  it. These scripts are LOCAL DEVELOPMENT ONLY — distribution needs a real Developer
  ID + hardened runtime + notarization.
- **Tests:** `scripts/test.sh` runs the XCTest suite (it locates a full Xcode and
  sets `DEVELOPER_DIR`). Add a test in `Tests/BoxedKitTests` whenever you touch
  layout logic.
- `Log.swift` writes to `$TMPDIR/boxed.log` (per-user, 0600 — not world-readable
  /tmp). The `$TMPDIR/boxed-cmd` test hook is **off** unless launched with
  `BOXED_CMD_HOOK=1` (`open --env BOXED_CMD_HOOK=1 boxed.app`); it's a dev affordance
  (lets any local process drive boxed's AX-granted control), never a product feature.
- Build with `cd mac && ./scripts/make-app.sh`.

## Roadmap guardrails

- **Phase 1 (now):** Accessibility only — tiling of the active display, menubar +
  hotkey, multi-display reconcile. Make it feel great.
- **Phase 2 (later, opt-in):** multi-Space orchestration (other Spaces / fullscreen
  apps), which needs a partial SIP disable (the yabai tier). Do NOT pursue without
  explicit direction — it's a system-wide security change.
