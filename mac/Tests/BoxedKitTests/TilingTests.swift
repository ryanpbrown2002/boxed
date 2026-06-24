import CoreGraphics
import XCTest

@testable import BoxedKit

final class TilingTests: XCTestCase {
  let rect = CGRect(x: 0, y: 0, width: 1000, height: 600)

  // MARK: "compact" (don't-stretch) detection

  func testCompactDetection() {
    let screen = CGSize(width: 1710, height: 1069)
    // Genuinely small windows (e.g. a small Preview) are compact…
    XCTAssertTrue(Tiling.isCompact(CGSize(width: 708, height: 276), in: screen))
    XCTAssertTrue(Tiling.isCompact(CGSize(width: 400, height: 300), in: screen))
    // …but a near-half window is NOT — the stricter threshold excludes it.
    XCTAssertFalse(Tiling.isCompact(CGSize(width: 847, height: 488), in: screen))
    // Full-screen and full-width windows are never compact.
    XCTAssertFalse(Tiling.isCompact(screen, in: screen))
    XCTAssertFalse(Tiling.isCompact(CGSize(width: 1600, height: 200), in: screen))
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
