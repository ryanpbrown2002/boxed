---
name: live-demo
description: Drive and inspect the boxed macOS app live on this Mac for manual testing — build & relaunch it, send layout commands through the $TMPDIR/boxed-cmd hook, warp the cursor to target a display, and read back real window geometry + logs. Use when verifying boxed's tiling, multi-display, edit-mode, or fullscreen behavior on the user's real screens (behavior the unit tests can't cover).
---

# live-demo — drive & inspect boxed on this machine

boxed's window/AX behavior can't be unit-tested, so verify it live: build it,
relaunch it, send it commands through a file hook, and read back where the real
windows actually landed. Heads-up to the user before running: **this rearranges
their real windows and moves the cursor** — keep tests short.

## 0. Setup the inspection tools (idempotent)

Compile the three Swift helpers to `/tmp/boxed-demo/` if not already there. The
sources live next to this skill in `tools/`.

```bash
D=/tmp/boxed-demo; mkdir -p "$D"
SKILL=.claude/skills/live-demo/tools
[ -x "$D/winz" ]    || swiftc "$SKILL/winz.swift"    -o "$D/winz"
[ -x "$D/warp" ]    || swiftc "$SKILL/warp.swift"    -o "$D/warp"
[ -x "$D/screens" ] || swiftc "$SKILL/screens.swift" -o "$D/screens"
```

- `/tmp/boxed-demo/winz` — lists on-screen normal windows **front→back** with size
  and position (top-left coords): `owner WxH @(x,y)`.
- `/tmp/boxed-demo/screens` — lists display frames (Cocoa coords).
- `/tmp/boxed-demo/warp X Y` — moves the cursor to a point (top-left/CG coords),
  used to choose which display `organize` targets.

## 1. Build, test, relaunch

```bash
cd mac && swift build && ./scripts/test.sh        # must be green first
./scripts/make-app.sh                             # bundle (else you test a stale binary!)
killall boxed 2>/dev/null; rm -f $TMPDIR/boxed.log; open --env BOXED_CMD_HOOK=1 boxed.app
osascript -e 'delay 1' >/dev/null                 # let it launch + grab Accessibility
```

Confirm it's trusted: `grep accessibilityTrusted $TMPDIR/boxed.log` → should say `true`.
(Re-grant Accessibility once if not; the stable signing keeps it across rebuilds.)

## 2. Drive it via the command hook

The command hook is a test-only affordance and is **off** unless the app was
launched with `BOXED_CMD_HOOK=1` (the `open --env …` above) — a normal `open
boxed.app` ignores it. The channel and log live in the per-user `$TMPDIR`, not the
world-writable `/tmp`. The app polls `$TMPDIR/boxed-cmd` (~0.3s); send a command,
then wait briefly:

```bash
echo organize > $TMPDIR/boxed-cmd; osascript -e 'delay 0.8' >/dev/null
```

Commands: `organize` (entry point: tile fresh if not yet tiled; if already tiled,
just opens the adjust popup and moves nothing), `reorganize` (the popup's Organize
— a clean re-fill that resets ratios/insets/heights), `rebox` (the popup's Reformat
— cycle layout), `undo` (restore pre-organize frames + forget the session),
`hide` (pull the focused window out of the layout, parked centered behind),
`restore` (bring all hidden windows back, keeping tweaks),
`swap`, `drop`, `seed`, `reconcile`, `dismiss`,
`dividers` (logs the handle list), `ratio <0..1>`, `stack <0..1>`,
`inset <top|bottom|left|right> <pts>`, `vinset <slot> <topPts> <bottomPts>`.

To simulate moving a window across displays, mimic the real drag flow: **`seed`**
(mimics mouse-down — snapshots where each window is) → move the window with System
Events (top-left/AX coords) → **`reconcile`** (mouse-up). Without `seed` the window
has no "previous display", so it won't auto-join — reconcile just drops it.

```bash
echo seed > $TMPDIR/boxed-cmd; osascript -e 'delay 0.4' >/dev/null    # mouse-down
osascript -e 'tell application "System Events" to tell process "Google Chrome" to set position of front window to {2300, -300}'
echo reconcile > $TMPDIR/boxed-cmd; osascript -e 'delay 1.2' >/dev/null  # mouse-up
```

**Gotcha — destination coords.** A window counts as "on" the display it overlaps
most; `organize` further needs the window's *center* on the target display. The
external display can sit at negative top-left y (run `screens` + convert), so a
tall window dropped at a small positive y hangs off its bottom and gets ignored.
Place destination windows near the display's true top.

`organize` targets the display **under the cursor** — warp first to pick one:

```bash
/tmp/boxed-demo/screens                                  # find display frames
/tmp/boxed-demo/warp 855 553;  echo organize > $TMPDIR/boxed-cmd   # box display under (855,553)
```

To simulate moving a window across displays, set its position with System Events
(top-left/AX coords), then `reconcile`:

```bash
osascript -e 'tell application "System Events" to tell process "Safari" to set position of front window to {150, 90}'
echo reconcile > $TMPDIR/boxed-cmd; osascript -e 'delay 0.8' >/dev/null
```

## 3. Inspect

```bash
/tmp/boxed-demo/winz            # where every window actually is
tail -20 $TMPDIR/boxed.log         # what boxed decided (applied layout, reconcile, etc.)
```

## Tips & gotchas

- **Always `make-app.sh` after `swift build`** or you relaunch the old binary
  (this has burned us — the giveaway is an old log format).
- Clear the log (`rm -f $TMPDIR/boxed.log`) before a scenario for clean output.
- `organize`/edit are greyed for <2 windows or a fullscreen Space (by design).
- `winz` y-coords are top-left; `screens` are Cocoa (bottom-left) — don't mix them.
- A 2nd-display window shows in `winz` at `x >= <display-1 width>`.
- **Cross-display/multi-window repros are fragile — verify window state with `winz`
  first.** These burned a lot of time: an app may have *no* open windows (moving its
  "front window" silently no-ops — e.g. Chrome with no window), `AXMinimized` doesn't
  reliably stick, and apps like Safari accumulate windows across `make new document`
  calls. Before driving a cross-display move, confirm the exact window you mean to
  move actually exists in `winz` and is on the display you think — then move *that*
  one. Fresh-launched windows also tend to open on whatever display macOS considers
  active, not the one under your cursor.
- Found a bug? Add a unit test for the pure part (BoxedKit) so it can't regress.
