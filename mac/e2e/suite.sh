#!/usr/bin/env bash
# boxed end-to-end suite — drives the real app and asserts real window geometry.
# Run from anywhere:  mac/e2e/suite.sh
# It builds + launches boxed (with the test hook), hides your other apps briefly,
# spawns TextEdit windows to tile, and restores everything on exit.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "boxed e2e — building, launching, and taking over the screen briefly…"
e2e_boot
e2e_hide_others

# 1 ─ Organize tiles cleanly (no overlap, right count).
scenario "organize 4 windows → clean grid"
e2e_spawn 4
e2e_target
e2e_cmd organize 1.4
assert_count 4 "all 4 windows tiled"
assert_no_overlap "tiled windows don't overlap"

# 2 ─ Grid is resizable: it must expose the internal column + row dividers.
scenario "4-window grid exposes in-between draggers"
e2e_clearlog
e2e_cmd dividers 0.6
assert_log "gridColumn" "grid has a column divider"
assert_log "gridRow" "grid has a row divider"

# 3 ─ Close a window mid-edit → re-tiles (regression: stale draggers).
scenario "close a window in edit mode → re-tiles to 3"
osascript -e 'tell application "TextEdit" to close front document saving no' >/dev/null 2>&1
osascript -e 'delay 1.3' >/dev/null
assert_count 3 "re-tiled to 3 after close"
assert_no_overlap "still no overlap after close"

# 4 ─ Hide a window → it leaves the layout; restore brings it back.
# (A hidden window is parked centered, still on screen — so we assert the tiled
# count via the log, not the window count.)
scenario "hide a window → 2 tiled; restore → 3"
osascript -e 'tell application "TextEdit" to activate' >/dev/null 2>&1
osascript -e 'delay 0.3' >/dev/null
e2e_clearlog
e2e_cmd hide 1.3
assert_log "2 tiled, 1 hidden" "hide → 2 tiled, 1 set aside"
e2e_clearlog
e2e_cmd restore 1.3
assert_log "restored hidden windows; 3 tiled" "restore → 3 tiled"

# 5 ─ Cross-display: drag a window from one boxed display onto another → it joins
# that display's layout (Reconcile). Skipped when only one display is connected.
scenario "drag a window across displays → it joins the other layout"
if ! e2e_has_secondary; then
  printf '  (skipped — only one display connected)\n'
else
  PRIMARY="$(e2e_rect primary)"
  SECONDARY="$(e2e_rect secondary)"
  # 5 fresh docs, parked 3 on the built-in and 2 on the secondary so BOTH displays
  # have enough to box (organize is a no-op on a display with <2 windows).
  e2e_spawn 5
  e2e_move_a_primary_window_to -1000 -300
  e2e_move_a_primary_window_to -1550 -300
  e2e_target;           e2e_cmd organize 1.4   # box the built-in (3 windows)
  e2e_target_secondary; e2e_cmd organize 1.4   # box the secondary (2 windows)
  assert_count_on "$PRIMARY"   3 "built-in boxed with 3"
  assert_count_on "$SECONDARY" 2 "secondary boxed with 2"

  # Snapshot (mouse-down), drag a built-in window onto the secondary, reconcile
  # (mouse-up): the window leaves the built-in (3→2) and joins the secondary (2→3).
  e2e_cmd seed 0.6
  e2e_move_a_primary_window_to -1200 -400
  e2e_clearlog
  e2e_cmd reconcile 1.4
  assert_count_on "$PRIMARY"   2 "built-in re-tiled to 2 after the drag-out"
  assert_count_on "$SECONDARY" 3 "secondary picked up the dragged window"
  assert_no_overlap "the dragged window joined the layout (nothing floats/overlaps)"
  assert_log_count "reconcile: display" 2 "reconcile re-tiled both displays"
fi

summary
