import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private var statusItem: NSStatusItem!
  private var organizeItem: NSMenuItem!
  private var hotKeyMonitor: Any?
  private var rightClickMonitor: Any?
  private var dragSwapMonitor: Any?
  private var reconcileMonitor: Any?
  private let manager = WindowManager()
  private let suggestionPanel = SuggestionPanel()

  /// Handles: internal split(s) + left/right edges + per-window top/bottom.
  private lazy var splitters: [Splitter] = (0..<16).map { tag in
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

  /// A "hide" button overlaid on each tiled window's top-right corner while editing.
  private lazy var hideButtons: [HideButton] = (0..<16).map { _ in HideButton() }

  func applicationDidFinishLaunching(_ notification: Notification) {
    Log.write("launched. accessibilityTrusted=\(AXIsProcessTrusted())")
    setupMenu()
    requestAccessibility()

    // Drag-to-swap, the splitter, and auto-reflow are only live while editing.
    suggestionPanel.onDismiss = { [weak self] in
      self?.manager.editMode = false
      self?.endDragSwap()
      self?.splitters.forEach { $0.hide() }
      self?.hideButtons.forEach { $0.hide() }
    }
    // When a window opens/closes during edit mode, re-tile and refresh the pill.
    manager.onReorganized = { [weak self] name in self?.showAdjustPill(layoutName: name) }
    manager.start()
    installShortcuts()
    installDisplayReconcile()
    startCommandHook()
  }

  /// Always-on: after any mouse-up, move windows that crossed between boxed
  /// displays into the destination's layout (cross-display auto-format).
  private func installDisplayReconcile() {
    reconcileMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) {
      [weak self] event in
      guard let self else { return }
      if event.type == .leftMouseDown {
        self.manager.seedLastSeen()  // snapshot positions as a drag begins
        return
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
        self.manager.reconcileDisplays()
        if self.manager.editMode { self.positionSplitters() }
      }
    }
  }

  // MARK: - The organize flow

  /// The single entry point (menu item, ⌥ right-click, ⌥⌘T). If the display under
  /// the cursor is already tiled, just open the adjust popup — don't move anything.
  /// Otherwise tile it fresh (needs ≥2 windows and not a fullscreen Space), then
  /// open the popup.
  private func organizeEntry() {
    if let name = manager.retileIfOrganized() {
      showAdjustPill(layoutName: name)
      return
    }
    guard manager.tileableCount() >= 2, !manager.isFullscreenContext(),
      let name = manager.organize()
    else { return }
    showAdjustPill(layoutName: name)
  }

  /// A small pill that drops down under the menubar ▣ to tweak the arrangement.
  /// Reformat (shown as a diagram of the current layout) cycles to the next layout;
  /// Reset re-fills from scratch; swapping is by dragging a window onto another.
  /// Each press re-tiles and refreshes the pill (resets fade).
  private func showAdjustPill(layoutName: String) {
    manager.editMode = true
    beginDragSwap()
    positionSplitters()
    // Reset = re-fill this display from scratch (clears ratios/insets/heights) —
    // named apart from the menubar's Organize so the two read distinctly.
    let reset = WindowSuggestion(label: "↺ Reset", keepsPanelOpen: true) { [weak self] in
      guard let self else { return }
      self.showAdjustPill(layoutName: self.manager.reorganizeActive() ?? layoutName)
    }
    // Reformat = cycle the layout shape. The button is a tiny diagram of the
    // *current* layout (updates each press) rather than a name.
    let preview = LayoutPreview.image(for: manager.currentLayout(), size: NSSize(width: 38, height: 24))
    let reformat = WindowSuggestion(label: "Reformat", image: preview, keepsPanelOpen: true) {
      [weak self] in
      guard let self else { return }
      self.showAdjustPill(layoutName: self.manager.rebox() ?? layoutName)
    }
    var buttons = [reset, reformat]
    // Hiding is done from the little "hide" button on each window (see
    // positionHideButtons); ↺ Reset brings any hidden windows back.
    // Undo = put the windows back where they were before this organize and stop
    // managing the display — the escape hatch. Only offered when there's a snapshot.
    if manager.canUndo() {
      buttons.append(
        WindowSuggestion(label: "↩ Undo") { [weak self] in self?.manager.undoLastLayout() })
    }
    suggestionPanel.present(title: nil, buttons, near: adjustPillAnchor(), prominent: true)
  }

  /// Where the adjust pill should appear: under the menubar ▣ when it's on the
  /// display we just organized, otherwise at the top-center of that display — so
  /// the pill always lands on the screen you acted on, even when the menubar icon
  /// is on a different display.
  private func adjustPillAnchor() -> CGRect {
    guard let active = manager.activeScreen() else { return menubarAnchor() }
    if let itemScreen = statusItem.button?.window?.screen,
      manager.displayID(itemScreen) == manager.displayID(active)
    {
      return menubarAnchor()
    }
    return CGRect(x: active.frame.midX, y: active.visibleFrame.maxY, width: 0, height: 0)
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
    // Never show handles over a fullscreen Space — they'd do nothing.
    if manager.isFullscreenContext() {
      splitters.forEach { $0.hide() }
      return
    }
    let dividers = manager.dividers()
    for (index, splitter) in splitters.enumerated() {
      if index < dividers.count {
        splitter.show(frame: dividers[index].frame, vertical: dividers[index].vertical)
      } else {
        splitter.hide()
      }
    }
    positionHideButtons()
  }

  /// Place a "hide" button in the top-right corner of each tiled window.
  private func positionHideButtons() {
    if manager.isFullscreenContext() {
      hideButtons.forEach { $0.hide() }
      return
    }
    let slots = manager.tiledSlots()
    let bw: CGFloat = 46
    let bh: CGFloat = 20
    let pad: CGFloat = 8
    for (index, button) in hideButtons.enumerated() {
      guard index < slots.count else {
        button.hide()
        continue
      }
      let (window, rect) = slots[index]
      // Top-right corner (Cocoa: maxY is the top edge), clear of the traffic lights.
      let frame = CGRect(x: rect.maxX - bw - pad, y: rect.maxY - bh - pad, width: bw, height: bh)
      button.onClick = { [weak self] in
        guard let self else { return }
        self.showAdjustPill(layoutName: self.manager.hide(window) ?? "")
      }
      button.show(frame: frame)
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

  /// Polls a command file so a script can drive boxed for automated testing:
  ///   echo organize > "$TMPDIR/boxed-cmd"   (also: rebox, undo, dismiss, …)
  ///
  /// This is a TEST affordance, not a product feature — it lets any local process
  /// drive boxed's Accessibility-granted window control. So it is OFF unless the
  /// app is launched with BOXED_CMD_HOOK=1 (e.g. `open --env BOXED_CMD_HOOK=1
  /// boxed.app`), and the channel lives in the per-user temp dir (0700, user-owned),
  /// never world-writable /tmp.
  private func startCommandHook() {
    guard ProcessInfo.processInfo.environment["BOXED_CMD_HOOK"] == "1" else { return }
    let path = Paths.temp("boxed-cmd")
    Log.write("command hook enabled (BOXED_CMD_HOOK=1) at \(path)")
    Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
      guard let self,
        let raw = try? String(contentsOfFile: path, encoding: .utf8)
      else { return }
      let cmd = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !cmd.isEmpty else { return }
      try? "".write(toFile: path, atomically: true, encoding: .utf8)
      Log.write("cmd: \(cmd)")
      switch cmd {
      case "organize": self.organizeEntry()
      case "reorganize":  // clean re-fill (reset ratios/insets), as the popup's Organize
        if let name = self.manager.reorganizeActive() { self.showAdjustPill(layoutName: name) }
      case "undo": self.suggestionPanel.dismiss(); self.manager.undoLastLayout()
      case "hide": if let name = self.manager.hideFocusedWindow() { self.showAdjustPill(layoutName: name) }
      case "rebox": if let name = self.manager.rebox() { self.showAdjustPill(layoutName: name) }
      case "swap": if let name = self.manager.swap() { self.showAdjustPill(layoutName: name) }
      case "drop": if let name = self.manager.handleWindowDropped() { self.showAdjustPill(layoutName: name) }
      case "seed": self.manager.seedLastSeen()  // debug: mimic mouse-down before a drag
      case "reconcile": self.manager.reconcileDisplays()
      case "dividers": self.manager.logDividers()
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
        } else if cmd.hasPrefix("vinset ") {
          let parts = cmd.dropFirst(7).split(separator: " ")
          if parts.count == 3, let slot = Int(parts[0]), let t = Double(parts[1]),
            let b = Double(parts[2])
          {
            self.manager.setVInset(slot, top: CGFloat(t), bottom: CGFloat(b))
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
      title: "Organize windows", action: #selector(organizeNow), keyEquivalent: "t")
    organizeItem.keyEquivalentModifierMask = [.command, .option]
    organizeItem.target = self
    menu.addItem(organizeItem)

    let hint = NSMenuItem(
      title: "Tip: ⌥ right-click anywhere to summon", action: nil, keyEquivalent: "")
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
    // Enabled when the display can be tiled (≥2 windows, not a fullscreen Space)
    // OR is already tiled — in which case clicking just opens the adjust popup
    // without moving anything.
    organizeItem.isEnabled =
      manager.isAlreadyOrganized()
      || (manager.tileableCount() >= 2 && !manager.isFullscreenContext())
  }

  @objc private func organizeNow() {
    organizeEntry()
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
        self?.organizeEntry()
      }
    }

    // ⌥ right-click anywhere — organize the display under the cursor immediately
    // (same as ⌥⌘T), then show the adjust pill. Gated on the Option key so ordinary
    // right-clicks / context menus are untouched.
    rightClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: .rightMouseDown) {
      [weak self] event in
      let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      guard mods.contains(.option) else { return }
      self?.organizeEntry()
    }
  }
}
