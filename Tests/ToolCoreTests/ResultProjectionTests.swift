import Foundation
import XCTest

@testable import ToolCore

final class ResultProjectionTests: XCTestCase {
  func testFilteredRowsKeepSourceIdentityForDetailAndNullPrecision() throws {
    let data = Data(
      """
      {"columns":["id","name"],"rows":[["9007199254740993","alpha"],[null,"Beta"],["3","alphabet"]],"elapsedMs":1,"truncated":false,"note":""}
      """.utf8)
    let output = try JSONDecoder().decode(QueryOutput.self, from: data)
    let projection = ResultProjection(output)
    XCTAssertEqual(projection.indices(matching: "beta"), [1])
    XCTAssertEqual(projection.indices(matching: " ALPHA "), [0, 2])
    XCTAssertEqual(projection.rows[0][0], "9007199254740993")
    XCTAssertEqual(output.rows[projection.indices(matching: "beta")[0]][0], .null)
    XCTAssertEqual(projection.indices(matching: ""), [0, 1, 2])
  }
  func testSearchIncludesLoadedTextBeyondDisplayClipping() {
    let output = QueryOutput(
      columns: ["body"], rows: [[.string(String(repeating: "x", count: 3000) + "needle")]],
      elapsedMs: 0, truncated: false, note: "", nextCursor: nil)
    let projection = ResultProjection(output)
    XCTAssertTrue(projection.rows[0][0].hasSuffix("…"))
    XCTAssertEqual(projection.indices(matching: "needle"), [0])
  }
  func testObjectQueryQuotesIdentifiersWithoutRewritingDatabase() {
    XCTAssertEqual(
      DataObjectQuery.select(kind: .mysql, schema: "db`name", table: "orders"),
      "SELECT * FROM `db``name`.`orders` LIMIT 100;")
    XCTAssertEqual(
      DataObjectQuery.select(kind: .pg, schema: "a\"b", table: "items"),
      "SELECT * FROM \"a\"\"b\".\"items\" LIMIT 100;")
    XCTAssertNil(DataObjectQuery.select(kind: .es, schema: "", table: ""))
  }
}
