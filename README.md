# ▣ boxed

**A Mac window manager for lazy multitaskers.**

You've got four things open and you don't want to drag-snap each one into place.
boxed lives in your menubar: hit a shortcut and every window on the screen tiles
itself into a clean layout. Open more, organize again, denser layout. That's it.

It never moves anything on its own — boxed only acts when you ask. No window to
maximize into, no dock icon, nothing forced.

---

## Quick start

```bash
cd mac
./scripts/setup-signing.sh   # run once
./scripts/make-app.sh
open boxed.app
```

Grant **Accessibility** when asked (System Settings → Privacy & Security →
Accessibility), relaunch, and you'll get a `▣` in your menubar.

## Organize

Tile the windows on the display your cursor is on, three ways:

- **⌥⌘T** — organize now.
- **⌥ (Option) + right-click anywhere** — organizes the display under your cursor.
- **Menubar `▣` → Organize windows** (greyed out if there's only one window, or
  the screen's a fullscreen app — nothing to tile).

Summon it again when things are already tiled and it just re-snaps anything you've
dragged out of place back into the layout (and reopens the tweak pill); a tidy
display isn't disturbed.

Layouts adapt to how many windows are open — 2 split it, 3 go main+stack, 4 make a
quad, and 5+ tile automatically. Windows fill their slots.

Some apps refuse to shrink past a minimum size (Docker Desktop, say). boxed
measures that floor and **sizes the layout around it** — the fixed window keeps its
footprint while the others stretch to fill what's left — and **skips any layout it
genuinely can't fit** when you cycle (three wide windows that won't sit side by
side, for instance).

## Tweak the layout

Right after organizing, a small pill drops down under the `▣` while you fine-tune:

- **Drag the handles** between windows to resize a split. A handle stops when the
  window next to it can't shrink any further, instead of sliding it under.
- **Drag the outer-edge handles** inward to shrink the whole layout and let some
  desktop show.
- **Drag one window onto another** to swap their spots.
- **Reformat** — a little diagram of the current layout; click it to cycle to the
  next layout that fits this set of windows (the diagram updates to match).
- **↺ Reset** — re-fill the screen from scratch, clearing any tweaks.

## Two displays

Each display gets its own layout — organize them independently. When **both** are
boxed, **dragging a window from one display to the other auto-tiles it into that
display's layout** (and the one it left reflows to fill). Drag a window to a
display that isn't boxed and it's just let go.

## Good to know

- **macOS only.** boxed arranges your real app windows via the Accessibility API —
  that's the one permission it needs.
- **Current Space only.** A fullscreen app is its own Space and can't be tiled, so
  boxed sits out there.
- `setup-signing.sh` lets the permission stick across rebuilds (grant it once).

The native app lives in [`mac/`](mac/) — see [its README](mac/README.md) for the
details and tests. Two earlier experiments are kept for reference: an Electron
"tabs in one window" app at the repo root, and a plain-HTML sketch in
[`prototype/`](prototype/).

## License

MIT
