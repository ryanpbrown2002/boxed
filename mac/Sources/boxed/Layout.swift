import CoreGraphics

/// Pure tiling math. No window APIs here so it can be reasoned about and tested
/// in isolation. Everything else in the app feeds rects from this.
enum Layout {
  /// Split `rect` among `count` windows binary-space-partition style and return a
  /// frame per window. Splits along the longer axis at each level so the result
  /// stays balanced.
  ///
  /// Reflow is free: because frames are recomputed purely from the *current*
  /// window count, opening a window re-splits a region and closing one lets its
  /// neighbours reclaim the space — no tree state to keep in sync.
  static func bsp(count: Int, in rect: CGRect, gap: CGFloat = 8) -> [CGRect] {
    guard count > 0, rect.width > 0, rect.height > 0 else { return [] }
    var frames = [CGRect](repeating: .zero, count: count)
    split(Array(0..<count), rect, &frames)
    // Inset every leaf by half the gap; adjacent leaves then sit a full gap apart.
    return frames.map { $0.insetBy(dx: gap / 2, dy: gap / 2) }
  }

  private static func split(_ indices: [Int], _ rect: CGRect, _ frames: inout [CGRect]) {
    if indices.count == 1 {
      frames[indices[0]] = rect
      return
    }
    let mid = indices.count / 2
    let first = Array(indices[..<mid])
    let second = Array(indices[mid...])
    let firstShare = CGFloat(first.count) / CGFloat(indices.count)

    if rect.width >= rect.height {
      let w = rect.width * firstShare
      split(first, CGRect(x: rect.minX, y: rect.minY, width: w, height: rect.height), &frames)
      let rest = CGRect(x: rect.minX + w, y: rect.minY, width: rect.width - w, height: rect.height)
      split(second, rest, &frames)
    } else {
      let h = rect.height * firstShare
      split(first, CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: h), &frames)
      let rest = CGRect(x: rect.minX, y: rect.minY + h, width: rect.width, height: rect.height - h)
      split(second, rest, &frames)
    }
  }
}
