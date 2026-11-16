import Foundation
import SwiftTerm
import ToolCore

@MainActor enum ShellAuthentication {
  static func environment(for server: Server) throws -> [String]? {
    let environment = TerminalAppearance.environment(base: ProcessInfo.processInfo.environment, local: server.local)
    guard !server.local, !(server.password ?? "").isEmpty else {
      return environment.map { "\($0.key)=\($0.value)" }
    }
    guard let helper = Bundle.main.url(forResource: "ssh-askpass", withExtension: nil),
      FileManager.default.isExecutableFile(atPath: helper.path),
      let executable = Bundle.main.executableURL
    else { throw ToolError.message("SSH 密码助手缺失，请使用完整应用包。") }
    return try SSHLaunch.environment(
      server: server, configuration: ShellStore.configurationURL,
      helper: helper, executable: executable, base: environment
    ).map { "\($0.key)=\($0.value)" }
  }
}
