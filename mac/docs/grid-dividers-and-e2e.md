# Spec: resizable Grid + an end-to-end test suite

## Part 1 — Grid has no in-between draggers (the bug)

A 4-window **Grid** (2×2) is the default for 4 windows, but it exposes no draggable
divider *between* the cells — only the outer edges and per-window height handles. So
you can't resize the quadrants. (Same root: `primarySplitVertical` is nil for grid,
so no internal split.)

### Design

Make the 2×2 grid adjustable with two splits stored on the session:

- `gridX` (0.5) — the vertical divide between the left/right **columns**.
- `gridY` (0.5) — the horizontal divide between the top/bottom **rows**.

`Tiling.grid` (2×2 case) sizes columns by `gridX` and rows by `gridY`, but each
split is run through `fitRatio` against that column's / row's rigid minimums — so
`gridX`/`gridY` are the *preference* and a fixed-min window (Docker) still can't be
crushed. Even split (0.5/0.5) when untouched, so existing behavior is unchanged.

`dividers()` for grid emits a **full-height vertical** handle at the column split
(`gridColumn`) and a **full-width horizontal** handle at the row split (`gridRow`),
plus the outer edges. (Drop the per-window height handles for grid — the gridRow
handle supersedes them.) `setRatio` updates `gridX`/`gridY` from the dragged handle,
clamped via the same `fitRatio`.

Pure-testable: `slots(.grid, …, gridX:, gridY:)` geometry + the divider rects.

## Part 2 — End-to-end test suite (`mac/e2e/`)

Unit tests can't catch AX/window-server regressions (stale draggers on close, etc.).
A runnable suite that drives the real app and asserts real geometry.

### Approach

- **Deterministic fixture:** hide every other regular app (so their windows aren't
  tileable), then spawn N **TextEdit** documents at known positions — the only
  windows boxed will tile. Restore (unhide) at the end.
- **Drive** boxed via the `$TMPDIR/boxed-cmd` hook (launched `BOXED_CMD_HOOK=1`).
- **Observe** real geometry via a small reader (reuse the live-demo `winz`) and the
  `$TMPDIR/boxed.log` for internal state (divider kinds).
- **Assert** with helpers → PASS/FAIL lines + non-zero exit on failure.

Files: `mac/e2e/lib.sh` (launch, fixture, hook, assertions) and `mac/e2e/suite.sh`
(scenarios). Heads-up: it rearranges windows and hides apps briefly.

### Scenarios (assertions)

1. **organize tiles cleanly** — 4 windows → all within the display, pairwise no
   overlap, count == 4.
2. **close in edit mode re-tiles** (the regression just fixed) — 4 → close 1 →
   count == 3, still no overlap (not stale 4-window layout).
3. **hide + restore** — 3 → hide → 2 tiled; restore → 3.
4. **grid is resizable** (Part 1) — organize 4 (Grid) → log shows `gridColumn` +
   `gridRow`; drag the column split → left column width changes accordingly.

### Done =

`swift build && ./scripts/test.sh` green (unit, incl. new grid math) **and**
`./e2e/suite.sh` all-pass on this machine.
