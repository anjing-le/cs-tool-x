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
    return try SSHLaunch.environment(
      server: server, configuration: ShellStore.configurationURL,
      helper: helper, executable: executable, base: environment
    ).map { "\($0.key)=\($0.value)" }
  }
}
