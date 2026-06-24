import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItem: NSStatusItem!
  private var suggestItem: NSMenuItem!
  private var hotKeyMonitor: Any?
  private var rightClickMonitor: Any?
  private let manager = WindowManager()
  private let suggestionPanel = SuggestionPanel()

  func applicationDidFinishLaunching(_ notification: Notification) {
    Log.write("launched. accessibilityTrusted=\(AXIsProcessTrusted())")
    setupMenu()
    requestAccessibility()

    manager.onNewWindow = { [weak self] anchor in
      self?.showOrganizePill(near: anchor)
    }
    manager.start()
    installShortcuts()
  }

  // MARK: - The organize flow

  /// Stage 1: the "Organize tabs" prompt near a new window. Clicking it tiles
  /// everything, then brings up the adjust pill.
  private func showOrganizePill(near anchor: CGRect) {
    let organize = WindowSuggestion(label: "⧉  Organize tabs") { [weak self] in
      self?.organizeAndAdjust()
    }
    Log.write("presenting organize pill near \(NSStringFromRect(anchor))")
    suggestionPanel.present(title: nil, [organize], near: anchor)
  }

  /// Tile the windows, then (if any moved) show the adjust pill out of the way.
  private func organizeAndAdjust() {
    guard let name = manager.organize() else { return }
    showAdjustPill(layoutName: name)
  }

  /// Stage 2: a small pill, parked bottom-center, to tweak the arrangement.
  /// Swap rotates which window sits where; Rebox cycles to the next layout. Each
  /// press re-tiles and refreshes the pill (resetting its fade timer).
  private func showAdjustPill(layoutName: String) {
    let swap = WindowSuggestion(label: "⇄ Swap", keepsPanelOpen: true) { [weak self] in
      guard let self else { return }
      self.showAdjustPill(layoutName: self.manager.swap() ?? layoutName)
    }
    let rebox = WindowSuggestion(label: "▦ Rebox", keepsPanelOpen: true) { [weak self] in
      guard let self else { return }
      self.showAdjustPill(layoutName: self.manager.rebox() ?? layoutName)
    }
    suggestionPanel.present(title: layoutName, [swap, rebox], near: bottomCenterAnchor())
  }

  private func bottomCenterAnchor() -> CGRect {
    let vf = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
    return CGRect(x: vf.midX, y: vf.minY + 56, width: 0, height: 0)
  }

  // MARK: - Menubar

  private func setupMenu() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.title = "▣"

    let menu = NSMenu()

    let organizeNow = NSMenuItem(
      title: "Organize tabs now", action: #selector(organizeNow), keyEquivalent: "t")
    organizeNow.keyEquivalentModifierMask = [.command, .option]
    organizeNow.target = self
    menu.addItem(organizeNow)

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
