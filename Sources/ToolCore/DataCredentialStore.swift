import Darwin
import Foundation

/// Local plaintext credentials, outside the app/repository. Metadata outputs never encode this store.
public struct DataCredentialStore: Sendable {
  private struct Entry: Codable {
    let identity: ConnectionIdentity
    let policy: String
    let credentials: ConnectionCredentials
  }
  private let file: ConfigurationFile
  public init(directory: URL? = nil) {
    file = ConfigurationFile(
      url: (directory ?? ConfigurationPaths.directory).appendingPathComponent(
        "data-credentials.json"), keepsBackup: false)
  }
  private func checkFile() throws {
    guard FileManager.default.fileExists(atPath: file.url.path) else { return }
    let attributes = try FileManager.default.attributesOfItem(atPath: file.url.path)
    guard attributes[.type] as? FileAttributeType == .typeRegular,
      (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
      (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600
    else { throw ConfigurationError.invalid }
  }
  public func load(for profile: ConnectionProfile) throws -> ConnectionCredentials? {
    try snapshot(for: profile).value
  }
  public func snapshot(for profile: ConnectionProfile) throws -> ConfigurationSnapshot<
    ConnectionCredentials?
  > {
    try profile.validate()
    try checkFile()
    let state: ConfigurationSnapshot<[String: Entry]> = try file.snapshot(default: [:])
    guard let entry = state.value[profile.credentialScope],
      entry.identity == ConnectionIdentity(profile), entry.policy == profile.transportPolicy
    else { return ConfigurationSnapshot(value: nil, revision: state.revision) }
    try validate(entry.credentials)
    return ConfigurationSnapshot(value: entry.credentials, revision: state.revision)
  }
  private func validate(_ credentials: ConnectionCredentials) throws {
    guard credentials.password.utf8.count <= 4096, credentials.apiKey.utf8.count <= 4096 else {
      throw ConfigurationError.invalid
    }
  }
  public func save(
    _ credentials: ConnectionCredentials, for profile: ConnectionProfile,
    expectedRevision: String? = nil
  ) throws {
    try profile.validate()
    try validate(credentials)
    try checkFile()
    try file.update(default: [String: Entry](), expectedRevision: expectedRevision) { entries in
      entries[profile.credentialScope] = Entry(
        identity: ConnectionIdentity(profile), policy: profile.transportPolicy,
        credentials: credentials)
      guard entries.count <= 100 else { throw ConfigurationError.invalid }
    }
  }
  public func remove(for profile: ConnectionProfile, expectedRevision: String? = nil) throws {
    try checkFile()
    try file.update(default: [String: Entry](), expectedRevision: expectedRevision) { entries in
      entries.removeValue(forKey: profile.credentialScope)
    }
  }
}

/// Latest activation wins; repeated opens reserve only one connection slot.
public struct DataOpenGate: Sendable {
  public struct Request: Sendable {
    public let profile: ConnectionProfile
    public let nodeID: String
    public let query: Bool
    public let presents: Bool
    public let generation: Int
  }
  public init() {}
  private var requests: [UUID: Request] = [:]
  private var generation = 0
  public var navigationRevision: Int { generation }
  public var pendingCount: Int { requests.count }
  public func isPending(_ id: UUID) -> Bool { requests[id] != nil }
  public func contains(groupID: String) -> Bool {
    requests.values.contains { ConnectionIdentity($0.profile).id == groupID }
  }
  public mutating func navigate() { generation += 1 }
  public mutating func clear() {
    generation += 1
    requests.removeAll()
  }
  /// Returns true only for the first request, which must start the async connection.
  public mutating func begin(
    profile: ConnectionProfile, nodeID: String, query: Bool, presents: Bool, active: Int
  ) throws -> Bool {
    let previous = requests[profile.id]
    if let previous,
      previous.profile.credentialScope != profile.credentialScope
        || previous.profile.database != profile.database
    {
      throw ConfigurationError.conflict
    }
    guard previous != nil || active + requests.count < 4 else {
      throw ToolError.message("最多同时保留 4 个数据会话，请先断开一个。")
    }
    if let previous, previous.presents && !presents { return false }
    if presents { navigate() }
    requests[profile.id] = Request(
      profile: profile, nodeID: nodeID, query: query, presents: presents, generation: generation)
    return previous == nil
  }
  public mutating func finish(_ id: UUID) -> Request? { requests.removeValue(forKey: id) }
  public func isCurrent(_ request: Request) -> Bool { request.generation == generation }
}
