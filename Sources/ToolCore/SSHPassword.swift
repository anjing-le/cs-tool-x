import Foundation

/// Local plaintext configuration, explicitly chosen by the user. No Keychain or argv secret.
public enum SSHPassword {
  public static func response(
    prompt: String, configuration: URL, serverID: Int, expectedHost: String, expectedUser: String,
    expectedPort: Int
  ) throws -> String {
    // Never answer host-key confirmation, private-key passphrases, OTP, or arbitrary questions.
    guard prompt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("password:")
    else { throw ToolError.message("密码助手不处理此提示；请先确认主机指纹或使用交互认证。") }
    let attributes = try FileManager.default.attributesOfItem(atPath: configuration.path)
    guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 1024 * 1024,
      (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
      (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
      attributes[.type] as? FileAttributeType == .typeRegular
    else { throw ToolError.message("本机 SSH 配置必须为当前用户的 0600 普通文件，且不超过 1 MiB。") }
    let value = try JSONSerialization.jsonObject(with: Data(contentsOf: configuration))
    guard let object = value as? [String: Any], let servers = object["servers"] as? [[String: Any]],
      let server = servers.first(where: { ($0["id"] as? Int) == serverID }),
      server["host"] as? String == expectedHost, server["user"] as? String == expectedUser,
      server["port"] as? Int == expectedPort,
      let password = server["password"] as? String, !password.isEmpty,
      password.utf8.count <= 4096,
      !password.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\0" })
    else { throw ToolError.message("本机服务器密码未配置或格式无效。") }
    return password
  }
}
