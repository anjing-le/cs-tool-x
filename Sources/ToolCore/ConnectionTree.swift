import CryptoKit
import Foundation

/// Presentation identity, not an authentication or pool identity. Child profiles
/// retain their UUID, database and transport policy; no source record is merged away.
public struct ConnectionIdentity: Hashable, Sendable, Codable {
  public let kind: DatabaseKind
  public let host: String
  public let port: Int
  public let username: String
  public let environment: String
  public let basePath: String
  public init(_ profile: ConnectionProfile) {
    kind = profile.kind
    let url = profile.kind == .es ? URLComponents(string: profile.endpoint) : nil
    host = (url?.host ?? profile.host).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    port = url?.port ?? (url?.scheme == "https" ? 443 : url?.scheme == "http" ? 80 : profile.port)
    username = profile.username
    environment = profile.environment
    basePath = url?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
  }
  public static func token(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }
  public var id: String {
    let data = try! JSONEncoder().encode([
      kind.rawValue, host, String(port), username, environment, basePath,
    ])
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
  public var address: String { "\(host):\(port)\(basePath.isEmpty ? "" : "/" + basePath)" }
}
public struct ConnectionScope: Sendable {
  public let database: String
  public let profiles: [ConnectionProfile]
  public var representative: ConnectionProfile { profiles[0] }
  public var hasPolicyVariants: Bool { Set(profiles.map(\.transportPolicy)).count > 1 }
}
public struct ConnectionGroup: Sendable, Encodable {
  public let identity: ConnectionIdentity
  public let profiles: [ConnectionProfile]
  public var id: String { identity.id }
  public var hasPolicyVariants: Bool { Set(profiles.map(\.transportPolicy)).count > 1 }
  public var scopes: [ConnectionScope] {
    var order: [String] = []
    var values: [String: [ConnectionProfile]] = [:]
    for profile in profiles {
      if values[profile.database] == nil { order.append(profile.database) }
      values[profile.database, default: []].append(profile)
    }
    return order.map { ConnectionScope(database: $0, profiles: values[$0]!) }
  }
  public static func build(_ profiles: [ConnectionProfile]) -> [ConnectionGroup] {
    var order: [ConnectionIdentity] = []
    var values: [ConnectionIdentity: [ConnectionProfile]] = [:]
    for profile in profiles {
      let key = ConnectionIdentity(profile)
      if values[key] == nil { order.append(key) }
      values[key, default: []].append(profile)
    }
    return order.map { ConnectionGroup(identity: $0, profiles: values[$0]!) }
  }
}
extension ConnectionProfile {
  /// Prevent automatic credential reuse between different TLS/protocol policies.
  public var transportPolicy: String {
    kind == .es ? (URLComponents(string: endpoint)?.scheme ?? "") : (tls ? "tls-verify" : "plain")
  }
  public var credentialScope: String { ConnectionIdentity(self).id + ":" + transportPolicy }
}
public struct ConnectionCredentials: Sendable, Codable, Equatable {
  public let password: String
  public let apiKey: String
  public init(password: String = "", apiKey: String = "") {
    self.password = password
    self.apiKey = apiKey
  }
}
