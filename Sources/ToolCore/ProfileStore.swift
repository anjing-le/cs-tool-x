import Foundation

public struct ProfileStore {
  private let url: URL
  public init(directory: URL? = nil) {
    let base =
      directory
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent(
        Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true ? "cs-tool-x-dev" : "cs-tool-x",
        isDirectory: true)
    url = base.appendingPathComponent("connections.json")
  }
  public func load() throws -> [ConnectionProfile] {
    guard FileManager.default.fileExists(atPath: url.path) else { return [] }
    let data = try Data(contentsOf: url)
    guard data.count <= 1024 * 1024 else { throw ToolError.message("连接配置超过上限。") }
    let profiles = try JSONDecoder().decode([ConnectionProfile].self, from: data)
    guard profiles.count <= 100 else { throw ToolError.message("保存的连接不能超过 100 个。") }
    return profiles
  }
  public func save(_ profiles: [ConnectionProfile]) throws {
    guard profiles.count <= 100 else { throw ToolError.message("保存的连接不能超过 100 个。") }
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    try JSONEncoder().encode(profiles).write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }
}
