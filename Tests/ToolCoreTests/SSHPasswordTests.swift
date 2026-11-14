import Foundation
import XCTest

@testable import ToolCore

final class SSHPasswordTests: XCTestCase {
  func testLocalPlaintextCredentialAndPromptBoundaries() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let path = directory.appendingPathComponent("shell.json")
    let record: [String: Any] = [
      "servers": [
        [
          "id": 7, "host": "fixture.invalid", "user": "test", "port": 22,
          "password": "fixture pass !",
        ]
      ]
    ]
    try JSONSerialization.data(withJSONObject: record).write(to: path)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    func read(_ prompt: String, host: String = "fixture.invalid", id: Int = 7) throws -> String {
      try SSHPassword.response(
        prompt: prompt, configuration: path, serverID: id,
        expectedHost: host, expectedUser: "test", expectedPort: 22)
    }
    XCTAssertEqual(try read("test@fixture.invalid's password: "), "fixture pass !")
    XCTAssertThrowsError(try read("Are you sure you want to continue connecting (yes/no)?"))
    XCTAssertThrowsError(try read("Enter passphrase for key '/tmp/key':"))
    XCTAssertThrowsError(try read("Verification code:"))
    XCTAssertThrowsError(try read("Password:", host: "other.invalid"))
    XCTAssertThrowsError(try read("Password:", id: 8))
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path.path)
    XCTAssertThrowsError(try read("Password:"))
  }
  func testPasswordAuthenticationKeepsHostVerificationAndNoSecretArguments() throws {
    for sftp in [false, true] {
      let args = try SSHCommand.arguments(
        host: "fixture.invalid", user: "test", port: "22",
        sftp: sftp, passwordAuthentication: true)
      XCTAssertTrue(args.contains("StrictHostKeyChecking=ask"))
      XCTAssertTrue(args.contains("UseKeychain=no"))
      XCTAssertTrue(args.contains("NumberOfPasswordPrompts=1"))
      XCTAssertTrue(args.contains("PreferredAuthentications=password"))
      XCTAssertFalse(args.contains("fixture pass !"))
    }
  }
}
