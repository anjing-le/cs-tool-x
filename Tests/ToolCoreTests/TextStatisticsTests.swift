import Foundation
import XCTest
@testable import ToolCore

final class TextStatisticsTests: XCTestCase {
  func testUnicodeAndExplicitCountingRules() throws {
    let text = "你好 hi 12!\r\n\r\n再见don't 👨‍👩‍👧‍👦\n"
    let value = try TextStatisticsIndex(text).snapshot
    XCTAssertEqual(value.characters, 21); XCTAssertEqual(value.nonWhitespace, 15)
    XCTAssertEqual(value.han, 4); XCTAssertEqual(value.englishWords, 2)
    XCTAssertEqual(value.digits, 2); XCTAssertEqual(value.punctuation, 2)
    XCTAssertEqual(value.whitespace, 6); XCTAssertEqual(value.lines, 4)
    XCTAssertEqual(value.emptyLines, 2); XCTAssertEqual(value.paragraphs, 2)
    XCTAssertEqual(value.utf8Bytes, text.utf8.count)
    XCTAssertEqual(try TextStatisticsIndex().snapshot.lines, 0)
    let crlf = try TextStatisticsIndex("\r\n").snapshot
    XCTAssertEqual(crlf.characters, 1); XCTAssertEqual(crlf.lines, 2)
    XCTAssertEqual(crlf.emptyLines, 2)
  }
  func testLineAlignedAggregationAndSelections() throws {
    let text = String(repeating: "alpha你好 12!\r\n", count: 1000)
    let index = try TextStatisticsIndex(text)
    let value = index.snapshot
    XCTAssertEqual(value.characters, 12_000); XCTAssertEqual(value.nonWhitespace, 10_000)
    XCTAssertEqual(value.han, 2000); XCTAssertEqual(value.englishWords, 1000)
    XCTAssertEqual(value.lines, 1001); XCTAssertEqual(value.nonEmptyLines, 1000)
    XCTAssertEqual(value.paragraphs, 1)
    let range = NSRange(location: 8190, length: 2500)
    XCTAssertEqual(try index.selection([range]), try TextStatisticsIndex((text as NSString).substring(with: range)).snapshot)
    XCTAssertEqual(try index.selection([range, range]), try index.selection([range]))
    XCTAssertEqual(try index.selection([NSRange(location: 0, length: (text as NSString).length)]), value)
  }
  func testIncrementalEditsMatchFreshSourceAcrossBlocks() throws {
    var source = String(repeating: "hello 你好\r\n\n第二段 42!\n", count: 1000)
    let index = try TextStatisticsIndex(source)
    let insertions = ["a", "你", "\r\n", "\n\n", "", "👨‍👩‍👧‍👦", "don't 42"]
    var seed: UInt64 = 1234
    func random(_ maximum: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1; return Int(seed >> 32) % maximum }
    for step in 0..<80 {
      let positions = Array(source.indices) + [source.endIndex]
      let start = random(positions.count)
      let end = min(positions.count - 1, start + random(20))
      let range = NSRange(positions[start]..<positions[end], in: source)
      let insertion = insertions[step % insertions.count]
      source = (source as NSString).replacingCharacters(in: range, with: insertion)
      try index.apply(range: range, replacement: insertion)
      XCTAssertEqual(index.snapshot, try TextStatisticsIndex(source).snapshot, "Edit \(step)")
    }
  }
  func testSmallEditDoesNotRescanLargeManuscript() throws {
    let source = String(repeating: "one line of writing\n", count: 300_000)
    let index = try TextStatisticsIndex(source)
    let previous = index.scannedUTF16Units
    try index.apply(range: NSRange(location: 2_000_000, length: 0), replacement: "你好")
    XCTAssertLessThan(index.scannedUTF16Units - previous, 64 * 1024)
    XCTAssertEqual(index.snapshot.utf16Units, (source as NSString).length + 2)
  }
  func testWorkerRejectsOutdatedRevisions() async throws {
    let worker = TextStatisticsWorker()
    _ = try await worker.reset("hello", revision: 10)
    let stale = try await worker.edit(NSRange(location: 0, length: 0), replacement: "x", before: 9, revision: 11)
    XCTAssertNil(stale)
    let result = try await worker.edit(NSRange(location: 0, length: 0), replacement: "你", before: 10, revision: 11)
    XCTAssertEqual(result?.nonWhitespace, 6)
    let oldSelection = try await worker.selection([NSRange(location: 0, length: 1)], revision: 10)
    XCTAssertNil(oldSelection)
  }
}
