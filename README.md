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

**Phase 1 — embedded web tabs (in progress).** Each box hosts a real web page via
Electron's `<webview>`, so unlike a browser iframe there are no embedding
restrictions — any site loads. Logins persist across sessions.

**Phase 2 — native window tiling (planned).** Tile *real* macOS app windows
(VSCode, Spotify, Chrome) into a saved layout. This requires the macOS
Accessibility APIs and is tracked as a separate effort.

A standalone, dependency-free HTML proof-of-concept lives in
[`prototype/index.html`](prototype/index.html) — open it in any browser to see the
original layout idea (it uses iframes, so some sites refuse to embed).

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
