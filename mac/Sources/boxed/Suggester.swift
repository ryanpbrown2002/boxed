import CoreGraphics

/// A candidate placement for a newly-opened window. Pure geometry — the offered
/// options adapt to what's already on screen.
struct Placement: Equatable {
  let label: String
  /// Where the new window should go.
  let newFrame: CGRect
  /// If non-nil, the suggestion also repositions the dominant existing window
  /// (e.g. "split" pushes it to the other half).
  let incumbentFrame: CGRect?
}

enum Suggester {
  /// Fraction of the screen a single window must cover to count as "dominant"
  /// and trigger split suggestions instead of plain quick-snaps.
  static let dominantCoverage: CGFloat = 0.6

  /// Build a short, context-aware list of placements for a new window.
  /// - `usable`: the usable area of the window's display.
  /// - `incumbent`: frame of the largest existing window on that display, if any.
  static func placements(usable: CGRect, incumbent: CGRect?, gap: CGFloat = 8) -> [Placement] {
    guard usable.width > 0, usable.height > 0 else { return [] }

    let halfW = (usable.width - gap) / 2
    let left = CGRect(x: usable.minX, y: usable.minY, width: halfW, height: usable.height)
    let right = CGRect(
      x: usable.minX + halfW + gap, y: usable.minY, width: halfW, height: usable.height)

    if let inc = incumbent,
      inc.width * inc.height >= dominantCoverage * usable.width * usable.height
    {
      // One window already fills the screen — offer to split it with the newcomer.
      return [
        Placement(label: "Split ▸", newFrame: right, incumbentFrame: left),
        Placement(label: "◂ Split", newFrame: left, incumbentFrame: right)
      ]
    }

    // Otherwise just offer quick spots for the new window; touch nothing else.
    return [
      Placement(label: "◧ Left", newFrame: left, incumbentFrame: nil),
      Placement(label: "Right ◨", newFrame: right, incumbentFrame: nil),
      Placement(label: "Fill", newFrame: usable, incumbentFrame: nil)
    ]
  }
}
