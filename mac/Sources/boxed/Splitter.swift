import AppKit

/// A thin draggable bar that sits on a layout divider. Dragging it reports the
/// cursor's screen location so the window manager can resize the split live.
final class SplitterView: NSView {
  var vertical = true
  var onDragTo: ((CGPoint) -> Void)?
  var onEnd: (() -> Void)?

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func mouseDown(with event: NSEvent) {}  // claim the drag
  override func mouseDragged(with event: NSEvent) { onDragTo?(NSEvent.mouseLocation) }
  override func mouseUp(with event: NSEvent) { onEnd?() }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: vertical ? .resizeLeftRight : .resizeUpDown)
  }

  override func draw(_ dirtyRect: NSRect) {
    // A faint, rounded grab pill centered on the divider.
    let pill: NSRect =
      vertical
      ? NSRect(x: bounds.midX - 1.5, y: bounds.midY - 20, width: 3, height: 40)
      : NSRect(x: bounds.midX - 20, y: bounds.midY - 1.5, width: 40, height: 3)
    NSColor.white.withAlphaComponent(0.55).setFill()
    NSBezierPath(roundedRect: pill, xRadius: 1.5, yRadius: 1.5).fill()
  }
}

/// Manages the divider handle's non-activating panel — shown while editing a
/// layout, positioned on the primary split.
final class Splitter {
  private var panel: NSPanel?
  private let view = SplitterView()

  var onDragTo: ((CGPoint) -> Void)? {
    didSet { view.onDragTo = onDragTo }
  }
  var onEnd: (() -> Void)? {
    didSet { view.onEnd = onEnd }
  }

  func show(frame: CGRect, vertical: Bool) {
    view.vertical = vertical
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
