# Spec: UX polish (from the usability eval)

Acting on the UI/UX review. Scoped per the user's direction: keep the `▣` glyph,
kill the probe flutter, and replace layout **names** with a tiny **visual diagram**
of the layout. Plus the cheap high-leverage fixes (naming, right-click). Each phase
keeps the suite green and is verified live where it's AX/visual.

## Phase 1 — kill the probe flutter

**Problem:** `applyLayout` proactively probes every unknown window's minimum
(shrink to 1×1, read, restore) so feasibility/weighting are right on the first
apply. That flutters every window on its first organize — too visible.

**Fix:** remove proactive probing; keep the flutter-free *lazy* learning (`learnMin`
in `place()` — a window that won't shrink to the slot we asked for teaches its min
as a side effect of normal tiling). Docker's min is still learned on the first
organize (it gets squeezed in the main slot); other windows' mins are learned the
first time a layout squeezes them.

**Tradeoff (accepted):** the first time you Reformat *into* an over-constrained
layout, it can briefly show overlap before the min is learned and the layout is
skipped next time. That's rare (needs a rigid window) vs. a flutter on every
organize. The `fitRigid` re-apply still corrects most of it within ~0.15s.

## Phase 2 — layout diagram instead of names

**Problem:** "Reformat" cycles blindly; users don't see what they'll get, and a
name ("Main + stack") is abstract.

**Fix:** the Reformat control becomes a **tiny diagram of the current layout** — a
rounded "screen" with boxes for each slot, mirroring the actual arrangement. Click
it to cycle (Reformat); the diagram updates to the new layout.

- `Tiling.slots` (pure, tested) already gives slot rects → reuse to lay out the
  boxes. New AppKit-only `LayoutPreview.image(kind:count:ratio:stackRatio:size:)`
  in the `boxed` target draws them (flip y: Tiling is top-left, NSImage bottom-left).
- `WindowManager.currentLayout()` exposes `(kind, count, ratio, stackRatio)`.
- `WindowSuggestion` gains an optional `image`; `SuggestionPanel` renders an
  image button when set (tooltip "Reformat").

## Phase 3 — naming & disambiguation

- "Organize **tabs**" → "Organize **windows**" (boxed arranges windows, not tabs).
- The pill's full-reset button **⧉ Organize** collides with the menubar's Organize.
  Rename it **↺ Reset** (clears tweaks, re-fills) so the two read distinctly.

## Phase 4 — ⌥ right-click tiles immediately

**Problem:** ⌥ right-click shows an intermediate "Organize tabs" pill you must click
before anything tiles — a two-pill detour (and a vestige of the removed
auto-prompt). The hotkey already tiles immediately.

**Fix:** ⌥ right-click calls `organizeEntry()` directly (tile + adjust pill), same
as ⌥⌘T. Remove the now-unused `showOrganizePill`.

## Phase 5 — Undo (next; implement if the above lands cleanly)

Snapshot each window's frame before organize/reset/reformat; an **↩ Undo** button in
the pill restores them. Lowers the stakes of pressing Organize. Extract the
snapshot/restore decision so the core is testable.

## Testing

- Pure: `Tiling.slots`/`weightedLengths`/`fits`/`fitRatio` already cover the geometry
  the preview and min-handling rely on; add a test if any new pure helper appears.
- Live (live-demo): no flutter on organize; Docker still fits and dividers still
  clamp (lazy mins); the pill shows a layout diagram that changes on Reformat;
  ⌥ right-click tiles in one step.
- `swift build && ./scripts/test.sh` green after every phase.
