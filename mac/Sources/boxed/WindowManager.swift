import AppKit
import ApplicationServices

/// Finds the user's real windows, tiles them to fill the active display, and
/// reflows whenever a window opens or closes. Tier 1: needs only Accessibility
/// permission — no SIP changes.
final class WindowManager {
  var autoTile = true
  var gap: CGFloat = 8

  private var observers: [pid_t: AXObserver] = [:]
  private var pendingTile = false

  func start() {
    let nc = NSWorkspace.shared.notificationCenter
    for name in [
      NSWorkspace.didLaunchApplicationNotification,
      NSWorkspace.didTerminateApplicationNotification,
      NSWorkspace.didActivateApplicationNotification
    ] {
      nc.addObserver(self, selector: #selector(appsChanged), name: name, object: nil)
    }
    observeRunningApps()
    tile()
  }

  @objc private func appsChanged(_ note: Notification) {
    observeRunningApps()
    scheduleTile()
  }

  // MARK: - Tiling

  /// Recompute and apply frames for every tileable window on the active display.
  func tile() {
    let windows = tileableWindows()
    guard !windows.isEmpty else { return }
    let frames = Layout.bsp(count: windows.count, in: usableRect(), gap: gap)
    for (window, frame) in zip(windows, frames) {
      setFrame(window, frame)
    }
  }

  /// Coalesce bursts of AX events into a single tile pass.
  func scheduleTile() {
    guard autoTile, !pendingTile else { return }
    pendingTile = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
      self?.pendingTile = false
      self?.tile()
    }
  }

  // MARK: - Window discovery

  private func tileableWindows() -> [AXUIElement] {
    var result: [AXUIElement] = []
    let apps = NSWorkspace.shared.runningApplications.filter {
      $0.activationPolicy == .regular && !$0.isHidden
    }
    for app in apps {
      let appElement = AXUIElementCreateApplication(app.processIdentifier)
      var value: CFTypeRef?
      guard
        AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
          == .success,
        let windows = value as? [AXUIElement]
      else { continue }
      result.append(contentsOf: windows.filter(isTileable))
    }
    return result
  }

  private func isTileable(_ window: AXUIElement) -> Bool {
    var subrole: CFTypeRef?
    AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole)
    if let s = subrole as? String, s != (kAXStandardWindowSubrole as String) { return false }

    var minimized: CFTypeRef?
    AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized)
    if let m = minimized as? Bool, m { return false }

    return true
  }

  private func setFrame(_ window: AXUIElement, _ rect: CGRect) {
    var origin = rect.origin
    var size = rect.size
    if let posValue = AXValueCreate(.cgPoint, &origin) {
      AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
    }
    if let sizeValue = AXValueCreate(.cgSize, &size) {
      AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
    }
  }

  /// The usable area of the active display, converted to the top-left origin
  /// coordinate space the Accessibility API expects.
  private func usableRect() -> CGRect {
    guard let screen = NSScreen.main ?? NSScreen.screens.first else { return .zero }
    let full = screen.frame
    let visible = screen.visibleFrame
    let axY = full.height - (visible.origin.y + visible.height) // = menu-bar height
    return CGRect(x: visible.origin.x, y: axY, width: visible.width, height: visible.height)
  }

  // MARK: - Live window events (open / close / focus)

  private func observeRunningApps() {
    let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
    for app in apps {
      observe(pid: app.processIdentifier)
    }
  }

  private func observe(pid: pid_t) {
    guard observers[pid] == nil else { return }

    var observer: AXObserver?
    let callback: AXObserverCallback = { _, _, _, refcon in
      guard let refcon else { return }
      let manager = Unmanaged<WindowManager>.fromOpaque(refcon).takeUnretainedValue()
      manager.scheduleTile()
    }
    guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }

    let appElement = AXUIElementCreateApplication(pid)
    let refcon = Unmanaged.passUnretained(self).toOpaque()
    for notification in [
      kAXWindowCreatedNotification,
      kAXUIElementDestroyedNotification,
      kAXFocusedWindowChangedNotification
    ] {
      AXObserverAddNotification(observer, appElement, notification as CFString, refcon)
    }
    CFRunLoopAddSource(
      CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    observers[pid] = observer
  }
}
