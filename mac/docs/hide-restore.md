# Spec: discoverable, non-destructive restore for hidden windows

Follow-up to the hide feature, addressing the UX eval. The hide button itself is
good; the gap is **getting windows back**.

## Problem (from the eval)

- **P1 — restore is one-way and lossy.** The only way to un-hide is ↺ Reset, which
  also discards every layout tweak (ratios, insets). "I hid one window, I want it
  back" shouldn't cost the whole arrangement.
- **P2 — no feedback.** After hiding, nothing says a window is set aside vs. closed,
  or how to recover it.

Both are solved by one small control.

## Design

- When the edited display has hidden windows, the pill shows a single compact
  **"show N hidden"** button (e.g. `show 2 hidden`). It is *one* button regardless of
  count — so it doesn't re-introduce the per-window chips that cluttered the pill —
  and it doubles as the feedback (you can always see how many are set aside).
- Clicking it **restores all hidden windows into the layout, preserving the current
  ratios/insets** (unlike Reset, which re-fills from scratch). `WindowManager`:
  - `restoreHidden()` — move `hidden` → `windows`, re-tile, keep tweaks.
  - `hiddenCount()` — for the label.
- The per-window **"hide"** button and its label stay as-is (your call). The
  "show N hidden" control makes the model legible — the windows are *hidden, not
  closed* — which also softens the macOS ⌘H ("hide app") ambiguity without a rename.
- Small visual tidy on the hide button: slightly more translucent resting fill +
  a hairline so it reads on dark windows (eval P4).

## Deferred (with reason)

- **Per-window selective restore** — that's the chips you removed; "show N hidden"
  (restore all) is the compact alternative. Revisit only if restore-all proves blunt.
- **⌘-Tab leak** — a hidden window is a real window, so the app switcher can surface
  it; the next re-tile re-parks it. Live with it for now.
- **Rename "hide"** — keeping your chosen label.

## Testing

Restore is session/AX behavior → verified via live demos:
1. hide one → `show 1 hidden` appears → click → it returns; tweaks kept.
2. hide several → `show 3 hidden` → click → all return.
3. hide, drag a divider (tweak ratio), then `show N hidden` → window returns AND the
   tweaked ratio is preserved (vs. Reset which would reset it).
4. hide, re-organize → stays hidden, indicator persists.
5. Reset still brings everything back and clears the indicator.
