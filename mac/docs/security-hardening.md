# Spec: security-audit remediation

Addressing the audit. Native app (shipping) first; the parked Electron app gets the
cheap, safe hardening too. Each change keeps the suite green / typechecks.

## Native (`mac/`)

### N1 — command hook: off by default + per-user channel
`startCommandHook` runs unconditionally and polls world-writable `/tmp/boxed-cmd`,
letting any local process drive boxed's Accessibility-granted window control
(confused deputy, cross-user on shared `/tmp`).

- Gate it: only start when `BOXED_CMD_HOOK=1` is in the environment. Off for every
  normal launch (double-click / `open boxed.app`).
- Move the channel to the **per-user** temp dir (`NSTemporaryDirectory()`, mode
  0700, owned by the user) instead of `/tmp` — closes the cross-user hole.
- live-demo still works: `open --env BOXED_CMD_HOOK=1 boxed.app` and `$TMPDIR/boxed-cmd`
  (shell `$TMPDIR` == `NSTemporaryDirectory()` for the same user).

### N2 / N3 — log off world-readable `/tmp`
`Log` writes window titles + geometry to `/tmp/boxed.log` (world-readable; append
path follows symlinks).

- Write to `NSTemporaryDirectory()/boxed.log`; create with `0600`. The per-user dir
  is 0700/user-owned, so no cross-user read and no untrusted symlink planting
  (N3 closed without needing `O_NOFOLLOW`).

### N4 — signing scripts are dev-only
Add a header note to `setup-signing.sh` / `make-app.sh`: the self-signed identity,
hardcoded keychain password and broad key ACL are for **local development only**;
distribution uses Developer ID + notarization + hardened runtime.

A tiny `Paths.temp(_:)` helper centralizes the per-user paths.

## Electron (parked — safe hardening only)

Done:
- **E1** `will-attach-webview` (strip nodeIntegration/preload, force sandbox) +
  `setWindowOpenHandler` (deny in-app windows; route http/https to the system
  browser) on every web-contents, via `app.on('web-contents-created')`.
- **E2** "Open in real browser" → `shell.openExternal` via a new preload method
  (`openExternal`), with main validating http/https only — instead of `window.open`.
- **E5** `sandbox: true` on the BrowserWindow (preload only needs ipc/contextBridge;
  e2e confirms it still launches).

Deferred (with reason):
- **E3** CSP — correct only done *with* font-bundling (`@fontsource`) and verified
  across dev (Vite HMR) **and** packaged builds; a half CSP breaks `pnpm dev` or
  gives false assurance. React already escapes (no active XSS sink), so this is
  defense-in-depth. Do it as a dedicated change when the Electron app is revived.
- **E4** per-tab partitions — trades away shared logins (a product decision).
- **E6** Electron version bumps — ongoing maintenance, not a one-off code change.

## Verify

- Native: `swift build && ./scripts/test.sh`; live — hook is **dead** with a normal
  `open boxed.app` (write `$TMPDIR/boxed-cmd`, nothing happens), and **works** under
  `open --env BOXED_CMD_HOOK=1`; log lands in `$TMPDIR` at 0600.
- Electron: `pnpm typecheck && pnpm lint && pnpm test` (+ `test:e2e` if it runs).
