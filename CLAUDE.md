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

> **ALWAYS re-run the full test suite after ANY change — no exceptions.** A change
> that "obviously can't break anything" still must be verified green before it's
> done or committed. For the native app that means:
> ```bash
> cd mac && swift build && ./scripts/test.sh
> ```
> Tests passing is necessary but not sufficient: the suite only covers the pure
> `BoxedKit` logic. If you touched window/AX behavior, ALSO re-verify the real
> behavior via the `/tmp/boxed-cmd` hook + `CGWindowList` inspection (rebuild with
> `./scripts/make-app.sh` first) — and when a regression slips through, add a test
> that would have caught it.

For the parked Electron app:

```bash
pnpm typecheck && pnpm lint && pnpm test
```

If you touched main-process behavior or the rendered layout, also run
`pnpm test:e2e` (it builds and launches the real app).

When adding a feature with non-trivial logic, add or update a unit test in
`tests/unit`. When adding user-visible flows, consider extending the Playwright
smoke test in `tests/e2e`.

## Test-driven development (do this)

When fixing a bug or adding logic with a testable core, write the test FIRST:

1. Extract the decision into pure code in `mac/Sources/BoxedKit` (no AppKit/AX).
2. Add a failing test in `mac/Tests/BoxedKitTests`; run `./scripts/test.sh` and
   watch it go red.
3. Implement until green. Don't edit the test to fit a wrong implementation.

If the behavior is inherently AppKit / Accessibility / window-server (z-order,
focus, real window placement) it can't be a pure unit test — verify it through the
`/tmp/boxed-cmd` hook + `CGWindowList` inspection instead, and say so explicitly.

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

- **Layout system lives in `Sources/BoxedKit` (pure, tested).** `Tiling.swift`
  decides which layouts each window count offers, their names, slot geometry,
  weighted partitions for rigid windows, and feasibility (`fits`); `Layout.swift` is
  the BSP fallback for 5+; `Reconcile.swift` is the cross-display move logic. No
  AppKit/window APIs in BoxedKit — keep it that way so it stays unit-testable.
- The flow: **Organize** tiles every window on the display under the cursor with
  that count's default layout (the `WindowManager` "organize session"). A pill then
  offers **Organize** (re-fill from scratch, clearing tweaks) and **Reformat**
  (cycle to the next layout that *fits*); **drag a window onto another** swaps them,
  **drag the handles** resize. Summoning when the display is already tiled just
  reopens the pill — it never re-tiles on its own. Fires only on a click/shortcut.
- **Rigid (min-size) windows** (e.g. Docker Desktop floors at ~940×600):
  `WindowManager` probes each window's hard minimum once (a brief one-time resize),
  then `Tiling` weights Columns/Rows/Grid so the rigid window keeps its footprint
  and the rest stretch around it (`weightedLengths`), dividers clamp at its edge
  (`fitRatio`), and Reformat skips layouts that can't fit it (`fits`). Resizable
  windows always fill their slot; only non-resizable ones keep their size.
- All window manipulation goes through the Accessibility API in `WindowManager`,
  which acts only on a user's click or shortcut — never on its own.
- The pill (`SuggestionPanel`) is a non-activating `NSPanel` that lingers then
  fades. Keep it unobtrusive; it doubles as boxed's only "presence."
- Summon paths: ⌥ right-click anywhere, ⌥⌘T (immediate), menubar. Keep ⌥ gating
  on the right-click so normal context menus are never hijacked.
- **Signing:** `scripts/setup-signing.sh` creates a stable self-signed identity so
  the Accessibility grant persists across rebuilds. `make-app.sh` uses it if
  present. Don't go back to ad-hoc-only — it forces a re-grant every build.
- **Tests:** `scripts/test.sh` runs the XCTest suite (it locates a full Xcode and
  sets `DEVELOPER_DIR`, since the Command Line Tools can't run `swift test`). Add a
  test in `Tests/BoxedKitTests` whenever you touch layout logic.
- `Log.swift` writes to `/tmp/boxed.log`; use it to debug `open`-launched builds.
- It's a menubar agent (`LSUIElement`, `.accessory` activation) — no dock icon,
  no main window. Keep it that way; "gets out of the way" still rules.
- Build with `cd mac && ./scripts/make-app.sh`; verify `swift build` compiles and
  `./scripts/test.sh` is green before committing. AX/window behavior that isn't
  unit-testable: verify live with the `live-demo` skill (`/tmp/boxed-cmd` hook +
  `CGWindowList`).
- **Large/multi-part features: write a short spec in `mac/docs/` first** (problem,
  design, test plan) and confirm the approach before implementing — see
  `docs/docker-desktop-gate.md`.

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
