import AppKit

/// A small "hide" overlay button that sits in the top-right corner of a tiled
/// window while editing. Click it to pull that window out of the layout. Like the
/// divider handles, it's a non-activating panel so it never steals focus.
final class HideButtonView: NSView {
  var onClick: (() -> Void)?

  private var hovered = false
  private var trackingArea: NSTrackingArea?
  private static let accent = NSColor(srgbRed: 0.15, green: 0.55, blue: 1.0, alpha: 1)  // boxed blue

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func mouseDown(with event: NSEvent) { onClick?() }
  override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
  override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea { removeTrackingArea(trackingArea) }
    let area = NSTrackingArea(
      rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
    addTrackingArea(area)
    trackingArea = area
  }

  override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

  override func draw(_ dirtyRect: NSRect) {
    let r = bounds.insetBy(dx: 1, dy: 1)
    let pill = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)
    // A dark capsule that lights up blue on hover, so it reads on any window. At rest
    // a faint hairline keeps it legible on dark windows (where the fill blends in).
    (hovered ? Self.accent : NSColor(white: 0, alpha: 0.58)).setFill()
    pill.fill()
    if !hovered {
      NSColor(white: 1, alpha: 0.22).setStroke()
      pill.lineWidth = 1
      pill.stroke()
    }

    let text = "hide" as NSString
    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
      .foregroundColor: NSColor.white.withAlphaComponent(hovered ? 1 : 0.9),
    ]
    let size = text.size(withAttributes: attrs)
    text.draw(
      at: NSPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2), withAttributes: attrs)
  }
}

/// One pooled hide button (a non-activating panel that follows a window's corner).
final class HideButton {
  private var panel: NSPanel?
  private let view = HideButtonView()

  var onClick: (() -> Void)? {
    get { view.onClick }
    set { view.onClick = newValue }
  }

  func show(frame: CGRect) {
    let panel = self.panel ?? makePanel()
    panel.setFrame(frame, display: true)
    panel.orderFrontRegardless()
    panel.invalidateCursorRects(for: view)
    view.needsDisplay = true
    self.panel = panel
  }

  func hide() {
    panel?.orderOut(nil)
    panel = nil
  }

  private func makePanel() -> NSPanel {
    let panel = NSPanel(
      contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
      defer: false)
    panel.level = .floating
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.ignoresMouseEvents = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    panel.contentView = view
    return panel
  }
}
