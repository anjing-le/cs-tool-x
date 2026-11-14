import Darwin
import Foundation
import XCTest

@testable import ToolCore

final class BoundedProcessTests: XCTestCase {
  func testConcurrentOutputDrainAndCombinedBudget() async throws {
    let result = try await BoundedProcess.run(
      executable: URL(fileURLWithPath: "/bin/sh"),
      arguments: [
        "-c",
        "i=0; while [ $i -lt 3000 ]; do printf 'out-1234567890\\n'; printf 'err-1234567890\\n' >&2; i=$((i+1)); done",
      ], timeout: 5, maxOutputBytes: 4096)
    XCTAssertTrue(result.truncated)
    XCTAssertLessThanOrEqual(result.stdout.utf8.count + result.stderr.utf8.count, 4096)
    XCTAssertFalse(result.timedOut)
  }
  func testDeadlineTerminatesAProcess() async throws {
    let result = try await BoundedProcess.run(
      executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"], timeout: 0.1)
    XCTAssertTrue(result.timedOut)
    XCTAssertNotEqual(result.exitCode, 0)
    XCTAssertLessThan(result.elapsedMs, 3000)
  }
  func testInputAndExitStatusArePreserved() async throws {
    signal(SIGPIPE, SIG_IGN)
    let result = try await BoundedProcess.run(
      executable: URL(fileURLWithPath: "/bin/sh"),
      arguments: ["-c", "cat; printf 'failure' >&2; exit 9"], input: Data("hello\n".utf8),
      timeout: 3)
    XCTAssertEqual(result.stdout, "hello\n")
    XCTAssertEqual(result.stderr, "failure")
    XCTAssertEqual(result.exitCode, 9)
    XCTAssertFalse(result.truncated)
    XCTAssertFalse(result.timedOut)
  }
}
