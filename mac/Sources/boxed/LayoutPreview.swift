import AppKit
import BoxedKit

/// Draws a tiny diagram of a layout — a rounded "screen" with a box per slot —
/// for the Reformat control, so the user sees the arrangement instead of reading a
/// name like "Main + stack". The slot geometry comes from `Tiling.slots` (pure,
/// tested); this only paints it.
enum LayoutPreview {
  static func image(
    kind: LayoutKind, count: Int, ratio: CGFloat, stackRatio: CGFloat, size: NSSize
  ) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()
    defer { image.unlockFocus() }

    let bounds = NSRect(origin: .zero, size: size)
    // The "screen": a faint rounded backdrop the boxes sit inside.
    let screen = bounds.insetBy(dx: 1, dy: 1)
    let backdrop = NSBezierPath(roundedRect: screen, xRadius: 3, yRadius: 3)
    NSColor(white: 1, alpha: 0.16).setFill()
    backdrop.fill()

    // Slot rects in the screen's coordinate space. Tiling uses a top-left origin
    // (y grows down); flip to AppKit's bottom-left for drawing so the diagram
    // matches what's on screen (main on the left, stack top/bottom, etc).
    let inner = screen.insetBy(dx: 1.5, dy: 1.5)
    let slots = Tiling.slots(
      kind, count: max(count, 1), in: inner, gap: 1.5, ratio: ratio, stackRatio: stackRatio)
    NSColor(srgbRed: 0.62, green: 0.82, blue: 1.0, alpha: 0.95).setFill()  // boxed light blue
    for slot in slots {
      let flipped = NSRect(
        x: slot.minX, y: inner.maxY - (slot.minY - inner.minY) - slot.height,
        width: slot.width, height: slot.height)
      NSBezierPath(roundedRect: flipped, xRadius: 1.5, yRadius: 1.5).fill()
    }
    return image
  }

  /// Convenience for the active layout (nil → a neutral placeholder box).
  static func image(
    for layout: (kind: LayoutKind, count: Int, ratio: CGFloat, stackRatio: CGFloat)?, size: NSSize
  ) -> NSImage {
    guard let l = layout else {
      return image(kind: .columns, count: 1, ratio: 0.5, stackRatio: 0.5, size: size)
    }
    return image(kind: l.kind, count: l.count, ratio: l.ratio, stackRatio: l.stackRatio, size: size)
  }
}
