import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private var statusItem: NSStatusItem!
  private var suggestItem: NSMenuItem!
  private var organizeItem: NSMenuItem!
  private var hotKeyMonitor: Any?
  private var rightClickMonitor: Any?
  private var dragSwapMonitor: Any?
  private let manager = WindowManager()
  private let suggestionPanel = SuggestionPanel()

  /// Up to six handles: internal split(s) + the four outer edges.
  private lazy var splitters: [Splitter] = (0..<6).map { tag in
    let splitter = Splitter(tag: tag)
    splitter.onDragTo = { [weak self] tag, point in
      self?.suggestionPanel.holdOpen()  // don't let edit mode fade mid-drag
      self?.manager.splitterDragBegan()
      self?.manager.setRatio(forDividerAt: tag, fromScreenPoint: point)
      self?.positionSplitters()  // handles follow the cursor live
    }
    splitter.onEnd = { [weak self] _ in
      self?.manager.splitterDragEnded()
      self?.positionSplitters()
      self?.suggestionPanel.restartTimer()  // restart the fade once the drag ends
    }
    return splitter
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    Log.write("launched. accessibilityTrusted=\(AXIsProcessTrusted())")
    setupMenu()
    requestAccessibility()

    manager.onNewWindow = { [weak self] anchor in
      self?.showOrganizePill(near: anchor)
    }
    // Drag-to-swap, the splitter, and auto-reflow are only live while editing.
    suggestionPanel.onDismiss = { [weak self] in
      self?.manager.editMode = false
      self?.endDragSwap()
      self?.splitters.forEach { $0.hide() }
    }
    // When a window opens/closes during edit mode, re-tile and refresh the pill.
    manager.onReorganized = { [weak self] name in self?.showAdjustPill(layoutName: name) }
    manager.start()
    installShortcuts()
    startCommandHook()
  }

  // MARK: - The organize flow

  /// Stage 1: the "Organize tabs" prompt near a new window. Clicking it tiles
  /// everything, then brings up the adjust pill.
  private func showOrganizePill(near anchor: CGRect) {
    let label = manager.isAlreadyOrganized() ? "✎  Edit tabs" : "⧉  Organize tabs"
    let organize = WindowSuggestion(label: label) { [weak self] in
      self?.organizeAndAdjust()
    }
    Log.write("presenting organize pill near \(NSStringFromRect(anchor))")
    suggestionPanel.present(title: nil, [organize], near: anchor)
  }

  /// Tile the windows, then (if any moved) show the adjust pill out of the way.
  private func organizeAndAdjust() {
    guard let name = manager.organizeOrEdit() else { return }
    showAdjustPill(layoutName: name)
  }

  /// Stage 2: a small pill that drops down under the menubar ▣ to tweak the
  /// arrangement. Rebox cycles to the next layout; swapping is by dragging a
  /// window onto another. Each press re-tiles and refreshes the pill (resets fade).
  private func showAdjustPill(layoutName: String) {
    manager.editMode = true
    beginDragSwap()
    positionSplitters()
    let rebox = WindowSuggestion(label: "▦ Rebox", keepsPanelOpen: true) { [weak self] in
      guard let self else { return }
      self.showAdjustPill(layoutName: self.manager.rebox() ?? layoutName)
    }
    suggestionPanel.present(title: nil, [rebox], near: menubarAnchor(), prominent: true)
  }

  /// A point just under the boxed menubar icon, so the pill reads as belonging to
  /// boxed and never covers the content area. Falls back to bottom-center.
  private func menubarAnchor() -> CGRect {
    if let frame = statusItem.button?.window?.frame {
      return CGRect(x: frame.midX, y: frame.minY, width: 0, height: 0)
    }
    return bottomCenterAnchor()
  }

  /// Place each divider handle on its split (hiding any unused handles).
  private func positionSplitters() {
    let dividers = manager.dividers()
    for (index, splitter) in splitters.enumerated() {
      if index < dividers.count {
        splitter.show(frame: dividers[index].frame, vertical: dividers[index].vertical)
      } else {
        splitter.hide()
      }
    }
  }

  /// A point at the bottom-center of the active display — keeps the pill clear of
  /// windows' top-right title-bar buttons.
  private func bottomCenterAnchor() -> CGRect {
    let vf = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
    return CGRect(x: vf.midX, y: vf.minY + 64, width: 0, height: 0)
  }

  // MARK: - Drag-to-swap (only while the adjust pill is up)

  /// While the adjust pill is showing, releasing a window dropped onto another
  /// swaps the two. Idempotent — safe to call on every adjust-pill present.
  private func beginDragSwap() {
    guard dragSwapMonitor == nil else { return }
    Log.write("drag-swap enabled")
    dragSwapMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) {
      [weak self] event in
      guard let self else { return }
      if event.type == .leftMouseDown {
        self.suggestionPanel.holdOpen()  // pause the fade while a drag is in progress
        return
      }
      // Let the dragged window settle into its final position first.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
        if let name = self.manager.handleWindowDropped() {
          self.showAdjustPill(layoutName: name)  // re-snap + reset the fade
        } else {
          self.suggestionPanel.restartTimer()  // nothing moved — just restart the fade
        }
      }
    }
  }

  private func endDragSwap() {
    guard let monitor = dragSwapMonitor else { return }
    NSEvent.removeMonitor(monitor)
    dragSwapMonitor = nil
    Log.write("drag-swap disabled")
  }

  // MARK: - Test hook (dev only)

  /// Polls /tmp/boxed-cmd so a script can drive boxed for automated testing:
  ///   echo organize > /tmp/boxed-cmd   (also: rebox, swap, dismiss)
  /// Lets changes be exercised against real windows without manual clicks.
  private func startCommandHook() {
    let path = "/tmp/boxed-cmd"
    Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
      guard let self,
        let raw = try? String(contentsOfFile: path, encoding: .utf8)
      else { return }
      let cmd = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !cmd.isEmpty else { return }
      try? "".write(toFile: path, atomically: true, encoding: .utf8)
      Log.write("cmd: \(cmd)")
      switch cmd {
      case "organize": self.organizeAndAdjust()
      case "rebox": if let name = self.manager.rebox() { self.showAdjustPill(layoutName: name) }
      case "swap": if let name = self.manager.swap() { self.showAdjustPill(layoutName: name) }
      case "drop": if let name = self.manager.handleWindowDropped() { self.showAdjustPill(layoutName: name) }
      case "dismiss": self.suggestionPanel.dismiss()
      default:
        if cmd.hasPrefix("ratio "), let v = Double(cmd.dropFirst(6)) {
          self.manager.setRatios(primary: CGFloat(v), stack: nil)
        } else if cmd.hasPrefix("stack "), let v = Double(cmd.dropFirst(6)) {
          self.manager.setRatios(primary: nil, stack: CGFloat(v))
        } else if cmd.hasPrefix("inset ") {
          let parts = cmd.dropFirst(6).split(separator: " ")
          if parts.count == 2, let v = Double(parts[1]) {
            self.manager.setInset(String(parts[0]), CGFloat(v))
          }
        }
      }
    }
  }

  // MARK: - Menubar

  private func setupMenu() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.title = "▣"

    let menu = NSMenu()
    menu.delegate = self  // refresh the organize item each time the menu opens
    menu.autoenablesItems = false

    organizeItem = NSMenuItem(
      title: "Organize tabs now", action: #selector(organizeNow), keyEquivalent: "t")
    organizeItem.keyEquivalentModifierMask = [.command, .option]
    organizeItem.target = self
    menu.addItem(organizeItem)

    menu.addItem(.separator())

    suggestItem = NSMenuItem(
      title: "Offer to organize on new windows", action: #selector(toggleSuggest), keyEquivalent: "")
    suggestItem.target = self
    suggestItem.state = manager.suggestNewWindows ? .on : .off
    menu.addItem(suggestItem)

    let hint = NSMenuItem(title: "Tip: ⌥ right-click anywhere to summon", action: nil, keyEquivalent: "")
    hint.isEnabled = false
    menu.addItem(hint)

    menu.addItem(.separator())

    menu.addItem(
      NSMenuItem(
        title: "Quit boxed", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

    statusItem.menu = menu
  }

  /// Keep the organize item in step with what's on screen: disabled when there
  /// are no windows to act on, and labeled "Edit tabs" when they're already tiled.
  func menuNeedsUpdate(_ menu: NSMenu) {
    let count = manager.tileableCount()
    organizeItem.isEnabled = count >= 1
    organizeItem.title = manager.isAlreadyOrganized() ? "Edit tabs" : "Organize tabs now"
  }

  @objc private func toggleSuggest() {
    manager.suggestNewWindows.toggle()
    suggestItem.state = manager.suggestNewWindows ? .on : .off
  }

  @objc private func organizeNow() {
    organizeAndAdjust()
  }

  // MARK: - Permissions

  private func requestAccessibility() {
    // String value of kAXTrustedCheckOptionPrompt — used directly to avoid
    // Unmanaged<CFString> bridging friction across SDK versions.
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    if !AXIsProcessTrustedWithOptions(options) {
      Log.write("Accessibility not yet granted — prompted. Grant it, then relaunch.")
    }
  }

  // MARK: - Shortcuts

  private func installShortcuts() {
    // ⌥⌘T — organize immediately, from anywhere.
    hotKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      if mods == [.command, .option], event.charactersIgnoringModifiers?.lowercased() == "t" {
        self?.organizeAndAdjust()
      }
    }

    // ⌥ right-click anywhere — summon the organize pill at the cursor. Gated on
    // the Option key so ordinary right-clicks / context menus are untouched.
    rightClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) {
      [weak self] event in
      let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      guard mods.contains(.option) else { return }
      let point = NSEvent.mouseLocation
      self?.showOrganizePill(near: CGRect(x: point.x, y: point.y, width: 0, height: 0))
    }
  }
}
