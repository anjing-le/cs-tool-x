import Foundation
import SwiftTerm
import ToolCore

@MainActor enum ShellAuthentication {
  static func environment(for server: Server) throws -> [String]? {
    guard !server.local, !(server.password ?? "").isEmpty else { return nil }
    guard let helper = Bundle.main.url(forResource: "ssh-askpass", withExtension: nil),
      FileManager.default.isExecutableFile(atPath: helper.path),
      let executable = Bundle.main.executableURL
    else { throw ToolError.message("SSH 密码助手缺失，请使用完整应用包。") }
    var environment = ProcessInfo.processInfo.environment
    for item in Terminal.getEnvironmentVariables(termName: "xterm-256color") {
      let parts = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      if parts.count == 2 { environment[String(parts[0])] = String(parts[1]) }
    }
    environment["SSH_ASKPASS"] = helper.path
    environment["SSH_ASKPASS_REQUIRE"] = "force"
    environment["CSTOOLX_ASKPASS_EXECUTABLE"] = executable.path
    environment["CSTOOLX_SSH_CONFIG"] = ShellStore.configurationURL.path
    environment["CSTOOLX_SSH_SERVER_ID"] = String(server.id)
    environment["CSTOOLX_SSH_HOST"] = server.host
    environment["CSTOOLX_SSH_USER"] = server.user
    environment["CSTOOLX_SSH_PORT"] = String(server.port)
    return environment.map { "\($0.key)=\($0.value)" }
  }
}
