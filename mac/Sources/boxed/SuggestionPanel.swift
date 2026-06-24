import AppKit

/// One offered action in the prompt: a label and what to do when clicked.
/// `keepsPanelOpen` buttons (Swap/Rebox) leave the pill up so it can be re-shown
/// with refreshed content instead of dismissing.
struct WindowSuggestion {
  let label: String
  let keepsPanelOpen: Bool
  let apply: () -> Void

  init(label: String, keepsPanelOpen: Bool = false, apply: @escaping () -> Void) {
    self.label = label
    self.keepsPanelOpen = keepsPanelOpen
    self.apply = apply
  }
}

/// A small, transient, tooltip-style prompt that appears near a newly-opened
/// window. Non-activating (never steals focus) and auto-dismisses if ignored —
/// so it never interrupts the normal macOS window workflow.
final class SuggestionPanel: NSObject {
  private var panel: NSPanel?
  private var dismissTimer: Timer?
  private var suggestions: [WindowSuggestion] = []

  /// How long the prompt lingers before quietly fading away.
  var timeout: TimeInterval = 9

  func present(
    title: String? = nil, _ suggestions: [WindowSuggestion], near anchor: CGRect,
    prominent: Bool = false
  ) {
    dismiss(animated: false)
    guard !suggestions.isEmpty else { return }
    self.suggestions = suggestions

    let content = buildContent(title: title, suggestions, prominent: prominent)
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

    panel.alphaValue = 1
    let placed = framePlacement(size: size, anchor: anchor)
    panel.setFrame(placed, display: true)
    panel.orderFrontRegardless()
    self.panel = panel
    Log.write("panel ordered front at \(NSStringFromRect(placed))")

    dismissTimer?.invalidate()
    dismissTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) {
      [weak self] _ in
      self?.dismiss()
    }
  }

  func dismiss(animated: Bool = true) {
    dismissTimer?.invalidate()
    dismissTimer = nil
    guard let panel else { return }
    self.panel = nil
    if animated {
      NSAnimationContext.runAnimationGroup(
        { context in
          context.duration = 0.35
          panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    } else {
      panel.orderOut(nil)
    }
  }

  // MARK: - Placement

  /// Center horizontally over the window, ride just inside its top edge, and
  /// clamp to the display so it never spills off-screen.
  private func framePlacement(size: NSSize, anchor: CGRect) -> CGRect {
    var x = anchor.midX - size.width / 2
    // Prefer floating just *above* the window's top edge.
    var y = anchor.maxY + 10

    let screen =
      NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main
    if let vf = screen?.visibleFrame {
      // No room above (near the top of the screen)? Tuck it just inside instead.
      if y + size.height > vf.maxY - 6 { y = anchor.maxY - size.height - 14 }
      x = min(max(x, vf.minX + 8), vf.maxX - size.width - 8)
      y = min(max(y, vf.minY + 8), vf.maxY - size.height - 8)
    }
    return CGRect(x: x, y: y, width: size.width, height: size.height)
  }

  // MARK: - View

  private func buildContent(title: String?, _ suggestions: [WindowSuggestion], prominent: Bool)
    -> NSView
  {
    let titleSize: CGFloat = prominent ? 16 : 12
    let buttonSize: CGFloat = prominent ? 14 : 11
    let controlSize: NSControl.ControlSize = prominent ? .large : .small
    let padV: CGFloat = prominent ? 11 : 7
    let padH: CGFloat = prominent ? 16 : 8

    let blur = NSVisualEffectView()
    blur.material = .hudWindow
    blur.state = .active
    blur.blendingMode = .behindWindow
    blur.wantsLayer = true
    blur.layer?.cornerRadius = prominent ? 15 : 11
    blur.layer?.masksToBounds = true

    let stack = NSStackView()
    stack.orientation = .horizontal
    stack.spacing = prominent ? 10 : 6
    stack.alignment = .centerY
    stack.edgeInsets = NSEdgeInsets(
      top: padV, left: title == nil ? padH - 4 : padH, bottom: padV, right: padH - 4)
    stack.translatesAutoresizingMaskIntoConstraints = false

    if let title {
      let label = NSTextField(labelWithString: title)
      label.font = .systemFont(ofSize: titleSize, weight: .semibold)
      label.textColor = .labelColor
      stack.addArrangedSubview(label)
    }

    for (index, suggestion) in suggestions.enumerated() {
      let button = NSButton(
        title: suggestion.label, target: self, action: #selector(suggestionClicked(_:)))
      button.tag = index
      button.bezelStyle = .rounded
      button.controlSize = controlSize
      button.font = .systemFont(ofSize: buttonSize, weight: .semibold)
      stack.addArrangedSubview(button)
    }

    let close = NSButton(title: "✕", target: self, action: #selector(closeClicked))
    close.bezelStyle = .rounded
    close.controlSize = controlSize
    close.font = .systemFont(ofSize: buttonSize, weight: .semibold)
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
    guard index >= 0, index < suggestions.count else { return }
    // Capture before apply() — apply may re-present and replace `suggestions`.
    let keepOpen = suggestions[index].keepsPanelOpen
    let action = suggestions[index].apply
    if !keepOpen { dismiss() }
    action()
  }

  @objc private func closeClicked() {
    dismiss()
  }
}
