import AppKit
import ApplicationServices

/// Watches for newly-opened windows and, when one appears, asks the delegate to
/// offer placement suggestions. It does NOT move anything on its own — that's the
/// whole point: boxed stays out of the normal macOS workflow until you opt in by
/// clicking a suggestion. `tidyAll()` is the one exception, and only runs when the
/// user explicitly invokes it.
final class WindowManager {
  /// When true, a prompt appears near each newly-opened window. Default behavior.
  var suggestNewWindows = true
  var gap: CGFloat = 8

  /// Called on the main thread when a new window appears and we should offer to
  /// organize. `anchor` is the new window's frame in Cocoa (bottom-left) coords.
  var onNewWindow: ((_ anchor: CGRect) -> Void)?

  private var observers: [pid_t: AXObserver] = [:]

  func start() {
    let nc = NSWorkspace.shared.notificationCenter
    for name in [
      NSWorkspace.didLaunchApplicationNotification,
      NSWorkspace.didActivateApplicationNotification
    ] {
      nc.addObserver(self, selector: #selector(appsChanged), name: name, object: nil)
    }
    observeRunningApps()
    Log.write("started, observing \(observers.count) apps for new windows")
  }

  @objc private func appsChanged(_ note: Notification) {
    observeRunningApps()
  }

  // MARK: - New-window suggestions

  /// Invoked (on the main thread) shortly after a window is created, once it has
  /// had a moment to settle into its initial size.
  func handleWindowCreated(_ window: AXUIElement) {
    guard suggestNewWindows, isTileable(window), let newFrame = frame(of: window) else { return }
    Log.write("new window -> offering organize")
    onNewWindow?(axToCocoa(newFrame))
  }

  // MARK: - Manual tidy (user-initiated only)

  /// Tile every window on the active display into a BSP layout. Only called from
  /// the menubar item / hotkey — never automatically.
  func tidyAll() {
    let screen = NSScreen.main ?? NSScreen.screens.first
    guard let screen else { return }
    let windows = tileableWindows().filter { frame(of: $0).map { screenContains(screen, $0) } ?? false }
    guard !windows.isEmpty else { return }
    let frames = Layout.bsp(count: windows.count, in: usableRect(on: screen), gap: gap)
    for (window, rect) in zip(windows, frames) {
      setFrame(window, rect)
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

  // MARK: - Geometry

  private func frame(of window: AXUIElement) -> CGRect? {
    var posRef: CFTypeRef?
    var sizeRef: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef) == .success,
      AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
      let posRef, let sizeRef,
      CFGetTypeID(posRef) == AXValueGetTypeID(), CFGetTypeID(sizeRef) == AXValueGetTypeID()
    else { return nil }

    var point = CGPoint.zero
    var size = CGSize.zero
    AXValueGetValue(posRef as! AXValue, .cgPoint, &point)
    AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
    return CGRect(origin: point, size: size)
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

  /// Usable area of a display, in the Accessibility API's top-left coordinate space.
  private func usableRect(on screen: NSScreen) -> CGRect {
    let primaryHeight =
      NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
      ?? screen.frame.height
    let v = screen.visibleFrame
    return CGRect(x: v.minX, y: primaryHeight - (v.minY + v.height), width: v.width, height: v.height)
  }

  /// Convert a top-left (Accessibility) rect to a bottom-left (Cocoa) rect.
  private func axToCocoa(_ rect: CGRect) -> CGRect {
    let primaryHeight =
      NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
      ?? NSScreen.main?.frame.height ?? rect.maxY
    return CGRect(
      x: rect.minX, y: primaryHeight - rect.minY - rect.height, width: rect.width,
      height: rect.height)
  }

  private func screenContains(_ screen: NSScreen, _ axRect: CGRect) -> Bool {
    let cocoa = axToCocoa(axRect)
    return screen.frame.contains(CGPoint(x: cocoa.midX, y: cocoa.midY))
  }

  // MARK: - Live window events

  private func observeRunningApps() {
    let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
    for app in apps {
      observe(pid: app.processIdentifier)
    }
  }

  private func observe(pid: pid_t) {
    guard observers[pid] == nil else { return }

    var observer: AXObserver?
    let callback: AXObserverCallback = { _, element, notification, refcon in
      guard let refcon else { return }
      let manager = Unmanaged<WindowManager>.fromOpaque(refcon).takeUnretainedValue()
      guard (notification as String) == (kAXWindowCreatedNotification as String) else { return }
      Log.write("AXWindowCreated received")
      let window = element
      // Let the app finish sizing the window before we read its frame.
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
        manager.handleWindowCreated(window)
      }
    }
    guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }

    let appElement = AXUIElementCreateApplication(pid)
    let refcon = Unmanaged.passUnretained(self).toOpaque()
    AXObserverAddNotification(observer, appElement, kAXWindowCreatedNotification as CFString, refcon)
    CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    observers[pid] = observer
  }
}
