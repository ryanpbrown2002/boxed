import AppKit
import ApplicationServices
import BoxedKit

/// Watches for newly-opened windows and, when one appears, asks the delegate to
/// offer to organize. Organizing tiles every window on the active display; the
/// resulting arrangement is an "organize session" the user can then tweak with
/// rebox (cycle layout) and swap (rotate which window sits where).
///
/// It never moves anything on its own — only on a user's click or shortcut.
final class WindowManager {
  var suggestNewWindows = true
  var gap: CGFloat = 8

  /// Called on the main thread when a new window appears. `anchor` is the new
  /// window's frame in Cocoa (bottom-left) coordinates.
  var onNewWindow: ((_ anchor: CGRect) -> Void)?

  private var observers: [pid_t: AXObserver] = [:]

  private struct Session {
    var windows: [AXUIElement]
    var screen: NSScreen
    var layoutIndex: Int
    var order: [Int]  // order[slot] = index into `windows`
  }
  private var session: Session?

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

  func handleWindowCreated(_ window: AXUIElement) {
    guard suggestNewWindows, isTileable(window), let newFrame = frame(of: window) else { return }
    Log.write("new window -> offering organize")
    onNewWindow?(axToCocoa(newFrame))
  }

  // MARK: - Organize session

  /// Capture every window on the active display and tile them with the default
  /// layout for that count. Returns the layout's name (nil if nothing to tile).
  @discardableResult
  func organize() -> String? {
    guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
    let windows = tileableWindows().filter {
      frame(of: $0).map { screenContains(screen, $0) } ?? false
    }
    guard !windows.isEmpty else {
      Log.write("organize: no windows to tile")
      return nil
    }
    session = Session(
      windows: windows, screen: screen, layoutIndex: 0, order: Array(0..<windows.count))
    applySession()
    return currentLayoutName()
  }

  /// Cycle to the next layout for the current window count and re-apply.
  @discardableResult
  func rebox() -> String? {
    guard var s = session else { return nil }
    let kinds = Tiling.layouts(for: s.windows.count)
    guard !kinds.isEmpty else { return nil }
    s.layoutIndex = (s.layoutIndex + 1) % kinds.count
    session = s
    applySession()
    return currentLayoutName()
  }

  /// Rotate which window occupies which slot and re-apply.
  @discardableResult
  func swap() -> String? {
    guard var s = session, s.order.count > 1 else { return currentLayoutName() }
    s.order = Array(s.order.dropFirst()) + [s.order[0]]
    session = s
    applySession()
    return currentLayoutName()
  }

  func currentLayoutName() -> String? {
    guard let s = session else { return nil }
    let kinds = Tiling.layouts(for: s.windows.count)
    guard !kinds.isEmpty else { return nil }
    return Tiling.name(kinds[s.layoutIndex % kinds.count], count: s.windows.count)
  }

  private func applySession() {
    guard let s = session else { return }
    let count = s.windows.count
    let kinds = Tiling.layouts(for: count)
    guard !kinds.isEmpty else { return }
    let kind = kinds[s.layoutIndex % kinds.count]
    let rects = Tiling.slots(kind, count: count, in: usableRect(on: s.screen), gap: gap)
    for slot in 0..<min(count, rects.count) {
      setFrame(s.windows[s.order[slot]], rects[slot])
    }
    Log.write("applied \(Tiling.name(kind, count: count)) (count=\(count), order=\(s.order))")
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
    return CGRect(
      x: v.minX, y: primaryHeight - (v.minY + v.height), width: v.width, height: v.height)
  }

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
