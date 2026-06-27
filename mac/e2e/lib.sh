#!/usr/bin/env bash
# Shared helpers for boxed's end-to-end suite. These drive the REAL app and assert
# REAL window geometry — the regressions unit tests can't reach (stale handles,
# reflow on close, hide/restore, grid dividers).
#
# Fixture: we hide every other foreground app (so only our windows are tileable),
# then spawn TextEdit documents as known, controllable windows. Everything is
# restored on exit. Heads-up: this briefly hides your apps and moves windows.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP="$ROOT/mac/boxed.app"
WORK="${TMPDIR%/}/boxed-e2e"
WINZ="$WORK/winz"
WARP="$WORK/warp"
SCREENS="$WORK/screens"
LOG="${TMPDIR%/}/boxed.log"
CMD="${TMPDIR%/}/boxed-cmd"

PASS=0
FAIL=0

# ── tiny output helpers ────────────────────────────────────────────────────
_grn() { printf '\033[32m%s\033[0m\n' "$1"; }
_red() { printf '\033[31m%s\033[0m\n' "$1"; }
ok()   { PASS=$((PASS+1)); _grn "  ✓ $1"; }
bad()  { FAIL=$((FAIL+1)); _red "  ✗ $1"; }
scenario() { printf '\n▸ %s\n' "$1"; }

# ── lifecycle ──────────────────────────────────────────────────────────────
e2e_boot() {
  mkdir -p "$WORK"
  [ -x "$WINZ" ] || swiftc "$ROOT/.claude/skills/live-demo/tools/winz.swift" -o "$WINZ" || {
    _red "failed to build winz"; exit 1; }
  [ -x "$WARP" ] || swiftc "$ROOT/.claude/skills/live-demo/tools/warp.swift" -o "$WARP" || {
    _red "failed to build warp"; exit 1; }
  [ -x "$SCREENS" ] || swiftc "$ROOT/.claude/skills/live-demo/tools/screens.swift" -o "$SCREENS" || {
    _red "failed to build screens"; exit 1; }
  ( cd "$ROOT/mac" && ./scripts/make-app.sh >/dev/null 2>&1 ) || { _red "build failed"; exit 1; }
  killall boxed 2>/dev/null; sleep 1
  rm -f "$LOG"
  open --env BOXED_CMD_HOOK=1 "$APP"
  osascript -e 'delay 1.2' >/dev/null
  grep -q "accessibilityTrusted=true" "$LOG" || { _red "boxed not Accessibility-trusted — grant it and retry"; exit 1; }
}

HIDDEN_APPS=()
_e2e_hide() {  # hide one process by name; remember it for restore; never aborts
  local app="$1"; [ -n "$app" ] || return 0
  case " ${HIDDEN_APPS[*]-} " in *" $app "*) ;; *) HIDDEN_APPS+=("$app") ;; esac
  osascript -e "tell application \"System Events\" to set visible of process \"$app\" to false" >/dev/null 2>&1
}

e2e_hide_others() {
  # Hide every visible foreground app except TextEdit, so only our test windows are
  # tileable. Two stages, because one un-hideable process used to abort the whole
  # pass (leaving e.g. VS Code visible → boxed tiled it too):
  #   1. collect the app names, then hide each INDEPENDENTLY (one failure can't kill
  #      the rest). (-e lines, not a heredoc — heredocs inside $() break bash 3.2.)
  #   2. sweep: whatever winz still shows that isn't TextEdit (Electron apps that
  #      resisted, late-openers) gets hidden by name, until only TextEdit remains.
  local names app left attempt
  names=$(osascript \
    -e 'tell application "System Events"' \
    -e 'set out to {}' \
    -e 'repeat with p in (every process whose background only is false and visible is true)' \
    -e 'if name of p is not "TextEdit" then set end of out to name of p' \
    -e 'end repeat' \
    -e 'return out' \
    -e 'end tell' 2>/dev/null)
  local arr; IFS=',' read -ra arr <<<"$names"
  for app in "${arr[@]:-}"; do _e2e_hide "${app# }"; done

  for attempt in 1 2 3 4 5; do
    left=$("$WINZ" | sed -nE 's/^.*\): (.+)  [0-9]+x[0-9]+ @.*/\1/p' | grep -v '^TextEdit$' | sort -u)
    [ -z "$left" ] && break
    while IFS= read -r app; do _e2e_hide "$app"; done <<<"$left"
    osascript -e 'delay 0.4' >/dev/null
  done
}

e2e_restore() {
  osascript -e 'tell application "TextEdit" to close every document saving no' >/dev/null 2>&1
  local app
  for app in "${HIDDEN_APPS[@]:-}"; do
    app="${app# }"  # AppleScript joins lists with ", " — trim the leading space
    [ -n "$app" ] && osascript -e "tell application \"System Events\" to set visible of process \"$app\" to true" >/dev/null 2>&1
  done
  killall boxed 2>/dev/null
  open "$APP" >/dev/null 2>&1  # relaunch in normal (hook-off) mode
}
trap e2e_restore EXIT

# Warp the cursor onto the built-in display (display 1) so `organize` targets it.
e2e_target() { "$WARP" 855 553 >/dev/null 2>&1; osascript -e 'delay 0.2' >/dev/null; }

# ── multi-display ──────────────────────────────────────────────────────────
# Display rects in CG global top-left coords (same space as winz/warp), as
# "X Y W H". e2e_rect secondary is empty when only one display is connected.
e2e_rect() { "$SCREENS" --cg | awk -v t="$1" '$3==t {print $4, $5, $6, $7; exit}'; }
e2e_has_secondary() { [ -n "$(e2e_rect secondary)" ]; }

# Center of a rect ("X Y W H") as "cx cy".
e2e_center() { awk '{print $1+$3/2, $2+$4/2}' <<<"$1"; }

# Warp the cursor onto the secondary display so `organize` targets it.
e2e_target_secondary() {
  local c; c=$(e2e_center "$(e2e_rect secondary)")
  "$WARP" $c >/dev/null 2>&1; osascript -e 'delay 0.2' >/dev/null
}

# Move the first tiled TextEdit window whose top-left x >= 0 (i.e. on a display
# right of the origin — the built-in here) to (x,y). Picks by position, not z-order,
# so it's stable across organizes. Used to drag a window onto the other display.
e2e_move_a_primary_window_to() {  # x y
  osascript \
    -e 'tell application "System Events" to tell process "TextEdit"' \
    -e 'repeat with w in windows' \
    -e 'set p to position of w' \
    -e 'if (item 1 of p) >= 0 then' \
    -e "set position of w to {$1, $2}" \
    -e 'exit repeat' \
    -e 'end if' \
    -e 'end repeat' \
    -e 'end tell' >/dev/null 2>&1
  osascript -e 'delay 0.5' >/dev/null
}

# Count test windows whose CENTER falls inside a rect ("X Y W H").
e2e_count_on() {  # X Y W H
  e2e_frames | awk -v rx="$1" -v ry="$2" -v rw="$3" -v rh="$4" '
    { cx=$3+$1/2; cy=$4+$2/2
      if (cx>=rx && cx<rx+rw && cy>=ry && cy<ry+rh) n++ }
    END { print n+0 }'
}

# Spawn N TextEdit documents, spread across the built-in display (display 1).
e2e_spawn() {
  local n="$1" i x y
  osascript -e 'tell application "TextEdit" to activate' >/dev/null 2>&1
  osascript -e 'tell application "TextEdit" to close every document saving no' >/dev/null 2>&1
  osascript -e 'delay 0.3' >/dev/null
  for ((i=0; i<n; i++)); do
    osascript -e 'tell application "TextEdit" to make new document' >/dev/null 2>&1
  done
  osascript -e 'delay 0.5' >/dev/null
  i=1
  for ((idx=0; idx<n; idx++)); do
    x=$((80 + idx*120)); y=$((80 + idx*90))
    osascript -e "tell application \"System Events\" to tell process \"TextEdit\" to set position of window $i to {$x, $y}" >/dev/null 2>&1
    i=$((i+1))
  done
  osascript -e 'delay 0.4' >/dev/null
}

e2e_cmd() { echo "$1" > "$CMD"; osascript -e "delay ${2:-1.2}" >/dev/null; }

# Frames of our test (TextEdit) windows as "W H X Y" lines (top-left coords).
# sed (not gawk's match-with-array, which BSD awk lacks).
e2e_frames() {
  "$WINZ" | sed -nE 's/.*TextEdit  ([0-9]+)x([0-9]+) @\(([0-9-]+),([0-9-]+)\).*/\1 \2 \3 \4/p'
}

# ── assertions ─────────────────────────────────────────────────────────────
assert_count() {  # assert_count N "msg"
  local got; got=$(e2e_frames | grep -c .)
  if [ "$got" -eq "$1" ]; then ok "$2 ($got windows)"; else bad "$2 (want $1, got $got)"; fi
}

assert_no_overlap() {  # no two test windows overlap by more than a gap's worth
  local bad_pairs
  bad_pairs=$(e2e_frames | awk '
    { w[NR]=$1; h[NR]=$2; x[NR]=$3; y[NR]=$4; n=NR }
    END {
      tol=12; bad=0
      for (i=1;i<=n;i++) for (j=i+1;j<=n;j++) {
        ox = (x[i] < x[j]+w[j]-tol) && (x[j] < x[i]+w[i]-tol)
        oy = (y[i] < y[j]+h[j]-tol) && (y[j] < y[i]+h[i]-tol)
        if (ox && oy) bad++
      }
      print bad
    }')
  if [ "${bad_pairs:-1}" -eq 0 ]; then ok "$1"; else bad "$1 ($bad_pairs overlapping pair(s))"; fi
}

assert_log() {  # assert_log "substring" "msg"  — searched since the last e2e_clearlog
  if grep -q "$1" "$LOG" 2>/dev/null; then
    ok "$2"
  else
    bad "$2 (log missing: $1)"
    grep -vE "on-screen:|  keep |  drop |tileable windows:" "$LOG" 2>/dev/null | tail -4 | sed 's/^/      · /'
  fi
}
assert_count_on() {  # assert_count_on "X Y W H" N "msg"
  local got; got=$(e2e_count_on $1)  # unquoted: split the rect into 4 args
  if [ "${got:-0}" -eq "$2" ]; then ok "$3 ($got)"; else bad "$3 (want $2, got ${got:-0})"; fi
}

assert_log_count() {  # assert_log_count "substring" N "msg"
  local got; got=$(grep -c "$1" "$LOG" 2>/dev/null)
  if [ "${got:-0}" -eq "$2" ]; then ok "$3"; else bad "$3 (want $2× '$1', got ${got:-0})"; fi
}

e2e_clearlog() { rm -f "$LOG"; }

summary() {
  printf '\n──────────\n'
  if [ "$FAIL" -eq 0 ]; then _grn "PASS — $PASS checks"; else _red "FAIL — $FAIL failed, $PASS passed"; fi
  return $FAIL
}
