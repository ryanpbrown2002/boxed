# ▣ boxed

**A Mac window manager for lazy multitaskers.**

You've got four things open and you don't want to drag-snap each one into place.
boxed lives in your menubar and does it for you: open a window, a little **Organize
tabs** button drifts in next to it — click it and every window tiles itself to fill
the screen. Open more, click again, denser layout. That's it.

It stays out of the way. No window to maximize into, no dock icon, nothing forced.
If you ignore the button, it fades away and your windows don't move.

---

## Quick start

```bash
cd mac
./scripts/setup-signing.sh   # run once
./scripts/make-app.sh
open boxed.app
```

Grant **Accessibility** when asked (System Settings → Privacy & Security →
Accessibility), relaunch, and you'll see a `▣` in your menubar. Open a new window
and the **⧉ Organize tabs** pill appears.

## How you use it

- **Open a window** → the pill shows up nearby. Click it to tile everything.
- **Then tweak it** → a little pill drifts in with **⇄ Swap** (move windows around)
  and **▦ Rebox** (try the next layout). With two windows that's *Left / Right* vs
  *Top / Bottom*; more windows get more options.
- **⌥ (Option) + right-click anywhere** → summon the pill at your cursor.
- **⌥⌘T** → organize instantly. **Menubar `▣`** → organize, or turn the pill off.

Layouts adapt to how many windows are open — 1 fills the screen, 2 split it, 3 go in
thirds or main+stack, 4 make a quad, and 5+ tile automatically.

## Good to know

- **macOS only.** boxed arranges your real app windows using the macOS
  Accessibility API — that's why it asks for permission once.
- **Today:** tiling on your current display. **Later:** spanning Spaces and
  multiple displays (needs deeper system access; not done yet).
- The `./scripts/setup-signing.sh` step lets the permission stick across updates,
  so you only ever grant it once.

The native app lives in [`mac/`](mac/) — see [its README](mac/README.md) for the
details. Two earlier experiments are kept for reference: an Electron "tabs in one
window" app (at the repo root) and a plain-HTML layout sketch in
[`prototype/`](prototype/).

## License

MIT
