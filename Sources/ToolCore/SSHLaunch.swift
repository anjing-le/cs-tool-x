import Foundation

public enum SSHLaunch {
  public static func environment(
    server: ShellServer, configuration: URL, helper: URL, executable: URL,
    base: [String: String] = ProcessInfo.processInfo.environment
  ) throws -> [String: String] {
    guard !server.local, !(server.password ?? "").isEmpty else { return base }
    guard FileManager.default.isExecutableFile(atPath: helper.path) else {
      throw ToolError.message("SSH 密码助手缺失，请使用完整应用包。")
    }
    var environment = base
    environment["SSH_ASKPASS"] = helper.path
    environment["SSH_ASKPASS_REQUIRE"] = "force"
    environment["CSTOOLX_ASKPASS_EXECUTABLE"] = executable.path
    environment["CSTOOLX_SSH_CONFIG"] = configuration.path
    environment["CSTOOLX_SSH_SERVER_ID"] = String(server.id)
    environment["CSTOOLX_SSH_HOST"] = server.host
    environment["CSTOOLX_SSH_USER"] = server.user
    environment["CSTOOLX_SSH_PORT"] = String(server.port)
    return environment
  }
  public static func noninteractiveArguments(server: ShellServer, sftp: Bool, timeout: Int) throws
    -> [String]
  {
    try server.validate()
    let hasPassword = !(server.password ?? "").isEmpty
    var args = try SSHCommand.arguments(
      host: server.host, user: server.user, port: String(server.port), sftp: sftp,
      passwordAuthentication: hasPassword)
    args = args.map { $0 == "StrictHostKeyChecking=ask" ? "StrictHostKeyChecking=yes" : $0 }
    args.insert(
      contentsOf: ["-o", "ConnectTimeout=\(timeout)", "-o", "ConnectionAttempts=1"], at: 0)
    if !hasPassword { args.insert(contentsOf: ["-o", "BatchMode=yes"], at: 0) }
    return args
  }
}
extension SSHPassword {
  /// Internal helper mode exits before any GUI or CLI command parser is initialized.
  public static func helperExitCode(
    arguments: [String] = CommandLine.arguments,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> Int32? {
    guard arguments.dropFirst().first == "--ssh-askpass" else { return nil }
    do {
      guard environment["SSH_ASKPASS_PROMPT"] != "confirm",
        let path = environment["CSTOOLX_SSH_CONFIG"],
        let id = Int(environment["CSTOOLX_SSH_SERVER_ID"] ?? "")
      else { return 1 }
      let password = try response(
        prompt: arguments.dropFirst(2).joined(separator: " "),
        configuration: URL(fileURLWithPath: path), serverID: id,
        expectedHost: environment["CSTOOLX_SSH_HOST"] ?? "",
        expectedUser: environment["CSTOOLX_SSH_USER"] ?? "",
        expectedPort: Int(environment["CSTOOLX_SSH_PORT"] ?? "") ?? 0)
      FileHandle.standardOutput.write(Data((password + "\n").utf8))
      return 0
    } catch {
      FileHandle.standardError.write(Data("SSH 密码助手未返回凭据；请检查本机配置或主机指纹。\n".utf8))
      return 1
    }
  }
}
