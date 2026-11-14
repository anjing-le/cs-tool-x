import Foundation
import XCTest

@testable import ToolCore

final class ConfigurationTests: XCTestCase {
  func testAtomicRevisionConflictBackupAndPermissions() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    let a = ProfileStore(directory: dir)
    let b = ProfileStore(directory: dir)
    let old = try a.snapshot()
    XCTAssertEqual(old.revision, ConfigurationFile.missingRevision)
    var p = ConnectionProfile()
    p.database = "fixture"
    let next = try a.save([p], expectedRevision: old.revision)
    XCTAssertThrowsError(try b.save([], expectedRevision: old.revision))
    XCTAssertEqual(try a.load(), [p])
    let empty = try b.save([], expectedRevision: next)
    XCTAssertNotEqual(next, empty)
    XCTAssertEqual(
      try JSONDecoder().decode(
        [ConnectionProfile].self,
        from: Data(contentsOf: dir.appendingPathComponent("connections.json.backup"))), [p])
    for name in ["connections.json", "connections.json.backup", "connections.json.lock"] {
      let attrs = try FileManager.default.attributesOfItem(
        atPath: dir.appendingPathComponent(name).path)
      XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }
  }
  func testConcurrentWritersMergeWithoutLosingRecords() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    try await withThrowingTaskGroup(of: Void.self) { group in
      for i in 0..<12 {
        group.addTask {
          let store = ProfileStore(directory: dir)
          try store.update { values in
            var p = ConnectionProfile()
            p.database = "fixture"
            p.name = "concurrent-\(i)"
            values.append(p)
          }
        }
      }
      try await group.waitForAll()
    }
    XCTAssertEqual(try ProfileStore(directory: dir).load().count, 12)
  }
  func testLegacyShellAndWrongRevision() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let raw = Data(
      "{\"servers\":[{\"id\":0,\"name\":\"fixture\",\"host\":\"fixture.invalid\",\"group\":\"test\",\"port\":22,\"user\":\"u\"}],\"groups\":[\"test\"]}"
        .utf8)
    try raw.write(to: dir.appendingPathComponent("shell.json"))
    let store = ShellStore(directory: dir)
    let snapshot = try await store.snapshot()
    XCTAssertNil(snapshot.value.servers[0].password)
    var newer = snapshot.value
    newer.servers[0].notes = "new"
    _ = try await store.save(newer, expectedRevision: snapshot.revision)
    do {
      _ = try await store.save(snapshot.value, expectedRevision: snapshot.revision)
      XCTFail("Expected conflict")
    } catch let e as ConfigurationError { if case .conflict = e {} else { XCTFail("Wrong error") } }
    let latest = try await store.snapshot()
    XCTAssertEqual(latest.value.servers[0].notes, "new")
  }
  func testOversizedAndInvalidConfigurationAreRejected() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data(repeating: 32, count: ConfigurationFile.maxBytes + 1).write(
      to: dir.appendingPathComponent("connections.json"))
    XCTAssertThrowsError(try ProfileStore(directory: dir).load())
    var invalid = ShellConfiguration(
      servers: [ShellServer(id: -1, name: "local", host: "localhost", group: "x")], groups: ["x"])
    XCTAssertThrowsError(try invalid.validate())
    invalid = ShellConfiguration(servers: [], groups: ["x", "x"])
    XCTAssertThrowsError(try invalid.validate())
  }
}
