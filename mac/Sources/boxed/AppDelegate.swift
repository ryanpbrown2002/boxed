import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItem: NSStatusItem!
  private var suggestItem: NSMenuItem!
  private var hotKeyMonitor: Any?
  private let manager = WindowManager()
  private let suggestionPanel = SuggestionPanel()

  func applicationDidFinishLaunching(_ notification: Notification) {
    setupMenu()
    requestAccessibility()

    manager.onSuggest = { [weak self] suggestions, anchor in
      self?.suggestionPanel.present(suggestions, near: anchor)
    }
    manager.start()
    installHotKey()
  }

  // MARK: - Menubar

  private func setupMenu() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.title = "▣"

    let menu = NSMenu()

    suggestItem = NSMenuItem(
      title: "Suggest layouts for new windows", action: #selector(toggleSuggest), keyEquivalent: "")
    suggestItem.target = self
    suggestItem.state = manager.suggestNewWindows ? .on : .off
    menu.addItem(suggestItem)

    menu.addItem(.separator())

    let tidy = NSMenuItem(
      title: "Tidy all windows", action: #selector(tidyAll), keyEquivalent: "t")
    tidy.keyEquivalentModifierMask = [.command, .option]
    tidy.target = self
    menu.addItem(tidy)

    menu.addItem(.separator())

    let quit = NSMenuItem(
      title: "Quit boxed", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    menu.addItem(quit)

    statusItem.menu = menu
  }

  @objc private func toggleSuggest() {
    manager.suggestNewWindows.toggle()
    suggestItem.state = manager.suggestNewWindows ? .on : .off
  }

  @objc private func tidyAll() {
    manager.tidyAll()
  }

  // MARK: - Permissions

  private func requestAccessibility() {
    // String value of kAXTrustedCheckOptionPrompt — used directly to avoid
    // Unmanaged<CFString> bridging friction across SDK versions.
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    if !AXIsProcessTrustedWithOptions(options) {
      NSLog("boxed: Accessibility not yet granted — prompted. Grant it, then relaunch.")
    }
  }

  // MARK: - Global hot key (⌥⌘T to tidy all)

  private func installHotKey() {
    hotKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      if mods == [.command, .option], event.charactersIgnoringModifiers?.lowercased() == "t" {
        self?.manager.tidyAll()
      }
    }
  }
}
