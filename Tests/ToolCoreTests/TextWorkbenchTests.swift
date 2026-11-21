import Foundation
import XCTest

@testable import ToolCore

final class TextWorkbenchTests: XCTestCase {
  func testUTF8ImportPreservesContentWithoutWriting() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let bytes = Data([0xef, 0xbb, 0xbf]) + Data("你好\r\n🧰\n".utf8)
    try bytes.write(to: url)
    XCTAssertEqual(try TextWorkbench.read(url), "你好\r\n🧰\n")
    XCTAssertEqual(try Data(contentsOf: url), bytes)
    XCTAssertThrowsError(try TextWorkbench.read(url, limit: 3))
    try Data([0xff, 0xfe, 0, 0]).write(to: url)
    XCTAssertThrowsError(try TextWorkbench.read(url))
    XCTAssertThrowsError(try TextWorkbench.read(URL(fileURLWithPath: "/dev/zero")))
  }
  func testPreviewBudgetAndExternalResourcePolicy() async throws {
    let missing = URL(fileURLWithPath: "/missing-worker")
    do {
      _ = try await TextWorkbench.preview(
        String(repeating: "a", count: TextWorkbench.previewBytes + 1), executable: missing)
      XCTFail("Must reject before launching")
    } catch { XCTAssertTrue(error.localizedDescription.contains("4 MiB")) }
    let html = TextWorkbench.page("<p>你好</p>")
    XCTAssertTrue(html.contains("default-src 'none'"))
    XCTAssertTrue(html.contains("img-src 'none'"))
    XCTAssertTrue(html.contains("<p>你好</p>"))
    XCTAssertFalse(html.contains("<script"))
  }
  func testLineBudgetAndJoinedLines() {
    XCTAssertTrue(
      TextWorkbench.acceptsLines(String(repeating: "a", count: TextWorkbench.lineBytes)))
    XCTAssertFalse(
      TextWorkbench.acceptsLines(String(repeating: "a", count: TextWorkbench.lineBytes + 1)))
    XCTAssertTrue(TextWorkbench.acceptsLines("x\ny", prefix: 100_000, suffix: 100_000))
    XCTAssertFalse(TextWorkbench.acceptsLines("", prefix: 100_000, suffix: 100_000))
    XCTAssertFalse(TextWorkbench.acceptsLines(String(repeating: "你", count: 50_000)))
  }
}
