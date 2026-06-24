# ▣ boxed

> A non-invasive floating workspace that tiles your tabs into a customizable grid.

`boxed` is a small, frameless, always-on-top window that lives in your menubar.
Summon it with a hotkey, drop a few tabs into a layout, drag the gutters to size
them however you like — then dismiss it. It's the "I have 4 things open and macOS
split-view only does 2" tool. Think of the Zoom floating window, but for *any* of
your tabs, and even less in your way.

It is **not** a fullscreen app you switch into. It floats over your work and gets
out of the way.

---

## Status

boxed is a **native macOS tiling window manager** ([`mac/`](mac/)). It arranges
your *real* app windows — it doesn't contain anything. Open a window and it fits
into the layout; close one and the survivors reflow to reclaim the space. This is
the thing: maximize your screen, integrate new windows automatically, never
manually drag-snap again.

**Phase 1 — in progress (Tier 1, Accessibility only):** BSP auto-tiling of the
active display, live reflow on window open/close, menubar agent, re-tile hotkey.
No SIP changes required.

**Phase 2 — later (opt-in):** multi-Space / multi-display orchestration, which
needs a partial SIP disable (the `yabai` tier). Not started.

### Two earlier explorations live in the repo (parked, not deleted)

- [`mac/`](mac/) is the real product (Swift, below).
- The **Electron app** at the repo root was an earlier "container" approach —
  embedding web pages in a single window. It's parked because it's a different
  product (a fancy browser, not a window manager). Kept for reference / possible
  config-UI reuse.
- A dependency-free HTML proof-of-concept of the layout idea is in
  [`prototype/index.html`](prototype/index.html).

---

## Stack

| Layer        | Choice                          |
| ------------ | ------------------------------- |
| Runtime      | Electron + TypeScript           |
| UI           | React                           |
| Build / DX   | electron-vite (Vite + HMR)      |
| Packaging    | electron-builder (`.dmg`)       |
| Tab embedding| Electron `<webview>`            |
| Lint / format| ESLint + Prettier               |
| Unit tests   | Vitest                          |
| E2E tests    | Playwright (Electron driver)    |

## Getting started

```bash
pnpm install      # or: npm install
pnpm dev          # launch the app with hot reload
```

The window appears floating and on top. It also adds a `▣` item to your menubar —
click it (or press **⌘⇧B**) to summon/dismiss boxed from anywhere.

### Everyday scripts

```bash
pnpm dev          # run in development with HMR
pnpm build        # type-check + bundle to ./out
pnpm start        # preview the production bundle
pnpm test         # unit tests (Vitest)
pnpm test:e2e     # build, then run the Playwright smoke test
pnpm typecheck    # tsc on main + renderer
pnpm lint         # eslint
pnpm format       # prettier --write
pnpm dist:mac     # build a .dmg into ./release
```

## Project layout

```
src/
  main/        Electron main process — window, tray, hotkey, IPC
  preload/     The contextBridge API exposed to the renderer (window.boxed)
  renderer/    The React UI
    src/
      App.tsx      grid of boxes + gutter resizing + window controls
      lib/         pure, unit-tested logic (url + layout math)
      styles.css
tests/
  unit/        Vitest — pure logic
  e2e/         Playwright — launches the real app
prototype/     original single-file HTML proof-of-concept
```

## How tabs are embedded

Each box renders an Electron `<webview>` on the `persist:boxed` session partition,
so cookies/logins are shared across boxes and survive restarts. Because webviews
are separate processes (not iframes), they are **not** subject to
`X-Frame-Options` / CSP framing rules — any site loads.

## License

MIT
