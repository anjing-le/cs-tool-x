import XCTest

@testable import ToolCore

final class ToolCoreTests: XCTestCase {
  func testSSHArgumentsAreNotShellCommands() throws {
    XCTAssertEqual(
      try SSHCommand.arguments(host: "jump-box", user: "dev", port: "22", sftp: false),
      [
        "-o", "UseKeychain=no", "-o", "AddKeysToAgent=no", "-o", "StrictHostKeyChecking=ask", "-p",
        "22", "-l", "dev", "--", "jump-box",
      ])
    for host in ["-oProxyCommand=evil", "box\nother", "box other", ""] {
      XCTAssertThrowsError(try SSHCommand.arguments(host: host, user: "", port: "22", sftp: false))
    }
    XCTAssertThrowsError(try SSHCommand.arguments(host: "box", user: "", port: "0", sftp: true))
    XCTAssertEqual(
      try SSHCommand.arguments(host: "box", user: "dev", port: "2200", sftp: true).suffix(2),
      ["--", "dev@box"])
  }
  func testProfilePersistenceContainsNoSecrets() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ProfileStore(directory: directory)
    var profile = ConnectionProfile()
    profile.name = "sample"
    profile.database = "sample"
    try profile.validate()
    try store.save([profile])
    XCTAssertEqual(try store.load(), [profile])
    let raw = try String(
      contentsOf: directory.appendingPathComponent("connections.json"), encoding: .utf8)
    XCTAssertFalse(raw.contains("password"))
    XCTAssertFalse(raw.contains("apiKey"))
    let attrs = try FileManager.default.attributesOfItem(
      atPath: directory.appendingPathComponent("connections.json").path)
    XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
  }
  func testJSONPreservesIntegersAndNull() throws {
    let value = try JSONDecoder().decode(
      JSONValue.self, from: Data("{\"id\":9007199254740993,\"n\":null}".utf8))
    XCTAssertEqual(value["id"]?.text, "9007199254740993")
    XCTAssertEqual(value["n"], .null)
    let roundtrip = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    XCTAssertEqual(roundtrip, value)
  }
  func testProfileEndpointValidation() {
    var profile = ConnectionProfile(kind: .es)
    profile.endpoint = "https://user:secret@example.com"
    XCTAssertThrowsError(try profile.validate())
    profile.endpoint = "https://example.com:9200"
    XCTAssertNoThrow(try profile.validate())
    profile = ConnectionProfile(kind: .redis)
    profile.database = "-1"
    XCTAssertThrowsError(try profile.validate())
  }
  func testMissingEngineFailsWithoutStartingOtherServices() async {
    let client = EngineClient(executable: URL(fileURLWithPath: "/missing/cs-tool-engine"))
    do {
      _ = try await client.call("hello")
      XCTFail("Expected missing helper error")
    } catch { XCTAssertTrue(error.localizedDescription.contains("数据引擎缺失")) }
  }
  func testRealEngineProtocol() async throws {
    guard let path = ProcessInfo.processInfo.environment["CSTOOLX_ENGINE"] else {
      throw XCTSkip("Set CSTOOLX_ENGINE to validate real worker framing")
    }
    let client = EngineClient(executable: URL(fileURLWithPath: path))
    let reply = try await client.call("hello")
    XCTAssertEqual(reply["protocol"]?.text, "1")
    async let first = client.call("hello")
    async let second = client.call("hello")
    let replies = try await [first, second]
    XCTAssertEqual(replies.count, 2)
    do {
      _ = try await client.call("unknown")
      XCTFail("Unknown method should fail")
    } catch { XCTAssertTrue(error.localizedDescription.contains("不支持")) }
    await client.stop()
    let again = try await client.call("hello")
    XCTAssertEqual(again["protocol"]?.text, "1")
    await client.stop()
  }
  func testConcurrentLargeWorkerFrames() async throws {
    guard ProcessInfo.processInfo.environment["CSTOOLX_FIXTURES"] == "1",
      let path = ProcessInfo.processInfo.environment["CSTOOLX_ENGINE"]
    else { throw XCTSkip("Requires isolated fixtures and worker path") }
    let client = EngineClient(executable: URL(fileURLWithPath: path))
    var profile = ConnectionProfile(kind: .mysql)
    profile.host = "127.0.0.1"
    profile.port = 13306
    profile.database = "datax_fixture"
    let connection = try await client.connect(profile: profile, password: "", apiKey: "")
    async let a = client.run(id: connection.0, action: "query", text: "SELECT REPEAT('x',65500)")
    async let b = client.run(id: connection.0, action: "query", text: "SELECT REPEAT('y',65500)")
    async let c = client.run(id: connection.0, action: "query", text: "SELECT REPEAT('z',65500)")
    let outputs = try await [a, b, c]
    XCTAssertEqual(outputs.map { $0.rows[0][0].text.count }, [65500, 65500, 65500])
    XCTAssertEqual(outputs[1].rows[0][0].text.first, "y")
    try await client.disconnect(id: connection.0)
    await client.stop()
  }

}
