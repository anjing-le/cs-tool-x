import Foundation
import XCTest

@testable import ToolCore

final class ToolboxTests: XCTestCase {
  func run(
    _ tool: String, _ mode: String = "", _ text: String = "", _ other: String = "",
    replacement: String = ""
  ) throws -> ToolboxResult {
    try Toolbox.run(
      .init(tool: tool, mode: mode, text: text, other: other, replacement: replacement))
  }
  func testTextTransformsAndSubtitleContent() throws {
    XCTAssertEqual(try run("case", "snake", "myHTTP value").output, "my_http_value")
    XCTAssertEqual(try run("lines", "count", "a\r\nb\r\na").output, "2\ta\n1\tb")
    XCTAssertEqual(
      try run(
        "srt", "",
        "1\r\n00:00:01,000 --> 00:00:02,000\r\n123\r\n\r\n2\r\n00:00:03,000 --> 00:00:04,000\r\n你好"
      ).output, "123\n你好")
    XCTAssertEqual(try run("diff", "", "a\nb", "a\nc").output, "  a\n− b\n+ c")
  }
  func testCodecsUnicodeAndInvalidInput() throws {
    for prefix in ["base64", "url", "hex"] {
      let encoded = try run("codec", prefix + "-encode", "你好\n+🧰").output
      XCTAssertEqual(try run("codec", prefix + "-decode", encoded).output, "你好\n+🧰")
    }
    let escaped = try run("codec", "json-escape", "\"hello\n").output
    XCTAssertEqual(try run("codec", "json-unescape", escaped).output, "\"hello\n")
    XCTAssertThrowsError(try run("codec", "base64-decode", "%%%"))
    XCTAssertThrowsError(try run("codec", "hex-decode", "ff"))
    XCTAssertThrowsError(try run("codec", "url-decode", "%FF"))
  }
  func testDatesJSONAndRegex() throws {
    XCTAssertEqual(try run("timestamp", "seconds-to-date", "0").output, "1970-01-01T00:00:00.000Z")
    XCTAssertEqual(
      try run("timestamp", "date-to-milliseconds", "1970-01-01T08:00:01+08:00").output, "1000")
    XCTAssertEqual(try run("json", "compact", "{ \"b\": [1, 2] }").output, "{\"b\":[1,2]}")
    XCTAssertThrowsError(
      try run(
        "json", "", String(repeating: "[", count: 129) + "0" + String(repeating: "]", count: 129)))
    XCTAssertTrue(try run("regex", "match", "🧰 ab12", "([0-9]+)").output.contains("1: 12"))
    XCTAssertEqual(
      try run("regex", "replace", "a12b34", "(\\d+)", replacement: "[$1]").output, "a[12]b[34]")
    XCTAssertThrowsError(try run("regex", "match", "abc", "["))
  }
  func testHashFileAndVerification() throws {
    let expected = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    XCTAssertEqual(try run("hash", "sha256", "abc", expected).detail, "校验一致")
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    try Data(repeating: 65, count: 1024 * 1024).write(to: url)
    let result = try Toolbox.run(.init(tool: "hash", mode: "sha256", file: url.path))
    XCTAssertEqual(result.output, SHA256DigestForFixture)
    XCTAssertThrowsError(try Toolbox.run(.init(tool: "hash", file: "/dev/zero")))
  }
  private let SHA256DigestForFixture =
    "4e29ad18ab9f42d7c233500771a39d7c852b200baf328fd00fbbe3fecea1eb56"
  func testRandomClassesAndBudgets() throws {
    let result = try Toolbox.run(.init(tool: "random", mode: "password", length: 24, count: 100))
      .output.components(separatedBy: "\n")
    XCTAssertEqual(Set(result).count, 100)
    for password in result {
      XCTAssertEqual(password.count, 24)
      XCTAssertTrue(password.contains(where: { $0.isUppercase }))
      XCTAssertTrue(password.contains(where: { $0.isLowercase }))
      XCTAssertTrue(password.contains(where: { $0.isNumber }))
      XCTAssertTrue(password.contains(where: { !$0.isLetter && !$0.isNumber }))
    }
    XCTAssertThrowsError(try run("case", "", String(repeating: "a", count: Toolbox.inputLimit + 1)))
    XCTAssertThrowsError(try run("diff", "", String(repeating: "x\n", count: 1001)))
    XCTAssertThrowsError(try Toolbox.run(.init(tool: "random", length: 0)))
    XCTAssertThrowsError(try run("hash", "sha256", "a", "zz"))
  }
}
