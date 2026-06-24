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

  // MARK: - The organize pill

  /// Show the transient "Organize tabs" prompt. Clicking it tiles every window on
  /// the active display — the layout adapts to the window count automatically.
  private func showOrganizePill(near anchor: CGRect) {
    let organize = WindowSuggestion(label: "⧉  Organize tabs") { [weak self] in
      self?.manager.tidyAll()
    }
    Log.write("presenting organize pill near \(NSStringFromRect(anchor))")
    suggestionPanel.present([organize], near: anchor)
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
    manager.tidyAll()
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
        self?.manager.tidyAll()
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
