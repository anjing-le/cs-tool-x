import Foundation

public struct ProfileStore: Sendable {
  private let file: ConfigurationFile
  public init(directory: URL? = nil) {
    file = ConfigurationFile(
      url: (directory ?? ConfigurationPaths.directory).appendingPathComponent("connections.json"))
  }
  public func snapshot() throws -> ConfigurationSnapshot<[ConnectionProfile]> {
    let result = try file.snapshot(default: [ConnectionProfile]())
    try Self.validate(result.value)
    return result
  }
  public func load() throws -> [ConnectionProfile] { try snapshot().value }
  @discardableResult public func save(_ value: [ConnectionProfile], expectedRevision: String? = nil)
    throws -> String
  {
    try Self.validate(value)
    return try file.update(default: [ConnectionProfile](), expectedRevision: expectedRevision) {
      $0 = value
    }.revision
  }
  @discardableResult public func update(
    expectedRevision: String? = nil, _ body: (inout [ConnectionProfile]) throws -> Void
  ) throws -> ConfigurationSnapshot<[ConnectionProfile]> {
    try file.update(default: [ConnectionProfile](), expectedRevision: expectedRevision) { value in
      try body(&value)
      try Self.validate(value)
    }
  }
  private static func validate(_ value: [ConnectionProfile]) throws {
    guard value.count <= 100, Set(value.map(\.id)).count == value.count else {
      throw ConfigurationError.invalid
    }
    for profile in value { try profile.validate() }
  }
}
