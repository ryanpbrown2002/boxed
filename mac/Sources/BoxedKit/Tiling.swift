import CoreGraphics
import Foundation

/// The named layout shapes boxed can arrange windows into.
public enum LayoutKind: Equatable {
  case columns  // equal columns, left → right
  case rows  // equal rows, top → bottom
  case grid  // near-square grid, row-major
  case mainLeft  // one big window on the left, the rest stacked on the right
  case mainTop  // one big window on top, the rest in a row below
  case bsp  // binary-space-partition fallback (5+ windows)
}

/// Pure layout math. All rects use a top-left origin (y grows downward), matching
/// the Accessibility API's coordinate space. No window/AppKit APIs here, so it is
/// fully unit-testable.
public enum Tiling {
  /// The ordered layout options offered for a given window count. "Rebox" cycles
  /// through this list; the first entry is the default.
  public static func layouts(for count: Int) -> [LayoutKind] {
    switch count {
    case ..<1: return []
    case 1: return [.columns]
    case 2: return [.columns, .rows]
    case 3: return [.columns, .rows, .mainLeft, .mainTop]
    case 4: return [.grid, .columns, .rows, .mainLeft]
    default: return [.bsp]
    }
  }

  /// A short human label for a layout, given the window count (so two windows read
  /// as "Left / Right" rather than the generic "Columns").
  public static func name(_ kind: LayoutKind, count: Int) -> String {
    switch kind {
    case .columns: return count <= 1 ? "Full" : (count == 2 ? "Left / Right" : "Columns")
    case .rows: return count == 2 ? "Top / Bottom" : "Rows"
    case .grid: return "Grid"
    case .mainLeft: return "Main + stack"
    case .mainTop: return "Main + row"
    case .bsp: return "Auto"
    }
  }

  /// The ordered slot rectangles for `count` windows under `kind`, within `rect`,
  /// separated by `gap`. Always returns exactly `count` rects.
  public static func slots(_ kind: LayoutKind, count: Int, in rect: CGRect, gap: CGFloat = 8)
    -> [CGRect]
  {
    guard count > 0, rect.width > 0, rect.height > 0 else { return [] }
    switch kind {
    case .bsp:
      return Layout.bsp(count: count, in: rect, gap: gap)  // already gap-inset
    case .columns:
      return inset(columns(count, rect), by: gap)
    case .rows:
      return inset(rows(count, rect), by: gap)
    case .grid:
      return inset(grid(count, rect), by: gap)
    case .mainLeft:
      return inset(mainLeft(count, rect), by: gap)
    case .mainTop:
      return inset(mainTop(count, rect), by: gap)
    }
  }

  // MARK: - partitions (exact, no gap)

  static func columns(_ n: Int, _ r: CGRect) -> [CGRect] {
    let w = r.width / CGFloat(n)
    return (0..<n).map {
      CGRect(x: r.minX + CGFloat($0) * w, y: r.minY, width: w, height: r.height)
    }
  }

  static func rows(_ n: Int, _ r: CGRect) -> [CGRect] {
    let h = r.height / CGFloat(n)
    return (0..<n).map {
      CGRect(x: r.minX, y: r.minY + CGFloat($0) * h, width: r.width, height: h)
    }
  }

  static func grid(_ n: Int, _ r: CGRect) -> [CGRect] {
    let cols = max(1, Int(ceil(Double(n).squareRoot())))
    let rowCount = max(1, Int(ceil(Double(n) / Double(cols))))
    let cw = r.width / CGFloat(cols)
    let ch = r.height / CGFloat(rowCount)
    return (0..<n).map { i in
      let col = i % cols
      let row = i / cols
      return CGRect(x: r.minX + CGFloat(col) * cw, y: r.minY + CGFloat(row) * ch, width: cw, height: ch)
    }
  }

  static func mainLeft(_ n: Int, _ r: CGRect) -> [CGRect] {
    guard n > 1 else { return [r] }
    let half = r.width / 2
    var out = [CGRect(x: r.minX, y: r.minY, width: half, height: r.height)]
    let h = r.height / CGFloat(n - 1)
    for j in 0..<(n - 1) {
      out.append(CGRect(x: r.minX + half, y: r.minY + CGFloat(j) * h, width: r.width - half, height: h))
    }
    return out
  }

  static func mainTop(_ n: Int, _ r: CGRect) -> [CGRect] {
    guard n > 1 else { return [r] }
    let half = r.height / 2
    var out = [CGRect(x: r.minX, y: r.minY, width: r.width, height: half)]
    let w = r.width / CGFloat(n - 1)
    for j in 0..<(n - 1) {
      out.append(CGRect(x: r.minX + CGFloat(j) * w, y: r.minY + half, width: w, height: r.height - half))
    }
    return out
  }

  private static func inset(_ rects: [CGRect], by gap: CGFloat) -> [CGRect] {
    rects.map { $0.insetBy(dx: gap / 2, dy: gap / 2) }
  }
}
