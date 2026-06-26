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
  var gap: CGFloat = 8

  /// True while the adjust pill is showing ("edit mode"). When set, opening or
  /// closing a window automatically re-tiles instead of offering a fresh prompt.
  var editMode = false

  /// Called after an automatic re-tile (edit mode) so the adjust pill can refresh.
  var onReorganized: ((_ layoutName: String) -> Void)?

  private var observers: [pid_t: AXObserver] = [:]
  private var reflowPending = false
  /// A window's "natural" size: recorded at creation (before boxed tiles it) and
  /// updated when the user manually resizes it — never from boxed's own tiling.
  /// Used to decide whether a window fills its slot or stays small.
  private var naturalSizes: [(window: AXUIElement, size: CGSize)] = []
  /// Windows boxed just resized, so the resulting resize echo isn't mistaken for a
  /// user resize. (window, ignore-until).
  private var recentlySized: [(window: AXUIElement, until: DispatchTime)] = []

  private struct Session {
    var windows: [AXUIElement]
    var screen: NSScreen
    var layoutIndex: Int
    var order: [Int]  // order[slot] = index into `windows`
    var ratio: CGFloat = 0.5  // primary split fraction (the draggable edge)
    var stackRatio: CGFloat = 0.5  // secondary split (between the two stacked windows)
    // Outer margins (points) — drag the edge handles to inset the tiled region and
    // let the desktop show around it.
    var insetTop: CGFloat = 0
    var insetBottom: CGFloat = 0
    var insetLeft: CGFloat = 0
    var insetRight: CGFloat = 0
    // Per-slot height trim (points off the top/bottom of each window's slot), so a
    // single window's height can be adjusted independently. Index = slot.
    var vInsets: [(top: CGFloat, bottom: CGFloat)] = []
  }
  /// One layout per display ("boxed" displays). Keyed by display ID.
  private var sessions: [CGDirectDisplayID: Session] = [:]
  /// The display currently being organized/edited — what `session` reads & writes.
  private var activeDisplay: CGDirectDisplayID?

  /// The active display's session. Most logic operates on this; per-display
  /// reconciliation iterates `sessions` directly.
  private var session: Session? {
    get { activeDisplay.flatMap { sessions[$0] } }
    set {
      guard let id = activeDisplay else { return }
      sessions[id] = newValue
    }
  }

  /// A divider was dragged this session, so the next mouse-up should snap clean.
  private var ratioDirty = false
  /// True while a splitter handle is being dragged — pauses auto-reflow so windows
  /// don't jump mid-adjust.
  private(set) var draggingSplitter = false

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
    recordNatural(window)  // capture the app's opening size, before boxed tiles it
    // A newly-opened window should come to the front, never hide behind tiles.
    if isTileable(window) {
      AXUIElementPerformAction(window, kAXRaiseAction as CFString)
      Log.write("raised new window to front")
    }
    // In edit mode, a new window slots into the current layout — unless the user
    // is mid-drag, in which case don't yank things around. (boxed never prompts on
    // its own; organizing is always summoned by the user.)
    if editMode, !draggingSplitter {
      Log.write("new window during edit mode -> reflow")
      scheduleReflow()
    }
  }

  /// A window (or other UI element) was destroyed. Drop any closed window from its
  /// display's session, but do NOT reflow — the survivors keep their sizes rather
  /// than one growing to fill the gap.
  func handleWindowClosed() {
    var changed = false
    for (id, var s) in sessions {
      let before = s.windows.count
      s.windows.removeAll { frame(of: $0) == nil }  // closed → AX frame unreadable
      if s.windows.count != before {
        sessions[id] = s.windows.isEmpty ? nil : normalized(s)
        changed = true
      }
    }
    if changed { Log.write("pruned closed window(s); not reflowing (no fullscreen)") }
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
    // Keep the windows we're already managing that still exist. A window shoved
    // off-screen by Show Desktop / a Spaces transition is still alive — it must
    // not be dropped just because it isn't in the on-screen scan this instant.
    let alive = old.windows.filter { isTileable($0) && frame(of: $0) != nil }
    // Add genuinely new on-screen windows we aren't tracking yet.
    let newcomers = tileableWindows().filter { candidate in
      isOn(candidate, screen) && !alive.contains { CFEqual($0, candidate) }
    }
    // Keep existing windows in their order; new ones go to the trailing slots.
    let windows = alive + newcomers
    guard !windows.isEmpty else { return }
    let keepLayout = windows.count == old.windows.count
    session = Session(
      windows: windows, screen: screen, layoutIndex: keepLayout ? old.layoutIndex : 0,
      order: Array(0..<windows.count), ratio: keepLayout ? old.ratio : 0.5,
      stackRatio: keepLayout ? old.stackRatio : 0.5,
      insetTop: keepLayout ? old.insetTop : 0, insetBottom: keepLayout ? old.insetBottom : 0,
      insetLeft: keepLayout ? old.insetLeft : 0, insetRight: keepLayout ? old.insetRight : 0)
    applyAndFitActive()
    if let name = currentLayoutName() { onReorganized?(name) }
  }

  // MARK: - Organize session

  /// Capture every window on the active display and tile them with the default
  /// layout for that count. Returns the layout's name (nil if nothing to tile).
  @discardableResult
  func organize() -> String? {
    guard let screen = screenUnderCursor() else { return nil }
    activeDisplay = displayID(screen)
    let onScreen = tileableWindows().filter {
      isOn($0, screen)
    }
    guard !onScreen.isEmpty else {
      Log.write("organize: no windows to tile")
      return nil
    }
    // Biggest windows take the primary slots (main), smaller ones the stack.
    let windows = onScreen.sorted { windowArea($0) > windowArea($1) }
    session = Session(
      windows: windows, screen: screen, layoutIndex: 0, order: Array(0..<windows.count))
    applyAndFitActive()
    return currentLayoutName()
  }

  /// The "Organize tabs" action. If the same windows are already in a session,
  /// just re-align them to the current layout (preserving the layout choice and
  /// any dragged ratios) instead of remixing from scratch. Only a changed set of
  /// windows triggers a fresh organize.
  @discardableResult
  func organizeOrEdit() -> String? {
    guard let screen = screenUnderCursor() else { return nil }
    if fullscreenWindow(on: screen) != nil {
      Log.write("fullscreen display — not organizing/editing")
      return nil
    }
    activeDisplay = displayID(screen)
    let onScreen = tileableWindows().filter {
      isOn($0, screen)
    }
    // Nothing to arrange with a single window — don't tile it to "Full".
    guard onScreen.count >= 2 else {
      Log.write("only one window on this display — not organizing")
      return nil
    }

    if let s = session, sameWindowSet(s.windows, onScreen) {
      Log.write("re-align (already organized) — keeping \(currentLayoutName() ?? "layout")")
      realignToNearestSlots()  // snap to nearest slot; keep layout + dragged ratios
      return currentLayoutName()
    }
    return organize()
  }

  private func sameWindowSet(_ a: [AXUIElement], _ b: [AXUIElement]) -> Bool {
    guard a.count == b.count else { return false }
    return b.allSatisfy { w in a.contains { CFEqual($0, w) } }
  }

  /// How many tileable windows are on the display under the cursor right now.
  func tileableCount() -> Int {
    guard let screen = screenUnderCursor() else { return 0 }
    return tileableWindows().filter { isOn($0, screen) }
      .count
  }

  /// Is the display under the cursor already boxed with exactly its current
  /// windows (so the action would re-align/edit rather than organize fresh)?
  func isAlreadyOrganized() -> Bool {
    guard let screen = screenUnderCursor(), let s = sessions[displayID(screen)] else { return false }
    let onScreen = tileableWindows().filter {
      isOn($0, screen)
    }
    return !onScreen.isEmpty && sameWindowSet(s.windows, onScreen)
  }

  /// Re-assign windows to the current layout's slots by nearest position — each
  /// window snaps to the slot closest to where it already is — while preserving
  /// the layout choice and any dragged ratios. "Match the closest place, but
  /// organized." This avoids replaying a stale order that would shuffle windows.
  private func realignToNearestSlots() {
    guard let s = session else { return }
    let count = s.windows.count
    let kinds = Tiling.layouts(for: count)
    guard !kinds.isEmpty else { return }
    let kind = kinds[s.layoutIndex % kinds.count]
    let rects = Tiling.slots(
      kind, count: count, in: effectiveRect(usableRect(on: s.screen), s), gap: gap, ratio: s.ratio,
      stackRatio: s.stackRatio)
    guard rects.count == count else {
      applySession()
      return
    }

    let centers = s.windows.map { frame(of: $0).map { CGPoint(x: $0.midX, y: $0.midY) } }
    var used = Set<Int>()
    var order = [Int](repeating: 0, count: count)
    for slot in 0..<count {
      let target = CGPoint(x: rects[slot].midX, y: rects[slot].midY)
      var best = -1
      var bestDist = CGFloat.greatestFiniteMagnitude
      for w in 0..<count where !used.contains(w) {
        let d = centers[w].map { hypot($0.x - target.x, $0.y - target.y) } ?? .greatestFiniteMagnitude
        if d < bestDist {
          bestDist = d
          best = w
        }
      }
      if best < 0 { best = (0..<count).first { !used.contains($0) } ?? slot }
      used.insert(best)
      order[slot] = best
    }
    var next = s
    next.order = order
    session = next
    Log.write("realign -> order \(order)")
    applyAndFitActive()
  }

  /// Debug/test hook: set an outer inset (points) directly.
  func setInset(_ edge: String, _ points: CGFloat) {
    guard var s = session, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
    let usable = usableRect(on: screen)
    switch edge {
    case "top": s.insetTop = clampInset(points, usable.height)
    case "bottom": s.insetBottom = clampInset(points, usable.height)
    case "left": s.insetLeft = clampInset(points, usable.width)
    case "right": s.insetRight = clampInset(points, usable.width)
    default: return
    }
    session = s
    applySession()
  }

  /// Debug/test hook: log the current draggable handles.
  func logDividers() {
    let ds = dividers()
    Log.write(
      "dividers (\(ds.count)): "
        + ds.map { "\($0.kind)@(\(Int($0.frame.minX)),\(Int($0.frame.minY)) \(Int($0.frame.width))x\(Int($0.frame.height)))" }
        .joined(separator: ", "))
  }

  /// Debug/test hook: set a slot's per-window height trim directly.
  func setVInset(_ slot: Int, top: CGFloat, bottom: CGFloat) {
    guard var s = session, slot >= 0, slot < s.windows.count else { return }
    ensureVInsets(&s, s.windows.count)
    s.vInsets[slot] = (top: max(0, top), bottom: max(0, bottom))
    session = s
    applySession()
  }

  /// Debug/test hook: set the split ratios directly.
  func setRatios(primary: CGFloat?, stack: CGFloat?) {
    guard var s = session else { return }
    if let primary { s.ratio = Tiling.clampRatio(primary) }
    if let stack { s.stackRatio = Tiling.clampRatio(stack) }
    session = s
    applySession()
  }

  /// Cycle to the next layout for the current window count and re-apply.
  @discardableResult
  func rebox() -> String? {
    guard var s = session else { return nil }
    let kinds = Tiling.layouts(for: s.windows.count)
    guard !kinds.isEmpty else { return nil }
    s.layoutIndex = (s.layoutIndex + 1) % kinds.count
    s.vInsets = []  // slot meanings change with the layout — reset per-window heights
    session = s
    applyAndFitActive()
    return currentLayoutName()
  }

  /// Rotate which window occupies which slot and re-apply.
  @discardableResult
  func swap() -> String? {
    guard var s = session, s.order.count > 1 else { return currentLayoutName() }
    s.order = Array(s.order.dropFirst()) + [s.order[0]]
    s.vInsets = []  // per-slot heights are meaningless once windows move slots
    session = s
    // Re-fit: the rigid window may have rotated into a different-sized slot.
    applyAndFitActive()
    return currentLayoutName()
  }

  /// Called on mouse-up while the adjust pill is showing. If a window was dragged
  /// off its slot and onto another's, swap the two and re-snap. Returns the layout
  /// name if anything changed (so the caller can keep the pill alive), else nil.
  @discardableResult
  func handleWindowDropped() -> String? {
    guard let s = session else { return nil }

    // If any window left this display, let reconcileDisplays handle it (move to
    // another boxed display or release) — don't swap-snap it back here.
    if s.windows.contains(where: { !isOn($0, s.screen) }) {
      ratioDirty = false
      return nil
    }

    guard s.windows.count > 1 else {
      if ratioDirty {
        ratioDirty = false
        applySession()
        return currentLayoutName()
      }
      return nil
    }
    let count = s.windows.count
    let kinds = Tiling.layouts(for: count)
    guard !kinds.isEmpty else { return nil }
    let kind = kinds[s.layoutIndex % kinds.count]
    let rects = Tiling.slots(
      kind, count: count, in: effectiveRect(usableRect(on: s.screen), s), gap: gap, ratio: s.ratio,
      stackRatio: s.stackRatio)
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


  // MARK: - Splitter (drag a divider to resize the split)

  func splitterDragBegan() { draggingSplitter = true }
  func splitterDragEnded() {
    draggingSplitter = false
    ratioDirty = false
  }

  /// A draggable divider in the current layout.
  struct Divider {
    enum Kind {
      case primary, stack, edgeLeft, edgeRight
      case windowTop(Int), windowBottom(Int)  // per-window height handles (slot index)
    }
    let kind: Kind
    let frame: CGRect  // Cocoa (bottom-left) coords for the handle
    let vertical: Bool  // true → drags left/right; false → up/down
  }

  /// All draggable handles for the active layout: the internal split(s) plus the
  /// four outer edges. Dragging an edge inward insets the tiled region and lets
  /// the desktop show around it. Edges are always present; internal splits depend
  /// on the layout.
  func dividers() -> [Divider] {
    guard let s = session else { return [] }
    let count = s.windows.count
    let kinds = Tiling.layouts(for: count)
    guard !kinds.isEmpty else { return [] }
    let kind = kinds[s.layoutIndex % kinds.count]

    let usable = usableRect(on: s.screen)
    let eff = effectiveRect(usable, s)
    let grab: CGFloat = 16
    var out: [Divider] = []

    // Internal split(s), within the inset region.
    if let primaryVertical = primarySplitVertical(kind, count) {
      let primaryAX: CGRect
      if primaryVertical {
        let x = eff.minX + eff.width * s.ratio
        primaryAX = CGRect(x: x - grab / 2, y: eff.minY, width: grab, height: eff.height)
      } else {
        let y = eff.minY + eff.height * s.ratio
        primaryAX = CGRect(x: eff.minX, y: y - grab / 2, width: eff.width, height: grab)
      }
      out.append(Divider(kind: .primary, frame: axToCocoa(primaryAX), vertical: primaryVertical))

      if count == 3, kind == .mainLeft {
        let stackX = eff.minX + eff.width * s.ratio
        let y = eff.minY + eff.height * s.stackRatio
        out.append(
          Divider(
            kind: .stack,
            frame: axToCocoa(
              CGRect(x: stackX, y: y - grab / 2, width: eff.maxX - stackX, height: grab)),
            vertical: false))
      } else if count == 3, kind == .mainTop {
        let stackY = eff.minY + eff.height * s.ratio
        let x = eff.minX + eff.width * s.stackRatio
        out.append(
          Divider(
            kind: .stack,
            frame: axToCocoa(
              CGRect(x: x - grab / 2, y: stackY, width: grab, height: eff.maxY - stackY)),
            vertical: true))
      }
    }

    // Outer left/right margins (the layout's horizontal insets). Top/bottom are
    // handled per-window below. Clamp on-screen so an edge handle sitting on the
    // screen border isn't half cut off (its panel would otherwise straddle the
    // edge); dragging math is cursor-based, so nudging the handle inward is free.
    out.append(
      Divider(
        kind: .edgeLeft,
        frame: axToCocoa(
          Tiling.clampOnscreen(
            CGRect(x: eff.minX - grab / 2, y: eff.minY, width: grab, height: eff.height),
            within: usable)),
        vertical: true))
    out.append(
      Divider(
        kind: .edgeRight,
        frame: axToCocoa(
          Tiling.clampOnscreen(
            CGRect(x: eff.maxX - grab / 2, y: eff.minY, width: grab, height: eff.height),
            within: usable)),
        vertical: true))

    // Per-window height handles — only on a window's FREE outer edges (those at
    // the layout's top/bottom). An inner edge shared with a neighbor is owned by
    // the split divider, so we don't stack a handle there (that was moving both).
    let raw = Tiling.slots(
      kind, count: count, in: eff, gap: gap, ratio: s.ratio, stackRatio: s.stackRatio)
    for slot in 0..<min(count, raw.count) {
      let vi = slot < s.vInsets.count ? s.vInsets[slot] : (top: CGFloat(0), bottom: CGFloat(0))
      let f = Tiling.shrinkVertically(raw[slot], top: vi.top, bottom: vi.bottom)
      let edges = Tiling.touchesEdge(slot: raw[slot], layout: eff, gap: gap)
      if edges.top {
        out.append(
          Divider(
            kind: .windowTop(slot),
            frame: axToCocoa(CGRect(x: f.minX, y: f.minY - grab / 2, width: f.width, height: grab)),
            vertical: false))
      }
      if edges.bottom {
        out.append(
          Divider(
            kind: .windowBottom(slot),
            frame: axToCocoa(CGRect(x: f.minX, y: f.maxY - grab / 2, width: f.width, height: grab)),
            vertical: false))
      }
    }
    return out
  }

  /// Resize a divider/edge live from a screen-space (Cocoa) cursor point.
  func setRatio(forDividerAt index: Int, fromScreenPoint point: CGPoint) {
    let ds = dividers()
    guard index < ds.count, var s = session else { return }
    let count = s.windows.count
    let kinds = Tiling.layouts(for: count)
    guard !kinds.isEmpty else { return }
    let kind = kinds[s.layoutIndex % kinds.count]
    let usable = usableRect(on: s.screen)
    let eff = effectiveRect(usable, s)
    let axY = primaryHeight() - point.y  // Cocoa → AX (top-left) y

    switch ds[index].kind {
    case .primary:
      s.ratio = Tiling.clampRatio(
        ds[index].vertical ? (point.x - eff.minX) / eff.width : (axY - eff.minY) / eff.height)
    case .stack:
      s.stackRatio = Tiling.clampRatio(
        ds[index].vertical ? (point.x - eff.minX) / eff.width : (axY - eff.minY) / eff.height)
    case .edgeLeft: s.insetLeft = clampInset(point.x - usable.minX, usable.width)
    case .edgeRight: s.insetRight = clampInset(usable.maxX - point.x, usable.width)
    case .windowTop(let slot):
      let raw = Tiling.slots(
        kind, count: count, in: eff, gap: gap, ratio: s.ratio, stackRatio: s.stackRatio)
      if slot < raw.count {
        ensureVInsets(&s, count)
        let top = max(0, axY - raw[slot].minY)
        s.vInsets[slot].top = min(top, max(0, raw[slot].height - 80 - s.vInsets[slot].bottom))
      }
    case .windowBottom(let slot):
      let raw = Tiling.slots(
        kind, count: count, in: eff, gap: gap, ratio: s.ratio, stackRatio: s.stackRatio)
      if slot < raw.count {
        ensureVInsets(&s, count)
        let bottom = max(0, raw[slot].maxY - axY)
        s.vInsets[slot].bottom = min(bottom, max(0, raw[slot].height - 80 - s.vInsets[slot].top))
      }
    }
    session = s
    ratioDirty = true
    applySession()
  }

  private func ensureVInsets(_ s: inout Session, _ count: Int) {
    if s.vInsets.count < count {
      s.vInsets.append(
        contentsOf: Array(repeating: (top: CGFloat(0), bottom: CGFloat(0)), count: count - s.vInsets.count))
    }
  }

  private func primarySplitVertical(_ kind: LayoutKind, _ count: Int) -> Bool? {
    switch kind {
    case .columns where count == 2, .mainLeft: return true
    case .rows where count == 2, .mainTop: return false
    default: return nil
    }
  }

  /// The tiled region after the outer margins are applied (AX top-left coords).
  private func effectiveRect(_ usable: CGRect, _ s: Session) -> CGRect {
    CGRect(
      x: usable.minX + s.insetLeft,
      y: usable.minY + s.insetTop,
      width: max(usable.width * 0.2, usable.width - s.insetLeft - s.insetRight),
      height: max(usable.height * 0.2, usable.height - s.insetTop - s.insetBottom))
  }

  private func clampInset(_ value: CGFloat, _ dimension: CGFloat) -> CGFloat {
    min(max(value, 0), dimension * 0.45)
  }

  func currentLayoutName() -> String? {
    guard let s = session else { return nil }
    let kinds = Tiling.layouts(for: s.windows.count)
    guard !kinds.isEmpty else { return nil }
    return Tiling.name(kinds[s.layoutIndex % kinds.count], count: s.windows.count)
  }

  private func applySession() {
    if let s = session { applyLayout(s) }
  }

  /// Apply the active display's layout, then fit rigid windows once it settles.
  private func applyAndFitActive() {
    guard let id = activeDisplay, sessions[id] != nil else {
      applySession()
      return
    }
    applyAndFit(id)
  }

  /// Tile one display's session (works for any display, not just the active one).
  private func applyLayout(_ s: Session) {
    let count = s.windows.count
    let kinds = Tiling.layouts(for: count)
    guard !kinds.isEmpty else { return }
    let kind = kinds[s.layoutIndex % kinds.count]
    let usable = usableRect(on: s.screen)
    let eff = effectiveRect(usable, s)
    let rects = Tiling.slots(
      kind, count: count, in: eff, gap: gap, ratio: s.ratio, stackRatio: s.stackRatio)
    for slot in 0..<min(count, rects.count) {
      let vi = slot < s.vInsets.count ? s.vInsets[slot] : (top: CGFloat(0), bottom: CGFloat(0))
      let r = Tiling.shrinkVertically(rects[slot], top: vi.top, bottom: vi.bottom)
      place(s.windows[s.order[slot]], in: r, within: usable)
    }
    Log.write("applied \(Tiling.name(kind, count: count)) (count=\(count)) on display \(displayID(s.screen))")
  }

  /// After a layout is applied, some windows may have a minimum size larger than
  /// their slot (e.g. a fixed dialog). Measure what actually fit and nudge the
  /// split ratios so a rigid window gets its minimum and the flexible windows take
  /// the remaining space — "fit the others around the fixed window". Runs once,
  /// after the windows have settled.
  private func fitRigid(for display: CGDirectDisplayID) {
    guard let s = sessions[display], s.windows.count >= 2 else { return }
    let kinds = Tiling.layouts(for: s.windows.count)
    guard !kinds.isEmpty else { return }
    let kind = kinds[s.layoutIndex % kinds.count]
    guard let vertical = primarySplitVertical(kind, s.windows.count),
      let screen = screen(forID: display)
    else { return }
    let eff = effectiveRect(usableRect(on: screen), s)
    let gap = self.gap
    let rects = Tiling.slots(
      kind, count: s.windows.count, in: eff, gap: gap, ratio: s.ratio, stackRatio: s.stackRatio)

    // A window constrains the split only if it's actually *rigid*: its real size
    // exceeds the slot it was given (it couldn't shrink to fit). Flexible windows
    // return 0 so they yield the leftover space to the rigid one.
    func rigidMin(_ slot: Int, width: Bool) -> CGFloat {
      guard slot < rects.count, slot < s.order.count,
        let f = frame(of: s.windows[s.order[slot]])
      else { return 0 }
      let actual = width ? f.width : f.height
      let slotDim = width ? rects[slot].width : rects[slot].height
      return actual > slotDim + gap ? actual : 0
    }

    var next = s
    // Primary split: reserve the rigid side's real footprint.
    let total = vertical ? eff.width : eff.height
    next.ratio = Tiling.fitRatio(
      total: total, min0: rigidMin(0, width: vertical), min1: rigidMin(1, width: vertical),
      fallback: s.ratio)
    // Secondary stack split for 3-window main layouts.
    if s.windows.count == 3, kind == .mainLeft {
      next.stackRatio = Tiling.fitRatio(
        total: eff.height, min0: rigidMin(1, width: false), min1: rigidMin(2, width: false),
        fallback: s.stackRatio)
    } else if s.windows.count == 3, kind == .mainTop {
      next.stackRatio = Tiling.fitRatio(
        total: eff.width, min0: rigidMin(1, width: true), min1: rigidMin(2, width: true),
        fallback: s.stackRatio)
    }

    if abs(next.ratio - s.ratio) > 0.005 || abs(next.stackRatio - s.stackRatio) > 0.005 {
      sessions[display] = next
      applyLayout(next)
      Log.write(
        "fit rigid: display \(display) ratio \(String(format: "%.2f", next.ratio)) "
          + "stack \(String(format: "%.2f", next.stackRatio))")
      if display == activeDisplay, let name = currentLayoutName() { onReorganized?(name) }
    }
  }

  /// Apply a session, then fit rigid windows once the sizes have settled.
  private func applyAndFit(_ display: CGDirectDisplayID) {
    guard let s = sessions[display] else { return }
    applyLayout(s)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
      self?.fitRigid(for: display)
    }
  }

  /// A window count → a valid layout index that fits.
  private func normalized(_ s: Session) -> Session {
    var n = s
    let kinds = Tiling.layouts(for: n.windows.count)
    n.layoutIndex = kinds.isEmpty ? 0 : min(n.layoutIndex, kinds.count - 1)
    n.order = Array(0..<n.windows.count)
    return n
  }

  /// Each window's display at the last reconcile — to tell a *move* from a window
  /// that's merely sitting there or newly opened.
  private var lastSeen: [(window: AXUIElement, display: CGDirectDisplayID)] = []

  private func lastSeenDisplay(_ window: AXUIElement) -> CGDirectDisplayID? {
    lastSeen.first { CFEqual($0.window, window) }?.display
  }

  /// Snapshot where every window is (called on mouse-down) so a drag that follows
  /// is detected as a move even if it's the first interaction.
  func seedLastSeen() {
    lastSeen = tileableWindows().compactMap { w in
      currentScreen(of: w).map { (w, displayID($0)) }
    }
  }

  /// On mouse-up: windows that left a boxed display drop out (or, if they landed
  /// on another boxed display, join it); and a window *dragged onto* a boxed
  /// display joins its layout. The set logic is the pure, tested `Reconcile.step`.
  func reconcileDisplays() {
    // The window universe: everything any session tracks + everything on screen.
    var wins: [AXUIElement] = []
    func id(of w: AXUIElement) -> Int {
      if let i = wins.firstIndex(where: { CFEqual($0, w) }) { return i }
      wins.append(w)
      return wins.count - 1
    }
    for s in sessions.values { for w in s.windows { _ = id(of: w) } }
    for w in tileableWindows() { _ = id(of: w) }

    // Build the pure inputs.
    var sessIn: [Int: [Int]] = [:]
    for (display, s) in sessions { sessIn[Int(display)] = s.windows.map { id(of: $0) } }
    var current: [Int: Int] = [:]
    var previous: [Int: Int] = [:]
    for (i, w) in wins.enumerated() {
      if let screen = currentScreen(of: w) { current[i] = Int(displayID(screen)) }
      if let prev = lastSeenDisplay(w) { previous[i] = Int(prev) }
    }

    let result = Reconcile.step(sessions: sessIn, current: current, previous: previous)

    // Rebuild sessions, preserving each display's layout/ratios where the window
    // set is unchanged and re-normalizing where it changed.
    var rebuilt: [CGDirectDisplayID: Session] = [:]
    var touched: Set<CGDirectDisplayID> = []
    for (displayInt, ids) in result {
      let display = CGDirectDisplayID(displayInt)
      let newWindows = ids.map { wins[$0] }
      guard let old = sessions[display] else { continue }
      if sameWindowSet(old.windows, newWindows) {
        rebuilt[display] = old
      } else {
        var n = old
        n.windows = newWindows
        n.vInsets = []
        rebuilt[display] = normalized(n)
        touched.insert(display)
        Log.write("reconcile: display \(display) now has \(newWindows.count) window(s)")
      }
    }
    // Displays that lost their session entirely were boxed before → re-tiled away.
    for display in sessions.keys where rebuilt[display] == nil { touched.insert(display) }

    sessions = rebuilt
    lastSeen = wins.compactMap { w in currentScreen(of: w).map { (w, displayID($0)) } }
    for display in touched where sessions[display] != nil { applyAndFit(display) }
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

  /// Place a window in its slot. Resizable windows fill the slot; a non-resizable
  /// window keeps its size, anchored top-right (it can't be stretched). The
  /// fill/keep decision is the pure, tested `Tiling.placement`.
  private func place(_ window: AXUIElement, in slot: CGRect, within bounds: CGRect) {
    let resizable = isSizeSettable(window)
    let target = Tiling.placement(slot: slot, natural: naturalSize(of: window), resizable: resizable)
    setPosition(window, target.origin)
    if resizable { setSize(window, target.size) }
    setPosition(window, target.origin)  // re-anchor for apps that recenter on resize
    // If the window has a minimum size larger than its slot, it stayed big and may
    // now spill off the display — nudge it back on-screen. Skip mid-drag so a
    // resize against a fixed window doesn't jitter.
    if !draggingSplitter, let actual = frame(of: window) {
      let fitted = Tiling.clampOnscreen(actual, within: bounds)
      if abs(fitted.minX - actual.minX) > 0.5 || abs(fitted.minY - actual.minY) > 0.5 {
        setPosition(window, fitted.origin)
      }
    }
  }

  // MARK: - Natural sizes

  /// Record a window's natural size once (at creation), if not already known.
  private func recordNatural(_ window: AXUIElement) {
    guard !naturalSizes.contains(where: { CFEqual($0.window, window) }),
      let size = frame(of: window)?.size
    else { return }
    naturalSizes.append((window, size))
  }

  /// The recorded natural size, or .zero (unknown → fill) if we never saw it open.
  private func naturalSize(of window: AXUIElement) -> CGSize {
    naturalSizes.first(where: { CFEqual($0.window, window) })?.size ?? .zero
  }

  /// The user manually resized a window — treat its new size as preferred.
  func handleWindowResized(_ window: AXUIElement) {
    guard !wasRecentlySized(window), let size = frame(of: window)?.size else { return }
    if let i = naturalSizes.firstIndex(where: { CFEqual($0.window, window) }) {
      naturalSizes[i].size = size
    } else {
      naturalSizes.append((window, size))
    }
    Log.write("user resized -> natural \(Int(size.width))×\(Int(size.height))")
  }

  private func markSized(_ window: AXUIElement) {
    recentlySized.append((window, .now() + .milliseconds(350)))
  }

  private func wasRecentlySized(_ window: AXUIElement) -> Bool {
    let now = DispatchTime.now()
    recentlySized.removeAll { $0.until < now }
    return recentlySized.contains { CFEqual($0.window, window) }
  }

  private func windowArea(_ window: AXUIElement) -> CGFloat {
    guard let f = frame(of: window) else { return 0 }
    return f.width * f.height
  }

  private func setPosition(_ window: AXUIElement, _ origin: CGPoint) {
    var o = origin
    if let value = AXValueCreate(.cgPoint, &o) {
      AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }
  }

  private func setSize(_ window: AXUIElement, _ size: CGSize) {
    markSized(window)  // so the resulting resize echo isn't read as a user resize
    var s = size
    if let value = AXValueCreate(.cgSize, &s) {
      AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
    }
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

  // MARK: - Displays

  func displayID(_ screen: NSScreen) -> CGDirectDisplayID {
    (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
      ?? 0
  }

  private func screen(forID id: CGDirectDisplayID) -> NSScreen? {
    NSScreen.screens.first { displayID($0) == id }
  }

  /// The display the cursor is currently on (where organize/edit should target).
  func screenUnderCursor() -> NSScreen? {
    let point = NSEvent.mouseLocation
    return NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
  }

  /// Which display a window currently sits on (by its center), if any.
  /// Whether a window belongs to `screen` — i.e. it's the display the window
  /// overlaps most (see `currentScreen`). The single source of truth for "is this
  /// window on this display", so organize, edit, reconcile and fullscreen all
  /// agree; a window taller/wider than where it sits still counts on the display
  /// it mostly covers, rather than falling through a strict center-point test.
  private func isOn(_ window: AXUIElement, _ screen: NSScreen) -> Bool {
    guard let s = currentScreen(of: window) else { return false }
    return displayID(s) == displayID(screen)
  }

  private func currentScreen(of window: AXUIElement) -> NSScreen? {
    guard let f = frame(of: window) else { return nil }
    // Use the display the window overlaps most, not a strict center-point test: a
    // window taller/wider than its display (e.g. a fixed-size dialog dragged near
    // an edge) has its center fall off the display and would otherwise map to no
    // display at all — orphaning it during reconcile.
    let screens = NSScreen.screens
    let cocoa = axToCocoa(f)
    guard let i = Tiling.maxOverlapIndex(of: cocoa, among: screens.map { $0.frame }) else {
      return nil
    }
    return screens[i]
  }

  // MARK: - Fullscreen

  private func isFullscreen(_ window: AXUIElement) -> Bool {
    var value: CFTypeRef?
    if AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &value) == .success,
      let flag = value as? Bool
    {
      return flag
    }
    return false
  }

  /// A native-fullscreen window on the given display, if any.
  private func fullscreenWindow(on screen: NSScreen) -> AXUIElement? {
    tileableWindows().first { w in
      isOn(w, screen) && isFullscreen(w)
    }
  }

  /// Is the display under the cursor showing a native-fullscreen window? Tiling
  /// can't touch a fullscreen Space, so boxed offers "minimize" instead of edit.
  func isFullscreenContext() -> Bool {
    guard let screen = screenUnderCursor() else { return false }
    return fullscreenWindow(on: screen) != nil
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
