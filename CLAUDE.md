# Development rules for Claude — boxed

This file is the contract for working in this repo. Read it before making changes.

## What boxed is (and is not)

boxed is a **non-invasive, floating, always-on-top menubar window** that tiles
the user's tabs into a customizable, resizable grid. The guiding feeling is
"gets out of the way." Every design decision is judged against that.

- DO keep the chrome minimal and the window small/floating by default.
- DO favor summon/dismiss (hotkey + tray) over a persistent fullscreen presence.
- DON'T turn it into a heavy dashboard, a browser replacement, or a fullscreen app.
- DON'T add chrome that competes with the user's content for attention.

## Architecture & boundaries

- **Three processes, three folders.** `src/main` (Node/Electron), `src/preload`
  (bridge), `src/renderer` (React UI). Keep them separate.
- **Security is non-negotiable.** The renderer runs with `contextIsolation: true`
  and `nodeIntegration: false`. The renderer must NOT import Electron or Node
  APIs directly. Anything the UI needs from the main process goes through the
  `window.boxed` bridge in `src/preload/index.ts` (and its type in `index.d.ts`).
- **`<webview>` is how tabs are embedded** — not iframes. Keep webviews on the
  `persist:boxed` partition so logins persist.
- **Keep logic out of components.** Pure, testable logic (URL handling, layout
  math) lives in `src/renderer/src/lib/*` and must have Vitest coverage. React
  components wire that logic to the DOM; they should stay thin.

## Conventions

- TypeScript everywhere; no `any` without a written reason.
- Prettier formatting (no semicolons, single quotes, width 100) — run `pnpm format`.
- ESLint must pass — run `pnpm lint`.
- Follow the existing file's style; match its naming and comment density.
- Comments explain *why*, not *what*. The prototype's terse, lowercase UI voice
  is intentional — keep copy lowercase and calm.

## Definition of done (run before every commit)

```bash
pnpm typecheck && pnpm lint && pnpm test
```

If you touched main-process behavior or the rendered layout, also run
`pnpm test:e2e` (it builds and launches the real app).

When adding a feature with non-trivial logic, add or update a unit test in
`tests/unit`. When adding user-visible flows, consider extending the Playwright
smoke test in `tests/e2e`.

## Git workflow

- Small, focused commits. Conventional-commit style prefixes: `feat:`, `fix:`,
  `chore:`, `refactor:`, `test:`, `docs:`.
- Only commit/push when the user asks. The user wants to "push as we go" — so it
  is expected here, but still confirm the commit message intent if ambiguous.
- Never commit `out/`, `release/`, or `node_modules/` (see `.gitignore`).

## Direction (read this — the project pivoted)

boxed is now a **native macOS tiling window manager** in [`mac/`](mac/) (Swift). It
arranges the user's *real* OS windows; it does not embed anything. The Electron app
at the repo root is **parked** — an earlier "container" approach — kept for
reference but not the active product. Don't add features to it without being asked.

**Core principle — suggest, don't force.** boxed must NOT auto-rearrange windows
or disrupt the normal macOS workflow. When a new window opens it offers a small,
transient, non-activating prompt with context-aware placement options; if the user
ignores it, nothing moves. The only en-masse action is the explicit, user-invoked
"Tidy all". Do not reintroduce automatic tiling as a default.

For the native app:

- Pure geometry lives in `Suggester.swift` (which options to offer) and
  `Layout.swift` (BSP math) — no window/AppKit APIs in there, so they stay
  testable. Keep it that way. Verify with a standalone `swiftc` check.
- All window manipulation goes through the Accessibility API in `WindowManager`,
  which acts only on a user's suggestion click or Tidy all — never on its own.
- The prompt (`SuggestionPanel`) is a non-activating `NSPanel` that auto-dismisses.
  Keep it unobtrusive; it doubles as boxed's only "presence" (no separate
  on-indicator by design).
- It's a menubar agent (`LSUIElement`, `.accessory` activation) — no dock icon,
  no main window. Keep it that way; "gets out of the way" still rules.
- Build with `cd mac && ./scripts/make-app.sh`. Verify `swift build` compiles
  before committing. Verify layout math with a standalone `swiftc` check (full
  Xcode isn't installed, so `swift test`/XCTest won't run here).

## Roadmap guardrails

- **Phase 1 (now):** Tier 1 — Accessibility only. BSP auto-tiling of the active
  display, live reflow on open/close, menubar + hotkey. Make it feel great.
- **Phase 2 (later, opt-in):** multi-Space / multi-display orchestration, which
  needs a partial SIP disable (the yabai tier). Do NOT pursue without explicit
  direction — it's a system-wide security change.
- Electron packaging/signing config in `electron-builder.yml` is dormant; ignore
  unless the parked Electron app is explicitly revived.

## Known rough edges to fix as we go

- The renderer loads fonts from Google Fonts over the network. Before shipping,
  bundle them (e.g. `@fontsource`) so the app works offline and needs no relaxed CSP.
- There is no Content-Security-Policy yet; harden the renderer before release.
- The tray uses a text glyph (`▣`) instead of an icon asset — replace with a
  proper template image when we have artwork.
