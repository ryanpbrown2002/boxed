import AppKit

/// A thin draggable bar that sits on a layout divider.
final class SplitterView: NSView {
  var vertical = true
  var onDown: (() -> Void)?

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func mouseDown(with event: NSEvent) { onDown?() }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: vertical ? .resizeLeftRight : .resizeUpDown)
  }

  override func draw(_ dirtyRect: NSRect) {
    let pill: NSRect =
      vertical
      ? NSRect(x: bounds.midX - 1.5, y: bounds.midY - 20, width: 3, height: 40)
      : NSRect(x: bounds.midX - 20, y: bounds.midY - 1.5, width: 40, height: 3)
    NSColor.white.withAlphaComponent(0.6).setFill()
    NSBezierPath(roundedRect: pill, xRadius: 1.5, yRadius: 1.5).fill()
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
