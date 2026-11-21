import XCTest

@testable import ToolCore

final class NavigationHistoryTests: XCTestCase {
  func testTraversalAndNewBranch() {
    var history = NavigationHistory("home")
    XCTAssertNil(history.back())
    XCTAssertNil(history.forward())
    XCTAssertTrue(history.visit("text"))
    XCTAssertFalse(history.visit("text"))
    history.visit("home")
    history.visit("toolbox/json")
    XCTAssertEqual(history.back(), "home")
    XCTAssertEqual(history.back(), "text")
    XCTAssertEqual(history.forward(), "home")
    history.visit("git")
    XCTAssertFalse(history.canGoForward)
    XCTAssertEqual(history.pages, ["home", "text", "home", "git"])
  }
  func testBoundedHistoryAndRepeatedTraversal() {
    var history = NavigationHistory(0, limit: 100)
    for n in 1...1000 { history.visit(n) }
    XCTAssertEqual(history.pages.count, 100)
    for n in (901..<1000).reversed() { XCTAssertEqual(history.back(), n) }
    XCTAssertNil(history.back())
    for n in 902...1000 { XCTAssertEqual(history.forward(), n) }
    XCTAssertNil(history.forward())
  }
}
