import CoreGraphics

/// Binary-space-partition tiling — the fallback when a window count has no
/// hand-tuned layout (5+ windows).
public enum Layout {
  /// Split `rect` among `count` windows BSP-style and return a frame per window,
  /// splitting along the longer axis at each level so the result stays balanced.
  public static func bsp(count: Int, in rect: CGRect, gap: CGFloat = 8) -> [CGRect] {
    guard count > 0, rect.width > 0, rect.height > 0 else { return [] }
    var frames = [CGRect](repeating: .zero, count: count)
    split(Array(0..<count), rect, &frames)
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
