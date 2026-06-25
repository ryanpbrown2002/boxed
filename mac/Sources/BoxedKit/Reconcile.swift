/// Pure cross-display reconciliation: decide which windows belong to which
/// "boxed" display after windows have moved. Windows and displays are plain Ints
/// so this is fully unit-testable; the app maps its real windows/displays onto it.
public enum Reconcile {
  /// - sessions: each boxed display's current window list (`display -> [window]`).
  /// - current:  where each window is right now (`window -> display`); a window
  ///             absent from this map is on no relevant display.
  /// - previous: where each window was at the last check (`window -> display`).
  ///
  /// Rules: a window that left its session's display is dropped; a window that
  /// *moved* onto a boxed display (its display changed) joins that display. A
  /// brand-new window (no `previous`) does not auto-join. Emptied displays drop out.
  public static func step(
    sessions: [Int: [Int]], current: [Int: Int], previous: [Int: Int]
  ) -> [Int: [Int]] {
    var result: [Int: [Int]] = [:]
    for (display, windows) in sessions {
      result[display] = windows.filter { current[$0] == display }  // still here
    }
    let boxed = Set(sessions.keys)
    for window in current.keys.sorted() {
      guard let now = current[window], boxed.contains(now) else { continue }
      if result[now]?.contains(window) == true { continue }
      if let was = previous[window], was != now {  // genuinely moved here
        result[now, default: []].append(window)
      }
    }
    return result.filter { !$0.value.isEmpty }
  }
}
