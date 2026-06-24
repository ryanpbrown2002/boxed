import CoreGraphics
import XCTest

@testable import BoxedKit

final class LayoutTests: XCTestCase {
  let rect = CGRect(x: 0, y: 0, width: 1000, height: 600)

  func testSingleFillsRect() {
    XCTAssertEqual(Layout.bsp(count: 1, in: rect, gap: 0), [rect])
  }

  func testTwoEqualHalves() {
    let t = Layout.bsp(count: 2, in: rect, gap: 0)
    XCTAssertEqual(t.count, 2)
    XCTAssertEqual(t[0].width, 500, accuracy: 0.001)
    XCTAssertEqual(t[1].minX, 500, accuracy: 0.001)
  }

  func testAreaConserved() {
    let f = Layout.bsp(count: 5, in: rect, gap: 0)
    let area = f.reduce(CGFloat(0)) { $0 + $1.width * $1.height }
    XCTAssertEqual(area, rect.width * rect.height, accuracy: 1)
  }

  func testZeroIsEmpty() {
    XCTAssertTrue(Layout.bsp(count: 0, in: rect).isEmpty)
  }
}
