import AppKit
import ApplicationServices
import BoxedKit
import CoreGraphics

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

  /// True while the adjust pill is showing ("edit mode"). When set, opening or
  /// closing a window automatically re-tiles instead of offering a fresh prompt.
  var editMode = false

  /// Called after an automatic re-tile (edit mode) so the adjust pill can refresh.
  var onReorganized: ((_ layoutName: String) -> Void)?

  private var observers: [pid_t: AXObserver] = [:]
  private var reflowPending = false
  /// Each window's size the first time we saw it — its "natural" size, before
  /// boxed ever tiled it. Used to decide "small" so a window tiled into a small
  /// slot isn't later mistaken for a naturally-small one.
  private var naturalSizes: [(window: AXUIElement, size: CGSize)] = []

  private struct Session {
    var windows: [AXUIElement]
    var screen: NSScreen
    var layoutIndex: Int
    var order: [Int]  // order[slot] = index into `windows`
    var ratio: CGFloat = 0.5  // primary split fraction (the draggable edge)
    var stackRatio: CGFloat = 0.5  // secondary split (between the two stacked windows)
  }
  private var session: Session?

  /// A divider was dragged this session, so the next mouse-up should snap clean.
  private var ratioDirty = false
  /// True while a splitter handle is being dragged — pauses auto-reflow so windows
  /// don't jump mid-adjust.
  private(set) var draggingSplitter = false
  /// Windows boxed just resized, so their resize echoes can be ignored (vs. a
  /// genuine user drag). Pairs of (window, ignore-until).
  private var recentlySized: [(window: AXUIElement, until: DispatchTime)] = []

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
    _ = naturalSize(of: window)  // record its opening size before anything tiles it
    // A newly-opened window should come to the front, never hide behind tiles.
    if isTileable(window) {
      AXUIElementPerformAction(window, kAXRaiseAction as CFString)
      Log.write("raised new window to front")
    }
    // In edit mode, a new window should just slot into the current layout —
    // unless the user is mid-drag, in which case don't yank things around.
    if editMode {
      if !draggingSplitter {
        Log.write("new window during edit mode -> reflow")
        scheduleReflow()
      }
      return
    }
    guard suggestNewWindows, isTileable(window), let newFrame = frame(of: window) else { return }
    Log.write("new window -> offering organize")
    onNewWindow?(axToCocoa(newFrame))
  }

  /// A window (or other UI element) was destroyed. Only relevant in edit mode,
  /// where a closed window should make the rest re-tile to fill the gap.
  func handleWindowClosed() {
    guard editMode, session != nil, !draggingSplitter else { return }
    scheduleReflow()
  }

  /// Re-capture the windows on the active display and re-apply, coalescing bursts
  /// of open/close events. Keeps the current layout if the count is unchanged,
  /// otherwise falls back to that count's default.
  private func scheduleReflow() {
    guard !reflowPending else { return }
    reflowPending = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
      self?.reflowPending = false
      self?.reflow()
    }
  }

  private func reflow() {
    guard let old = session else { return }
    let screen = old.screen
    let onScreen = tileableWindows().filter {
      frame(of: $0).map { screenContains(screen, $0) } ?? false
    }
    guard !onScreen.isEmpty else { return }
    let usable = usableRect(on: screen)
    let windows = onScreen.filter { !isSmall($0, usable) } + onScreen.filter { isSmall($0, usable) }
    let keepLayout = windows.count == old.windows.count
    session = Session(
      windows: windows, screen: screen, layoutIndex: keepLayout ? old.layoutIndex : 0,
      order: Array(0..<windows.count), ratio: keepLayout ? old.ratio : 0.5,
      stackRatio: keepLayout ? old.stackRatio : 0.5)
    applySession()
    if let name = currentLayoutName() { onReorganized?(name) }
  }

  // MARK: - Organize session

  /// Capture every window on the active display and tile them with the default
  /// layout for that count. Returns the layout's name (nil if nothing to tile).
  @discardableResult
  func organize() -> String? {
    guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
    let onScreen = tileableWindows().filter {
      frame(of: $0).map { screenContains(screen, $0) } ?? false
    }
    guard !onScreen.isEmpty else {
      Log.write("organize: no windows to tile")
      return nil
    }
    // Big windows take the primary slots; small windows fall into the stack.
    let usable = usableRect(on: screen)
    let windows = onScreen.filter { !isSmall($0, usable) } + onScreen.filter { isSmall($0, usable) }
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

  /// Called on mouse-up while the adjust pill is showing. If a window was dragged
  /// off its slot and onto another's, swap the two and re-snap. Returns the layout
  /// name if anything changed (so the caller can keep the pill alive), else nil.
  @discardableResult
  func handleWindowDropped() -> String? {
    guard let s = session, s.windows.count > 1 else { return nil }
    let count = s.windows.count
    let kinds = Tiling.layouts(for: count)
    guard !kinds.isEmpty else { return nil }
    let kind = kinds[s.layoutIndex % kinds.count]
    let rects = Tiling.slots(kind, count: count, in: usableRect(on: s.screen), gap: gap, ratio: s.ratio, stackRatio: s.stackRatio)
    guard rects.count == count else { return nil }

    let centers = (0..<count).map { slot in
      frame(of: s.windows[s.order[slot]]).map { CGPoint(x: $0.midX, y: $0.midY) }
    }

    // Which slot's window moved farthest from where it belongs (the dragged one)?
    let threshold: CGFloat = 40
    var from: Int?
    var maxDist: CGFloat = threshold
    for slot in 0..<count {
      guard let c = centers[slot] else { continue }
      let home = CGPoint(x: rects[slot].midX, y: rects[slot].midY)
      let d = hypot(c.x - home.x, c.y - home.y)
      if d > maxDist {
        maxDist = d
        from = slot
      }
    }
    guard let from, let dropped = centers[from] else {
      // Not a move/swap. If a divider was dragged, snap everything clean.
      if ratioDirty {
        ratioDirty = false
        applySession()
        return currentLayoutName()
      }
      return nil
    }

    // Nearest other slot to where it was dropped.
    var to: Int?
    var best = CGFloat.greatestFiniteMagnitude
    for slot in 0..<count where slot != from {
      let sc = CGPoint(x: rects[slot].midX, y: rects[slot].midY)
      let d = hypot(dropped.x - sc.x, dropped.y - sc.y)
      if d < best {
        best = d
        to = slot
      }
    }
    let homeDist = hypot(
      dropped.x - rects[from].midX, dropped.y - rects[from].midY)

    var next = s
    if let to, best < homeDist {
      next.order.swapAt(from, to)
      Log.write("drag-swap slots \(from) <-> \(to)")
    } else {
      Log.write("drag re-snap slot \(from)")
    }
    session = next
    applySession()
    return currentLayoutName()
  }

  /// While in edit mode, the user resized a tiled window. If that window owns one
  /// side of the layout's primary split (Left/Right, Top/Bottom, or Main+stack),
  /// treat the dragged edge as the divider and slide the other side(s) to meet it —
  /// VS Code-style. The dragged window is left exactly where the user put it.
  func handleWindowResized(_ window: AXUIElement) {
    guard editMode, let s = session, !wasRecentlySized(window) else { return }
    let count = s.windows.count
    let kinds = Tiling.layouts(for: count)
    guard !kinds.isEmpty else { return }
    let kind = kinds[s.layoutIndex % kinds.count]

    let vertical: Bool
    switch kind {
    case .columns where count == 2, .mainLeft: vertical = true
    case .rows where count == 2, .mainTop: vertical = false
    default: return  // no single draggable primary split
    }

    guard
      let slot = (0..<count).first(where: { CFEqual(s.windows[s.order[$0]], window) }),
      let f = frame(of: window)
    else { return }
    let usable = usableRect(on: s.screen)

    // The divider is the edge of this window that faces the split.
    var ratio: CGFloat
    if vertical {
      ratio = slot == 0 ? (f.maxX - usable.minX) / usable.width : (f.minX - usable.minX) / usable.width
    } else {
      ratio = slot == 0 ? (f.maxY - usable.minY) / usable.height : (f.minY - usable.minY) / usable.height
    }
    ratio = Tiling.clampRatio(ratio)
    guard abs(ratio - s.ratio) > 0.004 else { return }

    var next = s
    next.ratio = ratio
    session = next
    ratioDirty = true

    // Move every OTHER window to meet the new divider; don't touch the dragged one.
    let rects = Tiling.slots(kind, count: count, in: usable, gap: gap, ratio: ratio)
    for other in 0..<count where other != slot {
      let w = s.windows[s.order[other]]
      setPosition(w, rects[other].origin)
      setSize(w, rects[other].size)
      setPosition(w, rects[other].origin)
    }
    Log.write("edge drag -> ratio \(String(format: "%.2f", ratio))")
  }

  // MARK: - Splitter (drag a divider to resize the split)

  func splitterDragBegan() { draggingSplitter = true }
  func splitterDragEnded() {
    draggingSplitter = false
    ratioDirty = false
  }

  /// A draggable divider in the current layout.
  struct Divider {
    enum Kind { case primary, stack }
    let kind: Kind
    let frame: CGRect  // Cocoa (bottom-left) coords for the handle
    let vertical: Bool  // true → drags left/right; false → up/down
  }

  /// All draggable dividers for the active layout (0–2): the primary split, plus
  /// the secondary stack split for a 3-window Main + stack / Main + row.
  func dividers() -> [Divider] {
    guard let s = session else { return [] }
    let count = s.windows.count
    let kinds = Tiling.layouts(for: count)
    guard !kinds.isEmpty else { return [] }
    let kind = kinds[s.layoutIndex % kinds.count]
    guard let primaryVertical = primarySplitVertical(kind, count) else { return [] }

    let usable = usableRect(on: s.screen)
    let grab: CGFloat = 16
    var out: [Divider] = []

    // Primary split.
    let primaryAX: CGRect
    if primaryVertical {
      let x = usable.minX + usable.width * s.ratio
      primaryAX = CGRect(x: x - grab / 2, y: usable.minY, width: grab, height: usable.height)
    } else {
      let y = usable.minY + usable.height * s.ratio
      primaryAX = CGRect(x: usable.minX, y: y - grab / 2, width: usable.width, height: grab)
    }
    out.append(Divider(kind: .primary, frame: axToCocoa(primaryAX), vertical: primaryVertical))

    // Secondary stack split (only the 3-window main layouts have exactly one).
    if count == 3 {
      let stackAX: CGRect
      if kind == .mainLeft {
        let stackX = usable.minX + usable.width * s.ratio
        let y = usable.minY + usable.height * s.stackRatio
        stackAX = CGRect(x: stackX, y: y - grab / 2, width: usable.maxX - stackX, height: grab)
        out.append(Divider(kind: .stack, frame: axToCocoa(stackAX), vertical: false))
      } else if kind == .mainTop {
        let stackY = usable.minY + usable.height * s.ratio
        let x = usable.minX + usable.width * s.stackRatio
        stackAX = CGRect(x: x - grab / 2, y: stackY, width: grab, height: usable.maxY - stackY)
        out.append(Divider(kind: .stack, frame: axToCocoa(stackAX), vertical: true))
      }
    }
    return out
  }

  /// Resize a divider live from a screen-space (Cocoa) cursor point during a drag.
  func setRatio(forDividerAt index: Int, fromScreenPoint point: CGPoint) {
    let ds = dividers()
    guard index < ds.count, var s = session else { return }
    let usable = usableRect(on: s.screen)
    let frac: CGFloat =
      ds[index].vertical
      ? (point.x - usable.minX) / usable.width
      : ((primaryHeight() - point.y) - usable.minY) / usable.height
    switch ds[index].kind {
    case .primary: s.ratio = Tiling.clampRatio(frac)
    case .stack: s.stackRatio = Tiling.clampRatio(frac)
    }
    session = s
    ratioDirty = true
    applySession()
  }

  private func primarySplitVertical(_ kind: LayoutKind, _ count: Int) -> Bool? {
    switch kind {
    case .columns where count == 2, .mainLeft: return true
    case .rows where count == 2, .mainTop: return false
    default: return nil
    }
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
    let usable = usableRect(on: s.screen)
    let rects = Tiling.slots(kind, count: count, in: usable, gap: gap, ratio: s.ratio, stackRatio: s.stackRatio)
    for slot in 0..<min(count, rects.count) {
      place(s.windows[s.order[slot]], in: rects[slot], usable: usable)
    }
    Log.write("applied \(Tiling.name(kind, count: count)) (count=\(count), order=\(s.order))")
  }

  // MARK: - Window discovery

  private func tileableWindows() -> [AXUIElement] {
    // The Accessibility window list includes windows that aren't actually visible
    // (other Spaces, hidden helpers, zero-size ghosts) — counting those leaves a
    // gap in the layout. Cross-check against what's genuinely on screen right now.
    let visible = onScreenWindows()
    Log.write(
      "on-screen: "
        + (visible.isEmpty
          ? "none"
          : visible.map { "[\(appName($0.pid))] \(rectStr($0.frame))" }.joined(separator: " ")))

    var result: [AXUIElement] = []
    var rawCount = 0

    let apps = NSWorkspace.shared.runningApplications.filter {
      $0.activationPolicy == .regular && !$0.isHidden
    }
    for app in apps {
      let pid = app.processIdentifier
      let name = app.localizedName ?? "pid \(pid)"
      let appElement = AXUIElementCreateApplication(pid)
      var value: CFTypeRef?
      guard
        AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
          == .success,
        let windows = value as? [AXUIElement]
      else { continue }
      for window in windows where isTileable(window) {
        rawCount += 1
        let f = frame(of: window)
        if let f, isVisible(f, pid: pid, in: visible) {
          result.append(window)
          Log.write("  keep [\(name)] \(rectStr(f))")
        } else {
          Log.write("  drop [\(name)] \(f.map(rectStr) ?? "no-frame")")
        }
      }
    }
    Log.write("tileable windows: \(result.count) of \(rawCount)")
    return result
  }

  private func rectStr(_ r: CGRect) -> String {
    "(\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))×\(Int(r.height)))"
  }

  private func appName(_ pid: pid_t) -> String {
    NSRunningApplication(processIdentifier: pid)?.localizedName ?? "pid \(pid)"
  }

  /// Windows actually rendered on the current Space, from the window server.
  /// Returns (owning pid, frame in top-left coords) for normal app windows only.
  private func onScreenWindows() -> [(pid: pid_t, frame: CGRect)] {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard
      let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
    else { return [] }

    var out: [(pid_t, CGRect)] = []
    for info in list {
      guard
        let layer = info[kCGWindowLayer as String] as? Int, layer == 0,  // normal windows
        let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber,
        let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
        let frame = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
      else { continue }
      if frame.width < 50 || frame.height < 50 { continue }  // skip ghosts/affordances
      out.append((pidNumber.int32Value, frame))
    }
    return out
  }

  /// Is this AX window backed by a real on-screen window of the same app?
  private func isVisible(_ axFrame: CGRect, pid: pid_t, in visible: [(pid: pid_t, frame: CGRect)])
    -> Bool
  {
    let center = CGPoint(x: axFrame.midX, y: axFrame.midY)
    return visible.contains { $0.pid == pid && $0.frame.insetBy(dx: -2, dy: -2).contains(center) }
  }

  private func isTileable(_ window: AXUIElement) -> Bool {
    // Require a real standard window subrole — this excludes the Finder desktop,
    // panels, sheets, and other non-window elements that have no/!standard subrole.
    var subrole: CFTypeRef?
    AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole)
    guard let s = subrole as? String, s == (kAXStandardWindowSubrole as String) else { return false }

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

  /// Place a window in its slot. Big, resizable windows fill the slot. Windows that
  /// are fixed-size, or "small" by default (under half the screen in BOTH width and
  /// height), keep their natural size and tuck into the slot's top-right — leaving
  /// the bottom-right empty instead of stretching a small window to fill.
  private func place(_ window: AXUIElement, in slot: CGRect, usable: CGRect) {
    let natural = naturalSize(of: window)
    let settable = isSizeSettable(window)
    let small = Tiling.isCompact(natural, in: usable.size)

    if (small || !settable), natural.width > 0, natural.height > 0 {
      // Keep the natural size, anchored top-right of the slot (AX origin is
      // top-left, so top == minY). Restore the size too, in case a prior layout
      // had stretched this window to fill.
      let origin = CGPoint(x: max(slot.minX, slot.maxX - natural.width), y: slot.minY)
      setPosition(window, origin)
      if settable { setSize(window, natural) }
      setPosition(window, origin)
      Log.write("kept natural \(Int(natural.width))×\(Int(natural.height)) (small/fixed), top-right")
      return
    }
    setPosition(window, slot.origin)
    setSize(window, slot.size)
    setPosition(window, slot.origin)  // re-anchor for apps that recenter on resize
  }

  /// A window's size the first time we ever saw it — recorded once and never
  /// overwritten, so it reflects the natural opening size, not a tiled size.
  private func naturalSize(of window: AXUIElement) -> CGSize {
    if let hit = naturalSizes.first(where: { CFEqual($0.window, window) }) { return hit.size }
    let size = frame(of: window)?.size ?? .zero
    naturalSizes.append((window, size))
    return size
  }

  private func isSmall(_ window: AXUIElement, _ usable: CGRect) -> Bool {
    Tiling.isCompact(naturalSize(of: window), in: usable.size)
  }

  private func setPosition(_ window: AXUIElement, _ origin: CGPoint) {
    var o = origin
    if let value = AXValueCreate(.cgPoint, &o) {
      AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }
  }

  private func setSize(_ window: AXUIElement, _ size: CGSize) {
    markSized(window)  // so the resulting resize echo isn't read as a user drag
    var s = size
    if let value = AXValueCreate(.cgSize, &s) {
      AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
    }
  }

  private func markSized(_ window: AXUIElement) {
    recentlySized.append((window, .now() + .milliseconds(300)))
  }

  private func wasRecentlySized(_ window: AXUIElement) -> Bool {
    let now = DispatchTime.now()
    recentlySized.removeAll { $0.until < now }
    return recentlySized.contains { CFEqual($0.window, window) }
  }

  private func isSizeSettable(_ window: AXUIElement) -> Bool {
    var settable: DarwinBoolean = false
    let err = AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &settable)
    return err == .success && settable.boolValue
  }

  /// Height of the primary display — the reference for converting between the
  /// Accessibility API's top-left origin and Cocoa's bottom-left origin.
  private func primaryHeight() -> CGFloat {
    NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
      ?? NSScreen.main?.frame.height ?? 0
  }

  /// Usable area of a display, in the Accessibility API's top-left coordinate space.
  private func usableRect(on screen: NSScreen) -> CGRect {
    let v = screen.visibleFrame
    return CGRect(
      x: v.minX, y: primaryHeight() - (v.minY + v.height), width: v.width, height: v.height)
  }

  private func axToCocoa(_ rect: CGRect) -> CGRect {
    CGRect(
      x: rect.minX, y: primaryHeight() - rect.minY - rect.height, width: rect.width,
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
      let note = notification as String
      if note == (kAXWindowCreatedNotification as String) {
        let window = element
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
          manager.handleWindowCreated(window)
        }
      } else if note == (kAXUIElementDestroyedNotification as String) {
        DispatchQueue.main.async { manager.handleWindowClosed() }
      } else if note == (kAXWindowResizedNotification as String) {
        let window = element
        DispatchQueue.main.async { manager.handleWindowResized(window) }
      }
    }
    guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }

    let appElement = AXUIElementCreateApplication(pid)
    let refcon = Unmanaged.passUnretained(self).toOpaque()
    AXObserverAddNotification(observer, appElement, kAXWindowCreatedNotification as CFString, refcon)
    AXObserverAddNotification(
      observer, appElement, kAXUIElementDestroyedNotification as CFString, refcon)
    AXObserverAddNotification(
      observer, appElement, kAXWindowResizedNotification as CFString, refcon)
    CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    observers[pid] = observer
  }
}
