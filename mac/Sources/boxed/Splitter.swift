import AppKit

/// A draggable grip that sits on a layout divider. Drawn as a subtle frosted
/// capsule with a grip line — reads on light or dark windows, and lights up in
/// boxed's accent on hover.
final class SplitterView: NSView {
  var vertical = true
  var onDown: (() -> Void)?

  private var hovered = false
  private var trackingArea: NSTrackingArea?

  private static let accent = NSColor(srgbRed: 0.78, green: 1.0, blue: 0.23, alpha: 1)

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func mouseDown(with event: NSEvent) { onDown?() }
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

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: vertical ? .resizeLeftRight : .resizeUpDown)
  }

  override func draw(_ dirtyRect: NSRect) {
    // A rounded "pill" for the long axis: a dark base (contrast on any window)
    // with a lighter grip on top.
    func capsule(thickness: CGFloat, length: CGFloat) -> NSBezierPath {
      let r =
        vertical
        ? NSRect(x: bounds.midX - thickness / 2, y: bounds.midY - length / 2, width: thickness, height: length)
        : NSRect(x: bounds.midX - length / 2, y: bounds.midY - thickness / 2, width: length, height: thickness)
      return NSBezierPath(roundedRect: r, xRadius: thickness / 2, yRadius: thickness / 2)
    }

    NSColor(white: 0, alpha: hovered ? 0.4 : 0.22).setFill()
    capsule(thickness: 7, length: hovered ? 52 : 44).fill()

    (hovered ? Self.accent : NSColor(white: 1, alpha: 0.75)).setFill()
    capsule(thickness: 3, length: hovered ? 30 : 24).fill()
  }
}

/// One divider handle. Drag tracking uses event monitors (not the panel's own
/// mouse events) so the handle can be repositioned to follow the cursor mid-drag
/// without the OS dropping the drag.
final class Splitter {
  let tag: Int
  private var panel: NSPanel?
  private let view = SplitterView()
  private var localMonitor: Any?
  private var globalMonitor: Any?

  /// (tag, cursor location in screen/Cocoa coords) on each drag move.
  var onDragTo: ((Int, CGPoint) -> Void)?
  var onEnd: ((Int) -> Void)?

  init(tag: Int) {
    self.tag = tag
    view.onDown = { [weak self] in self?.beginTracking() }
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
    endTracking()
    panel?.orderOut(nil)
    panel = nil
  }

  private func beginTracking() {
    endTracking()
    localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) {
      [weak self] event in
      self?.handle(event)
      return event
    }
    globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) {
      [weak self] event in
      self?.handle(event)
    }
  }

  private func handle(_ event: NSEvent) {
    if event.type == .leftMouseUp {
      onEnd?(tag)
      endTracking()
    } else {
      onDragTo?(tag, NSEvent.mouseLocation)
    }
  }

  private func endTracking() {
    if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
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
