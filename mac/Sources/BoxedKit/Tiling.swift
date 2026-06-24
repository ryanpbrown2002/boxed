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
    case 3: return [.mainLeft, .columns, .rows, .mainTop]
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

  /// Where a window goes within its slot. A **resizable** window fills the slot
  /// exactly (the core tiling behavior). A **non-resizable** window can't be
  /// stretched, so it keeps its natural size, anchored to the slot's top-right
  /// (top-left origin) and capped to the slot.
  public static func placement(slot: CGRect, natural: CGSize, resizable: Bool) -> CGRect {
    guard !resizable, natural.width > 0, natural.height > 0 else { return slot }
    let w = min(natural.width, slot.width)
    let h = min(natural.height, slot.height)
    return CGRect(x: slot.maxX - w, y: slot.minY, width: w, height: h)
  }

  /// Smallest fraction either side of an adjustable split may shrink to.
  public static let minRatio: CGFloat = 0.1

  /// Clamp a split ratio so neither side collapses.
  public static func clampRatio(_ r: CGFloat) -> CGFloat {
    min(max(r, minRatio), 1 - minRatio)
  }

  /// The ordered slot rectangles for `count` windows under `kind`, within `rect`,
  /// separated by `gap`. Always returns exactly `count` rects.
  ///
  /// `ratio` sizes the layout's *primary* split (the draggable edge): the
  /// left/right divide for Left-Right, top/bottom for Top-Bottom, and the
  /// main-vs-stack divide for Main + stack / row. It's ignored by layouts without
  /// a single primary split (even Columns/Rows of 3+, Grid, BSP).
  public static func slots(
    _ kind: LayoutKind, count: Int, in rect: CGRect, gap: CGFloat = 8, ratio: CGFloat = 0.5,
    stackRatio: CGFloat = 0.5
  ) -> [CGRect] {
    guard count > 0, rect.width > 0, rect.height > 0 else { return [] }
    switch kind {
    case .bsp:
      return Layout.bsp(count: count, in: rect, gap: gap)  // already gap-inset
    case .columns:
      return inset(count == 2 ? twoSplit(rect, ratio: ratio, vertical: true) : columns(count, rect), by: gap)
    case .rows:
      return inset(count == 2 ? twoSplit(rect, ratio: ratio, vertical: false) : rows(count, rect), by: gap)
    case .grid:
      return inset(grid(count, rect), by: gap)
    case .mainLeft:
      return inset(mainLeft(count, rect, ratio: ratio, stackRatio: stackRatio), by: gap)
    case .mainTop:
      return inset(mainTop(count, rect, ratio: ratio, stackRatio: stackRatio), by: gap)
    }
  }

  static func twoSplit(_ r: CGRect, ratio: CGFloat, vertical: Bool) -> [CGRect] {
    if vertical {
      let w = r.width * ratio
      return [
        CGRect(x: r.minX, y: r.minY, width: w, height: r.height),
        CGRect(x: r.minX + w, y: r.minY, width: r.width - w, height: r.height)
      ]
    } else {
      let h = r.height * ratio
      return [
        CGRect(x: r.minX, y: r.minY, width: r.width, height: h),
        CGRect(x: r.minX, y: r.minY + h, width: r.width, height: r.height - h)
      ]
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

  static func mainLeft(_ n: Int, _ r: CGRect, ratio: CGFloat = 0.5, stackRatio: CGFloat = 0.5)
    -> [CGRect]
  {
    guard n > 1 else { return [r] }
    let mainW = r.width * ratio
    let stackX = r.minX + mainW
    let stackW = r.width - mainW
    var out = [CGRect(x: r.minX, y: r.minY, width: mainW, height: r.height)]
    if n - 1 == 2 {  // two-window stack: the divider is adjustable
      let h0 = r.height * stackRatio
      out.append(CGRect(x: stackX, y: r.minY, width: stackW, height: h0))
      out.append(CGRect(x: stackX, y: r.minY + h0, width: stackW, height: r.height - h0))
    } else {
      let h = r.height / CGFloat(n - 1)
      for j in 0..<(n - 1) {
        out.append(CGRect(x: stackX, y: r.minY + CGFloat(j) * h, width: stackW, height: h))
      }
    }
    return out
  }

  static func mainTop(_ n: Int, _ r: CGRect, ratio: CGFloat = 0.5, stackRatio: CGFloat = 0.5)
    -> [CGRect]
  {
    guard n > 1 else { return [r] }
    let mainH = r.height * ratio
    let stackY = r.minY + mainH
    let stackH = r.height - mainH
    var out = [CGRect(x: r.minX, y: r.minY, width: r.width, height: mainH)]
    if n - 1 == 2 {
      let w0 = r.width * stackRatio
      out.append(CGRect(x: r.minX, y: stackY, width: w0, height: stackH))
      out.append(CGRect(x: r.minX + w0, y: stackY, width: r.width - w0, height: stackH))
    } else {
      let w = r.width / CGFloat(n - 1)
      for j in 0..<(n - 1) {
        out.append(CGRect(x: r.minX + CGFloat(j) * w, y: stackY, width: w, height: stackH))
      }
    }
    return out
  }

  private static func inset(_ rects: [CGRect], by gap: CGFloat) -> [CGRect] {
    rects.map { $0.insetBy(dx: gap / 2, dy: gap / 2) }
  }
}
