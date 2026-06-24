import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
  private var statusItem: NSStatusItem!
  private var autoItem: NSMenuItem!
  private var hotKeyMonitor: Any?
  private let manager = WindowManager()

  func applicationDidFinishLaunching(_ notification: Notification) {
    setupMenu()
    requestAccessibility()
    manager.start()
    installHotKey()
  }

  // MARK: - Menubar

  private func setupMenu() {
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.title = "▣"

    let menu = NSMenu()

    let tileNow = NSMenuItem(title: "Tile now", action: #selector(tileNow), keyEquivalent: "t")
    tileNow.target = self
    menu.addItem(tileNow)

    autoItem = NSMenuItem(title: "Auto-tile", action: #selector(toggleAuto), keyEquivalent: "")
    autoItem.target = self
    autoItem.state = manager.autoTile ? .on : .off
    menu.addItem(autoItem)

    menu.addItem(.separator())
    menu.addItem(
      withTitle: "Re-tile shortcut: ⌥⌘T", action: nil, keyEquivalent: "")
    menu.addItem(.separator())

    let quit = NSMenuItem(
      title: "Quit boxed", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    menu.addItem(quit)

    statusItem.menu = menu
  }

  @objc private func tileNow() {
    manager.tile()
  }

  @objc private func toggleAuto() {
    manager.autoTile.toggle()
    autoItem.state = manager.autoTile ? .on : .off
    if manager.autoTile { manager.tile() }
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

  // MARK: - Global hot key (⌥⌘T to re-tile)

  private func installHotKey() {
    hotKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
      let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      if mods == [.command, .option], event.charactersIgnoringModifiers?.lowercased() == "t" {
        self?.manager.tile()
      }
    }
  }
}
