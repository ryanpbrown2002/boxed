import AppKit

/// One offered action in the prompt: a label and what to do when clicked.
struct WindowSuggestion {
  let label: String
  let apply: () -> Void
}

/// A small, transient, tooltip-style prompt that appears near a newly-opened
/// window. Non-activating (never steals focus) and auto-dismisses if ignored —
/// so it never interrupts the normal macOS window workflow.
final class SuggestionPanel: NSObject {
  private var panel: NSPanel?
  private var dismissTimer: Timer?
  private var suggestions: [WindowSuggestion] = []

  /// How long the prompt lingers before quietly disappearing.
  var timeout: TimeInterval = 5

  func present(_ suggestions: [WindowSuggestion], near anchor: CGRect) {
    dismiss()
    guard !suggestions.isEmpty else { return }
    self.suggestions = suggestions

    let content = buildContent(suggestions)
    content.layoutSubtreeIfNeeded()
    let size = content.fittingSize

    let panel = NSPanel(
      contentRect: CGRect(origin: .zero, size: size),
      styleMask: [.nonactivatingPanel, .borderless],
      backing: .buffered,
      defer: false)
    panel.level = .floating
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.isMovable = false
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    panel.contentView = content

    panel.setFrame(framePlacement(size: size, anchor: anchor), display: true)
    panel.orderFrontRegardless()
    self.panel = panel

    dismissTimer?.invalidate()
    dismissTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) {
      [weak self] _ in
      self?.dismiss()
    }
  }

  func dismiss() {
    dismissTimer?.invalidate()
    dismissTimer = nil
    panel?.orderOut(nil)
    panel = nil
  }

  // MARK: - Placement

  /// Center horizontally over the window, ride just inside its top edge, and
  /// clamp to the display so it never spills off-screen.
  private func framePlacement(size: NSSize, anchor: CGRect) -> CGRect {
    var x = anchor.midX - size.width / 2
    var y = anchor.maxY - size.height - 14

    let screen =
      NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main
    if let vf = screen?.visibleFrame {
      x = min(max(x, vf.minX + 8), vf.maxX - size.width - 8)
      y = min(max(y, vf.minY + 8), vf.maxY - size.height - 8)
    }
    return CGRect(x: x, y: y, width: size.width, height: size.height)
  }

  // MARK: - View

  private func buildContent(_ suggestions: [WindowSuggestion]) -> NSView {
    let blur = NSVisualEffectView()
    blur.material = .hudWindow
    blur.state = .active
    blur.blendingMode = .behindWindow
    blur.wantsLayer = true
    blur.layer?.cornerRadius = 11
    blur.layer?.masksToBounds = true

    let stack = NSStackView()
    stack.orientation = .horizontal
    stack.spacing = 6
    stack.alignment = .centerY
    stack.edgeInsets = NSEdgeInsets(top: 7, left: 12, bottom: 7, right: 8)
    stack.translatesAutoresizingMaskIntoConstraints = false

    let label = NSTextField(labelWithString: "Snap into layout?")
    label.font = .systemFont(ofSize: 12, weight: .medium)
    label.textColor = .secondaryLabelColor
    stack.addArrangedSubview(label)

    for (index, suggestion) in suggestions.enumerated() {
      let button = NSButton(
        title: suggestion.label, target: self, action: #selector(suggestionClicked(_:)))
      button.tag = index
      button.bezelStyle = .rounded
      button.controlSize = .small
      button.font = .systemFont(ofSize: 11, weight: .semibold)
      stack.addArrangedSubview(button)
    }

    let close = NSButton(title: "✕", target: self, action: #selector(closeClicked))
    close.bezelStyle = .rounded
    close.controlSize = .small
    stack.addArrangedSubview(close)

    blur.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
      stack.topAnchor.constraint(equalTo: blur.topAnchor),
      stack.bottomAnchor.constraint(equalTo: blur.bottomAnchor)
    ])
    blur.frame = CGRect(origin: .zero, size: stack.fittingSize)
    return blur
  }

  @objc private func suggestionClicked(_ sender: NSButton) {
    let index = sender.tag
    if index >= 0, index < suggestions.count {
      suggestions[index].apply()
    }
    dismiss()
  }

  @objc private func closeClicked() {
    dismiss()
  }
}
