import XCTest

@testable import BoxedKit

final class ReconcileTests: XCTestCase {
  func testWindowLeavesToNonBoxedDisplay() {
    // 11 moved to display 2 (not boxed) → dropped, not re-added.
    XCTAssertEqual(
      Reconcile.step(sessions: [1: [10, 11]], current: [10: 1, 11: 2], previous: [10: 1, 11: 1]),
      [1: [10]])
  }

  func testBoxedToBoxedMove() {
    // 11 leaves boxed display 1 and joins boxed display 2.
    XCTAssertEqual(
      Reconcile.step(
        sessions: [1: [10, 11], 2: [20]], current: [10: 1, 11: 2, 20: 2],
        previous: [10: 1, 11: 1, 20: 2]),
      [1: [10], 2: [20, 11]])
  }

  func testDragOntoBoxedDisplayJoins() {
    // 50 was on a non-boxed display, dragged onto boxed display 1 → joins. (The bug.)
    XCTAssertEqual(
      Reconcile.step(sessions: [1: [10]], current: [10: 1, 50: 1], previous: [50: 2]),
      [1: [10, 50]])
  }

  func testNewWindowDoesNotAutoJoin() {
    // 99 appeared on boxed display 1 but has no previous display → not pulled in.
    XCTAssertEqual(
      Reconcile.step(sessions: [1: [10]], current: [10: 1, 99: 1], previous: [10: 1]),
      [1: [10]])
  }

  func testEmptiedDisplayDropsOut() {
    XCTAssertEqual(
      Reconcile.step(sessions: [1: [10]], current: [10: 2], previous: [10: 1]),
      [:])
  }
}
