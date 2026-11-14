import Foundation

public struct ShellServer: Identifiable, Codable, Equatable, Sendable {
  public let id: Int
  public var name: String
  public var host: String
  public var group: String
  public var port: Int
  public var user: String
  public var password: String?
  public var notes: String?
  public init(
    id: Int, name: String, host: String, group: String, port: Int = 22, user: String = "",
    password: String? = nil, notes: String? = nil
  ) {
    self.id = id
    self.name = name
    self.host = host
    self.group = group
    self.port = port
    self.user = user
    self.password = password
    self.notes = notes
  }
  public var local: Bool { id == -1 }
  public static let localServer = ShellServer(id: -1, name: "本地终端", host: "localhost", group: "本机")
  public func validate() throws {
    guard id >= 0, id <= Int(Int32.max), !name.isEmpty, name.count <= 100, !group.isEmpty,
      group.count <= 100,
      !host.contains("://"), !host.contains("/"), !host.contains("@"),
      (password ?? "").utf8.count <= 4096, (notes ?? "").utf8.count <= 4096,
      !(password ?? "").contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\0" })
    else { throw ConfigurationError.invalid }
    _ = try SSHCommand.arguments(host: host, user: user, port: String(port), sftp: false)
  }
}
public struct ShellConfiguration: Codable, Sendable {
  public var servers: [ShellServer]
  public var groups: [String]
  public init(servers: [ShellServer] = [], groups: [String] = ["日常开发"]) {
    self.servers = servers
    self.groups = groups
  }
  public func validate() throws {
    guard servers.count <= 100, groups.count <= 50,
      Set(servers.map(\.id)).count == servers.count, Set(groups).count == groups.count,
      groups.allSatisfy({ !$0.isEmpty && $0.count <= 100 })
    else { throw ConfigurationError.invalid }
    for server in servers {
      try server.validate()
      guard groups.contains(server.group) else { throw ConfigurationError.invalid }
    }
  }
}
public actor ShellStore {
  public static var configurationURL: URL {
    ConfigurationPaths.directory.appendingPathComponent("shell.json")
  }
  private let file: ConfigurationFile
  public init(directory: URL? = nil) {
    file = ConfigurationFile(
      url: (directory ?? ConfigurationPaths.directory).appendingPathComponent("shell.json"))
  }
  public func snapshot() throws -> ConfigurationSnapshot<ShellConfiguration> {
    let result = try file.snapshot(default: ShellConfiguration())
    try result.value.validate()
    return result
  }
  @discardableResult public func save(_ value: ShellConfiguration, expectedRevision: String) throws
    -> String
  {
    try value.validate()
    return try file.update(default: ShellConfiguration(), expectedRevision: expectedRevision) {
      $0 = value
    }.revision
  }
  @discardableResult public func update(
    expectedRevision: String? = nil, _ body: (inout ShellConfiguration) throws -> Void
  ) throws -> ConfigurationSnapshot<ShellConfiguration> {
    try file.update(default: ShellConfiguration(), expectedRevision: expectedRevision) { value in
      try body(&value)
      try value.validate()
    }
  }
}
