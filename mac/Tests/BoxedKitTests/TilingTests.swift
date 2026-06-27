import CoreGraphics
import XCTest

@testable import BoxedKit

final class TilingTests: XCTestCase {
  let rect = CGRect(x: 0, y: 0, width: 1000, height: 600)

  // MARK: "compact" (don't-stretch) detection

  func testFitRatio() {
    // Both fit at the fallback → keep the fallback (don't disturb the user).
    XCTAssertEqual(Tiling.fitRatio(total: 1000, min0: 400, min1: 400, fallback: 0.5), 0.5, accuracy: 0.001)
    // Side 0 is rigid (needs 700) → grow it to fit; side 1 takes the rest.
    XCTAssertEqual(Tiling.fitRatio(total: 1000, min0: 700, min1: 200, fallback: 0.5), 0.7, accuracy: 0.001)
    // Side 1 rigid (needs 700) → shrink side 0.
    XCTAssertEqual(Tiling.fitRatio(total: 1000, min0: 200, min1: 700, fallback: 0.5), 0.3, accuracy: 0.001)
    // Both rigid, can't both fit → proportional.
    XCTAssertEqual(Tiling.fitRatio(total: 1000, min0: 600, min1: 600, fallback: 0.5), 0.5, accuracy: 0.001)
    // Extreme → clamped so neither collapses.
    XCTAssertEqual(Tiling.fitRatio(total: 1000, min0: 980, min1: 50, fallback: 0.5), 1 - Tiling.minRatio, accuracy: 0.001)
  }

  func testUndoShouldCapture() {
    // First organize of a display (no session) → capture the pre-organize state.
    XCTAssertTrue(Undo.shouldCapture(hasSession: false, sameWindowSet: false))
    XCTAssertTrue(Undo.shouldCapture(hasSession: false, sameWindowSet: true))
    // Re-snap / reformat / reset the SAME set → keep the original snapshot.
    XCTAssertFalse(Undo.shouldCapture(hasSession: true, sameWindowSet: true))
    // The set changed (window opened/closed) → it's a new arrangement → capture.
    XCTAssertTrue(Undo.shouldCapture(hasSession: true, sameWindowSet: false))
  }

  func testWeightedLengths() {
    // Nothing rigid → even split.
    XCTAssertEqual(Tiling.weightedLengths(mins: [0, 0, 0], total: 900), [300, 300, 300])
    // One rigid (600); the two flexibles split the 400 of slack.
    let w = Tiling.weightedLengths(mins: [600, 0, 0], total: 1000)
    XCTAssertEqual(w[0], 600, accuracy: 0.001)
    XCTAssertEqual(w[1], 200, accuracy: 0.001)
    XCTAssertEqual(w[2], 200, accuracy: 0.001)
    // All rigid but they fit → each gets its min plus a proportional share of slack.
    let f = Tiling.weightedLengths(mins: [400, 400], total: 1000)
    XCTAssertEqual(f[0], 500, accuracy: 0.001)
    XCTAssertEqual(f[1], 500, accuracy: 0.001)
    // Over-constrained → protect the largest mins first; the rest take what's left.
    // (Docker 940 + Safari 574 + Code 400 = 1914 can't fit 1702.)
    let o = Tiling.weightedLengths(mins: [940, 574, 400], total: 1702)
    XCTAssertEqual(o[0], 940, accuracy: 0.001)  // Docker protected
    XCTAssertEqual(o[1], 574, accuracy: 0.001)  // Safari protected
    XCTAssertEqual(o[2], 188, accuracy: 0.001)  // Code takes the remainder
    XCTAssertEqual(Tiling.weightedLengths(mins: [], total: 500), [])
  }

  func testLayoutFits() {
    let size = CGSize(width: 1702, height: 993)
    let docker = CGSize(width: 940, height: 600)
    let safari = CGSize(width: 574, height: 0)
    let code = CGSize(width: 400, height: 0)
    // Three windows 940+574+400 wide can't fit side by side → Columns infeasible.
    XCTAssertFalse(Tiling.fits(.columns, count: 3, in: size, mins: [docker, safari, code]))
    // But Rows fits (each spans the full width; 600 + 0 + 0 of height fits).
    XCTAssertTrue(Tiling.fits(.rows, count: 3, in: size, mins: [docker, safari, code]))
    // Main + stack: Docker main (940) + widest stack (574) = 1514 ≤ 1702 → fits.
    XCTAssertTrue(Tiling.fits(.mainLeft, count: 3, in: size, mins: [docker, safari, code]))
    // No minimums → everything fits.
    XCTAssertTrue(Tiling.fits(.grid, count: 4, in: size, mins: []))
  }

  func testWeightedColumnsRowsGrid() {
    let r = CGRect(x: 0, y: 0, width: 1000, height: 600)
    // Rigid window (min width 600) in column 0 of 3 → 600 / 200 / 200.
    let cols = Tiling.slots(
      .columns, count: 3, in: r, gap: 0, mins: [CGSize(width: 600, height: 0), .zero, .zero])
    XCTAssertEqual(cols[0].width, 600, accuracy: 0.001)
    XCTAssertEqual(cols[1].width, 200, accuracy: 0.001)
    XCTAssertEqual(cols[2].minX, 800, accuracy: 0.001)
    // Rigid height 400 in row 1 of 3 → 100 / 400 / 100.
    let rows = Tiling.slots(
      .rows, count: 3, in: r, gap: 0, mins: [.zero, CGSize(width: 0, height: 400), .zero])
    XCTAssertEqual(rows[1].height, 400, accuracy: 0.001)
    XCTAssertEqual(rows[0].height, 100, accuracy: 0.001)
    // Grid 2×2, rigid cell 0 needs 700×450 → col0=700/col1=300, row0=450/row1=150.
    let g = Tiling.slots(
      .grid, count: 4, in: r, gap: 0, mins: [CGSize(width: 700, height: 450), .zero, .zero, .zero])
    XCTAssertEqual(g[0].width, 700, accuracy: 0.001)
    XCTAssertEqual(g[0].height, 450, accuracy: 0.001)
    XCTAssertEqual(g[1].width, 300, accuracy: 0.001)  // top-right column
    XCTAssertEqual(g[2].height, 150, accuracy: 0.001)  // bottom-left row
    // No mins → unchanged even grid (regression guard).
    let even = Tiling.slots(.grid, count: 4, in: r, gap: 0)
    XCTAssertEqual(even[0].width, 500, accuracy: 0.001)
    XCTAssertEqual(even[0].height, 300, accuracy: 0.001)
  }

  func testMaxOverlapIndex() {
    // Two side-by-side displays (Cocoa coords): left 0..1710, right 1710..3630.
    let left = CGRect(x: 0, y: 0, width: 1710, height: 1107)
    let right = CGRect(x: 1710, y: 516, width: 1920, height: 1080)
    // Fully inside the right display.
    XCTAssertEqual(Tiling.maxOverlapIndex(of: CGRect(x: 2000, y: 600, width: 400, height: 300), among: [left, right]), 1)
    // Regression guard for unifying display membership on overlap (not center):
    // this window's CENTER (2400,1700) lies past the right display's bottom edge
    // (y 516..1596), so the old center-point test mapped it to NO display and
    // dropped it. It still overlaps only the right display, so it belongs to it.
    let centerOffDisplay = CGRect(x: 2000, y: 1500, width: 800, height: 400)
    XCTAssertFalse(right.contains(CGPoint(x: centerOffDisplay.midX, y: centerOffDisplay.midY)))
    XCTAssertEqual(Tiling.maxOverlapIndex(of: centerOffDisplay, among: [left, right]), 1)
    // Straddling: more area on the left → left wins.
    XCTAssertEqual(Tiling.maxOverlapIndex(of: CGRect(x: 1500, y: 600, width: 400, height: 300), among: [left, right]), 0)
    // Off both displays entirely → nil.
    XCTAssertNil(Tiling.maxOverlapIndex(of: CGRect(x: 5000, y: 5000, width: 100, height: 100), among: [left, right]))
  }

  func testTouchesEdge() {
    let layout = CGRect(x: 0, y: 0, width: 1000, height: 600)
    // Regression guard: gap-inset slots still read as touching the outer edge.
    let rows = Tiling.slots(.rows, count: 2, in: layout, gap: 8)  // top / bottom
    XCTAssertEqual(Tiling.touchesEdge(slot: rows[0], layout: layout, gap: 8).top, true)
    XCTAssertEqual(Tiling.touchesEdge(slot: rows[0], layout: layout, gap: 8).bottom, false)
    XCTAssertEqual(Tiling.touchesEdge(slot: rows[1], layout: layout, gap: 8).bottom, true)
    XCTAssertEqual(Tiling.touchesEdge(slot: rows[1], layout: layout, gap: 8).top, false)
    // A full-height column touches both.
    let col = Tiling.slots(.columns, count: 2, in: layout, gap: 8)[0]
    let both = Tiling.touchesEdge(slot: col, layout: layout, gap: 8)
    XCTAssertTrue(both.top && both.bottom)
  }

  func testClampOnscreen() {
    let b = CGRect(x: 0, y: 0, width: 1000, height: 800)
    // Fully inside → unchanged.
    XCTAssertEqual(
      Tiling.clampOnscreen(CGRect(x: 100, y: 100, width: 200, height: 200), within: b),
      CGRect(x: 100, y: 100, width: 200, height: 200))
    // Spills past right/bottom → pulled back in (same size).
    XCTAssertEqual(
      Tiling.clampOnscreen(CGRect(x: 900, y: 700, width: 300, height: 300), within: b),
      CGRect(x: 700, y: 500, width: 300, height: 300))
    // Spills past left/top (negative origin) → pulled back to the edge. This is the
    // edge-divider case: a handle centered on x=0 would straddle the screen border.
    XCTAssertEqual(
      Tiling.clampOnscreen(CGRect(x: -8, y: -8, width: 16, height: 200), within: b),
      CGRect(x: 0, y: 0, width: 16, height: 200))
    // Bigger than the bounds → top-left aligned (title bar stays reachable).
    XCTAssertEqual(
      Tiling.clampOnscreen(CGRect(x: 50, y: 50, width: 1200, height: 900), within: b),
      CGRect(x: 0, y: 0, width: 1200, height: 900))
  }

  func testShrinkVertically() {
    let r = CGRect(x: 10, y: 20, width: 200, height: 400)
    XCTAssertEqual(Tiling.shrinkVertically(r, top: 0, bottom: 0), r)  // no change
    XCTAssertEqual(
      Tiling.shrinkVertically(r, top: 50, bottom: 30),
      CGRect(x: 10, y: 70, width: 200, height: 320))  // top down 50, height -80
    XCTAssertEqual(
      Tiling.shrinkVertically(r, top: 500, bottom: 0, minHeight: 80).height, 80, accuracy: 0.001)
    // x/width never change.
    XCTAssertEqual(Tiling.shrinkVertically(r, top: 100, bottom: 0).minX, 10, accuracy: 0.001)
  }

  func testPlacement() {
    let slot = CGRect(x: 100, y: 50, width: 800, height: 600)
    // A resizable window always fills its slot — even a small one (organizing uses
    // the space; guards the "small window stayed small on a big display" gripe).
    XCTAssertEqual(
      Tiling.placement(slot: slot, natural: CGSize(width: 700, height: 500), resizable: true), slot)
    XCTAssertEqual(
      Tiling.placement(slot: slot, natural: CGSize(width: 300, height: 200), resizable: true), slot)
    // Unknown natural (.zero) → fill.
    XCTAssertEqual(Tiling.placement(slot: slot, natural: .zero, resizable: true), slot)
    // Non-resizable keeps its size (capped to the slot), anchored top-right.
    XCTAssertEqual(
      Tiling.placement(slot: slot, natural: CGSize(width: 300, height: 200), resizable: false),
      CGRect(x: 600, y: 50, width: 300, height: 200))
    XCTAssertEqual(
      Tiling.placement(slot: slot, natural: CGSize(width: 2000, height: 2000), resizable: false),
      slot)
  }

  // MARK: adjustable primary split (draggable edge)

  func testRatioAwarePrimarySplit() {
    let r = CGRect(x: 0, y: 0, width: 1000, height: 600)
    // Left/Right at 0.6 → left 600, right 400 meeting at x=600.
    let lr = Tiling.slots(.columns, count: 2, in: r, gap: 0, ratio: 0.6)
    XCTAssertEqual(lr[0].width, 600, accuracy: 0.001)
    XCTAssertEqual(lr[1].width, 400, accuracy: 0.001)
    XCTAssertEqual(lr[1].minX, 600, accuracy: 0.001)
    // Top/Bottom at 0.7 → top 420, bottom 180.
    let tb = Tiling.slots(.rows, count: 2, in: r, gap: 0, ratio: 0.7)
    XCTAssertEqual(tb[0].height, 420, accuracy: 0.001)
    XCTAssertEqual(tb[1].height, 180, accuracy: 0.001)
    // Main + stack at 0.65 → main width 650.
    let m = Tiling.slots(.mainLeft, count: 3, in: r, gap: 0, ratio: 0.65)
    XCTAssertEqual(m[0].width, 650, accuracy: 0.001)
    // Default (no ratio) stays an even split.
    XCTAssertEqual(Tiling.slots(.columns, count: 2, in: r, gap: 0)[0].width, 500, accuracy: 0.001)
  }

  func testStackRatioSecondarySplit() {
    let r = CGRect(x: 0, y: 0, width: 1000, height: 600)
    // Main + stack (3 windows): main at 0.5, stack split at 0.7.
    let m = Tiling.slots(.mainLeft, count: 3, in: r, gap: 0, ratio: 0.5, stackRatio: 0.7)
    XCTAssertEqual(m[0].width, 500, accuracy: 0.001)  // main, full height
    XCTAssertEqual(m[1].height, 420, accuracy: 0.001)  // top of stack
    XCTAssertEqual(m[2].height, 180, accuracy: 0.001)  // bottom of stack
    XCTAssertEqual(m[2].minY, 420, accuracy: 0.001)
    // Default stack split is even.
    let even = Tiling.slots(.mainLeft, count: 3, in: r, gap: 0)
    XCTAssertEqual(even[1].height, 300, accuracy: 0.001)
  }

  func testCentered() {
    let r = CGRect(x: 0, y: 0, width: 1000, height: 600)
    XCTAssertEqual(
      Tiling.centered(CGSize(width: 400, height: 200), in: r),
      CGRect(x: 300, y: 200, width: 400, height: 200))
    // Offset origin is respected.
    XCTAssertEqual(
      Tiling.centered(CGSize(width: 100, height: 100), in: CGRect(x: 200, y: 50, width: 400, height: 400)),
      CGRect(x: 350, y: 200, width: 100, height: 100))
  }

  func testClampRatio() {
    XCTAssertEqual(Tiling.clampRatio(0.5), 0.5, accuracy: 0.001)
    XCTAssertEqual(Tiling.clampRatio(0.001), Tiling.minRatio, accuracy: 0.001)  // floored
    XCTAssertEqual(Tiling.clampRatio(0.999), 1 - Tiling.minRatio, accuracy: 0.001)  // capped
  }

  // MARK: which layouts are offered per count

  func testLayoutsPerCount() {
    XCTAssertEqual(Tiling.layouts(for: 1), [.columns])
    XCTAssertEqual(Tiling.layouts(for: 2), [.columns, .rows])
    XCTAssertEqual(Tiling.layouts(for: 3), [.mainLeft, .columns, .rows, .mainTop])
    XCTAssertEqual(Tiling.layouts(for: 3).first, .mainLeft)  // main+stack is the default
    XCTAssertEqual(Tiling.layouts(for: 4), [.grid, .columns, .rows, .mainLeft])
    XCTAssertEqual(Tiling.layouts(for: 6), [.bsp])  // 5+ falls back
    XCTAssertEqual(Tiling.layouts(for: 0), [])
  }

  // MARK: two tabs — left/right vs top/bottom (the core case)

  func testTwoTabsLeftRight() {
    let s = Tiling.slots(.columns, count: 2, in: rect, gap: 0)
    XCTAssertEqual(s, [
      CGRect(x: 0, y: 0, width: 500, height: 600),
      CGRect(x: 500, y: 0, width: 500, height: 600)
    ])
    XCTAssertEqual(Tiling.name(.columns, count: 2), "Left / Right")
  }

  func testTwoTabsTopBottom() {
    let s = Tiling.slots(.rows, count: 2, in: rect, gap: 0)
    XCTAssertEqual(s, [
      CGRect(x: 0, y: 0, width: 1000, height: 300),
      CGRect(x: 0, y: 300, width: 1000, height: 300)
    ])
    XCTAssertEqual(Tiling.name(.rows, count: 2), "Top / Bottom")
  }

  // MARK: four tabs — quad grid order is TL, TR, BL, BR

  func testFourTabGrid() {
    let s = Tiling.slots(.grid, count: 4, in: rect, gap: 0)
    XCTAssertEqual(s, [
      CGRect(x: 0, y: 0, width: 500, height: 300),
      CGRect(x: 500, y: 0, width: 500, height: 300),
      CGRect(x: 0, y: 300, width: 500, height: 300),
      CGRect(x: 500, y: 300, width: 500, height: 300)
    ])
  }

  func testGridAdjustableSplits() {
    let r = CGRect(x: 0, y: 0, width: 1000, height: 600)
    // gridX 0.7 → columns 700/300; gridY 0.6 → rows 360/240.
    let g = Tiling.slots(.grid, count: 4, in: r, gap: 0, gridX: 0.7, gridY: 0.6)
    XCTAssertEqual(g[0], CGRect(x: 0, y: 0, width: 700, height: 360))  // top-left
    XCTAssertEqual(g[1], CGRect(x: 700, y: 0, width: 300, height: 360))  // top-right
    XCTAssertEqual(g[2], CGRect(x: 0, y: 360, width: 700, height: 240))  // bottom-left
    XCTAssertEqual(g[3], CGRect(x: 700, y: 360, width: 300, height: 240))  // bottom-right
    // A rigid cell (min width 800 in column 0) clamps gridX up even if it asks lower.
    let rigid = Tiling.slots(
      .grid, count: 4, in: r, gap: 0,
      mins: [CGSize(width: 800, height: 0), .zero, .zero, .zero], gridX: 0.3, gridY: 0.5)
    XCTAssertEqual(rigid[0].width, 800, accuracy: 0.001)
  }

  // MARK: three tabs — main + stack puts the big one on the left

  func testThreeTabMainLeft() {
    let s = Tiling.slots(.mainLeft, count: 3, in: rect, gap: 0)
    XCTAssertEqual(s[0], CGRect(x: 0, y: 0, width: 500, height: 600))  // main
    XCTAssertEqual(s[1], CGRect(x: 500, y: 0, width: 500, height: 300))  // top-right
    XCTAssertEqual(s[2], CGRect(x: 500, y: 300, width: 500, height: 300))  // bottom-right
  }

  // MARK: invariants across every offered layout (snap-into-place correctness)

  func testEveryLayoutTilesCleanly() {
    for count in 1...4 {
      for kind in Tiling.layouts(for: count) {
        let slots = Tiling.slots(kind, count: count, in: rect, gap: 0)
        XCTAssertEqual(slots.count, count, "\(kind) for \(count) should produce \(count) slots")

        // Slots cover the whole area with no gaps and no overlap.
        let area = slots.reduce(CGFloat(0)) { $0 + $1.width * $1.height }
        XCTAssertEqual(
          area, rect.width * rect.height, accuracy: 1, "\(kind) for \(count) should fill the rect")

        // Every slot stays inside the rect.
        for slot in slots {
          XCTAssertTrue(
            rect.insetBy(dx: -0.5, dy: -0.5).contains(slot), "\(kind) slot \(slot) escaped the rect")
        }
      }
    }
  }

  // MARK: gaps inset each slot

  func testGapInsetsEachSlot() {
    let s = Tiling.slots(.columns, count: 2, in: rect, gap: 10)
    XCTAssertEqual(s[0], CGRect(x: 5, y: 5, width: 490, height: 590))
    XCTAssertEqual(s[1], CGRect(x: 505, y: 5, width: 490, height: 590))
  }

  // MARK: 5+ windows fall back to BSP and still produce one slot each

  func testBeyondFourUsesBSP() {
    let s = Tiling.slots(.bsp, count: 6, in: rect, gap: 0)
    XCTAssertEqual(s.count, 6)
    let area = s.reduce(CGFloat(0)) { $0 + $1.width * $1.height }
    XCTAssertEqual(area, rect.width * rect.height, accuracy: 1)
  }
}
