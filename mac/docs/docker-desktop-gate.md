# Spec: the "docker-desktop gate" — rigid (min-size) windows

## Problem

Some apps enforce a large hard **minimum window size**. Docker Desktop on this
machine clamps to **940×600** — it will not go narrower than 940pt or shorter than
600pt no matter what we ask via the Accessibility API. This breaks two things:

### A. Even-split layouts overflow

Layouts with an adjustable split already accommodate a rigid window through
`fitRigid` (it sets `ratio`/`stackRatio` so the rigid side gets its minimum and the
flexible windows take the rest):

- 2 windows: Left/Right, Top/Bottom — ✅ via `ratio`
- 3 windows: Main + stack / Main + row — ✅ via `ratio` + `stackRatio`

Layouts **without** an adjustable split partition the space evenly, so a rigid
window overflows into its neighbors:

- 3+ windows: Columns, Rows — ❌ even thirds (570pt each; Docker needs 940)
- 4 windows: Grid — ❌ even quarters

**Reproduced:** Reformat a 3-window display to Columns → Docker `940@(574,43)`
overlaps both neighbors (Safari ends at 578, Code starts at 1144).

### B. Dragging a divider toward a rigid window overlaps the neighbor

`setRatio` clamps only with `clampRatio` (floor 0.1), ignoring the adjacent
window's minimum. Drag the divider toward Docker and Docker can't shrink past 940,
so instead the **other** window slides under it.

**Reproduced:** Left/Right Docker+Safari, drag to `ratio 0.2` → Docker stays
`940@(4..944)`, Safari jumps to `@(346..1706)` — 600pt of overlap.

The slider should simply **stop** when the rigid window hits its minimum.

## Shared infrastructure: learn min sizes from tiling (non-destructive)

Both fixes need each window's minimum size. We learn it as a side effect of
placing windows — no destructive 1×1 probe:

- New `minSizes: [(window, CGSize)]` cache in `WindowManager`.
- In `place(_:in:within:)`, after setting the frame, read the window's actual size.
  If it exceeds the slot we *requested* in a dimension, the window couldn't shrink
  → that measured value is a lower bound on its minimum. Store `max(seen, measured)`
  per dimension.
- Unknown window → min `(0,0)` → treated as fully flexible (today's behavior).

`fitRigid` already squeezes rigid windows into undersized slots, so a single
organize is enough to learn Docker's 940×600.

## Fix B (smaller — do first): clamp the divider at the rigid edge

In `setRatio` (primary, stack, and the relevant edge insets), replace the bare
`clampRatio(raw)` with `Tiling.fitRatio(total:, min0:, min1:, fallback: raw)`:

- `total` = the split dimension's effective length.
- `min0`/`min1` = the two adjacent windows' learned min in that dimension (0 if
  unknown).
- `fallback` = the raw ratio the cursor maps to.

`fitRatio` already raises/lowers the fallback so neither side drops below its
minimum (and shares proportionally if neither fits). So dragging toward Docker
stops the divider at Docker's 940 edge instead of sliding Safari under it.
**Reuses existing, unit-tested `fitRatio`** — only new tests are for the wiring
(verified live) and any new min-lookup helper.

## Fix A (larger): weighted partitions so every layout fits

Make Columns/Rows fit-aware via **weighted 1-D partitions**:

- New pure `Tiling.weightedColumns/weightedRows(_ weights:[CGFloat], in:gap:)` (or a
  `minSizes:` parameter on `slots`) that sizes each column/row to satisfy its
  window's minimum first, then distributes the remainder proportionally — clamped
  so no slot collapses. Fully unit-testable in `BoxedKit`.
- `fitRigid` computes per-window weights from `minSizes` for Columns/Rows and
  re-applies. A rigid window's column grows to its min; the others shrink to share
  what's left.

**Grid (4):** a rigid cell needs both its row taller and its column wider. Plan:
weight the 2×2 grid's one row and one column that contain the rigid window. If two
rigid windows can't co-fit, fall back to the rigid window's best single-axis fit
and `clampOnscreen` the rest (documented limitation, logged — never silent).

**"Multiple options":** Reformat keeps cycling the same layout set, but every
option now stretches the others around the rigid window. If a layout genuinely
cannot fit (e.g. two windows each wider than half the screen), it is skipped in the
cycle and the skip is logged.

## Testing

- **Pure (BoxedKit, TDD):** weighted columns/rows satisfy minimums + distribute
  remainder + clamp; `fitRatio` already covers the drag clamp; min-learning is a
  pure max-merge helper.
- **Live (live-demo, before/after):** Docker 940×600 on display 1.
  - B: organize Left/Right, `ratio 0.05` → divider stops at Docker's 940 edge, no
    overlap (before: Safari slides under).
  - A: organize 3-window, Reformat through Columns/Rows → Docker keeps 940 wide,
    the other two share the remaining width; no overlap (before: overflow).

## Order of work

1. Min-size learning in `place()` (+ helper, test).
2. Fix B: divider clamp via `fitRatio` (+ live verify before/after).
3. Fix A: weighted Columns/Rows in `Tiling` (+ tests), wire into `fitRigid`.
4. Grid weighting / documented fallback.
5. Reformat skip-and-log for impossible layouts.

Each step builds + `./scripts/test.sh` green + live before/after, committed
separately.
