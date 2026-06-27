# Spec: hide a window from the layout (edit mode)

## Goal

In edit mode, a **Hide** button tucks a window out of the layout: it moves to the
center of the display, sits **behind** the tiled windows (so it's covered/hidden),
and the remaining windows re-tile to fill the space. The hidden window is still a
real, open window — just not part of the arrangement.

## Behavior

- **Which window:** the currently focused window on the edited display (you focus a
  window, press Hide). *(Confirming this — the one open question.)*
- **On Hide:** remove it from the layout's slots, place it centered on the display
  at its current size, and raise the tiled windows so they sit in front of it
  (AX has no "send to back", so we raise the others). The rest re-tile for the new
  (smaller) count.
- **Guard:** never hide the last tiled window (keep ≥1 in the layout).

## Persistence (the important part)

The session gains a `hidden: [Window]` list alongside `windows` (the tiled set):

- **Organize / re-snap** (the entry button when already tiled): keeps hidden
  windows hidden — re-tiles only `windows`. So re-editing doesn't resurrect them.
  (Requires matching the on-screen set against `windows + hidden`, not just
  `windows`, so "already organized" is still recognized.)
- **↺ Reset** (re-fill from scratch): clears `hidden` and tiles everything again —
  the hidden window comes back.
- **No stored session** (boxed restarted, session cleared, or window set changed):
  a fresh Organize scans all on-screen windows — the hidden one is still on screen
  (centered, behind), so it rejoins the layout. Matches "if the state isn't stored,
  Organize puts it back."

## UI

- A small **"hide"** button overlaid in the **top-right corner of each tiled
  window** (clear of the macOS traffic lights), shown in edit mode like the divider
  handles (`HideButton`, a non-activating panel; pooled + positioned by
  `positionHideButtons`). Click it to hide *that* window.
- After hiding, the pill re-presents (layout diagram + handles update to the new
  count), same refresh path as everything else.
- The hidden window is sent fully behind: activate a tiled window's app first
  (drops the hidden window's now-inactive app behind), then re-tile (which raises
  the tiled windows above it).

## Testing

- Pure (BoxedKit): `Tiling.centered(_ size:in:)` — the centered rect for a hidden
  window; plus existing layout tests cover tiling the reduced set.
- Live (live-demo): hide the focused window → it centers behind the others and the
  rest re-tile; Organize again → stays hidden; Reset → returns; relaunch/fresh
  organize → returns. Add a `hide` command to the test hook.

## Decisions (final)

- **Per-window hide button** (top-right of each window, labelled "hide") — not a
  pill button. You click the button on the window you want gone.
- **Un-hide:** ↺ Reset (or a fresh Organize with no stored state) brings hidden
  windows back. No per-window un-hide chips — they cluttered the pill.
