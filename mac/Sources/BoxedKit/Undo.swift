/// Policy for the single-level "undo the organize" snapshot. Pure so it can be
/// unit-tested; the actual frame capture/restore is AX work in `WindowManager`.
public enum Undo {
  /// Whether to (over)write the undo snapshot. Capture only for a *genuinely new*
  /// arrangement — there's no session for this display yet, or the set of windows
  /// being organized differs from the one already tiled. Re-snapping, reformatting
  /// or resetting the *same* set must NOT overwrite the snapshot, so Undo always
  /// reverts to where the windows were before they were first organized.
  public static func shouldCapture(hasSession: Bool, sameWindowSet: Bool) -> Bool {
    !hasSession || !sameWindowSet
  }
}
