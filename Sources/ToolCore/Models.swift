import Foundation

public enum ToolModule: String, CaseIterable, Codable, Sendable {
  case data, terminal, files, requests, utilities, git
  public var title: String {
    switch self {
    case .git: return "Git"
    case .data: return "数据"
    case .terminal: return "终端"
    case .files: return "文件"
    case .requests: return "接口"
    case .utilities: return "百宝箱"
    }
  }
  public var symbol: String {
    switch self {
    case .git: return "arrow.triangle.branch"
    case .data: return "externaldrive"
    case .terminal: return "terminal"
    case .files: return "folder"
    case .requests: return "arrow.left.arrow.right"
    case .utilities: return "wrench.and.screwdriver"
    }
  }
  public var available: Bool {
    self == .data || self == .terminal || self == .files || self == .git || self == .utilities
  }
}
public enum DatabaseKind: String, CaseIterable, Codable, Sendable, Hashable {
  case mysql, pg, es, redis
  public var title: String {
    switch self {
    case .mysql: return "MySQL"
    case .pg: return "PostgreSQL"
    case .es: return "Elasticsearch"
    case .redis: return "Redis"
    }
  }
  public var port: Int {
    switch self {
    case .mysql: return 3306
    case .pg: return 5432
    case .es: return 9200
    case .redis: return 6379
    }
  }
  public var initialQuery: String {
    switch self {
    case .mysql, .pg: return "SELECT 1 AS connected;"
    case .es: return "{\n  \"query\": { \"match_all\": {} },\n  \"size\": 100\n}"
    case .redis: return "*"
    }
  }
}
/// Saved profile intentionally has no password, API key or private-key content.
public struct ConnectionProfile: Codable, Equatable, Identifiable, Sendable {
  public var id: UUID
  public var name: String
  public var kind: DatabaseKind
  public var environment: String
  public var host: String
  public var port: Int
  public var username: String
  public var database: String
  public var tls: Bool
  public var endpoint: String
  public init(kind: DatabaseKind = .mysql) {
    id = UUID()
    name = ""
    self.kind = kind
    environment = "开发"
    host = "localhost"
    port = kind.port
    username = kind == .pg ? "postgres" : kind == .mysql ? "root" : ""
    database = kind == .redis ? "0" : ""
    tls = false
    endpoint = "http://localhost:9200"
  }
  public var displayName: String { name.isEmpty ? "\(kind.title) · \(environment)" : name }
  public var address: String { kind == .es ? endpoint : "\(host):\(port) / \(database)" }
  public func validate() throws {
    guard (1...65535).contains(port), host.utf8.count <= 1024, name.utf8.count <= 256 else {
      throw ToolError.message("主机、端口或名称无效。")
    }
    if kind == .es {
      guard let url = URL(string: endpoint), ["http", "https"].contains(url.scheme ?? ""),
        url.host != nil,
        url.user == nil, url.password == nil, url.query == nil, url.fragment == nil
      else { throw ToolError.message("ES 地址无效；凭据请放在独立字段。") }
    } else if database.isEmpty || host.isEmpty {
      throw ToolError.message("请填写主机和数据库。")
    }
    if kind == .redis, UInt32(database) == nil { throw ToolError.message("Redis DB 必须是非负整数。") }
  }
}
public enum ToolError: Error, LocalizedError, Sendable {
  case message(String)
  public var errorDescription: String? {
    if case .message(let text) = self { return text }
    return nil
  }
}
public enum JSONValue: Codable, Equatable, Sendable {
  case null
  case bool(Bool)
  case number(Decimal)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])
  public init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() {
      self = .null
    } else if let v = try? c.decode(Bool.self) {
      self = .bool(v)
    } else if let v = try? c.decode(String.self) {
      self = .string(v)
    } else if let v = try? c.decode(Decimal.self) {
      self = .number(v)
    } else if let v = try? c.decode([JSONValue].self) {
      self = .array(v)
    } else {
      self = .object(try c.decode([String: JSONValue].self))
    }
  }
  public func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .null: try c.encodeNil()
    case .bool(let v): try c.encode(v)
    case .number(let v): try c.encode(v)
    case .string(let v): try c.encode(v)
    case .array(let v): try c.encode(v)
    case .object(let v): try c.encode(v)
    }
  }
  public var text: String {
    switch self {
    case .null: return "NULL"
    case .string(let s): return s
    case .number(let n): return NSDecimalNumber(decimal: n).stringValue
    case .bool(let b): return String(b)
    default: return (try? String(data: JSONEncoder().encode(self), encoding: .utf8)) ?? ""
    }
  }
  public subscript(_ key: String) -> JSONValue? {
    if case .object(let object) = self { return object[key] }
    return nil
  }
}
public struct QueryOutput: Codable, Sendable {
  public var columns: [String]
  public var rows: [[JSONValue]]
  public var elapsedMs: Int
  public var truncated: Bool
  public var note: String
  public var nextCursor: String?
}
public enum SSHCommand {
  /// Arguments stay separate. Never concatenate a host into a shell command.
  public static func arguments(
    host: String, user: String, port: String, sftp: Bool, passwordAuthentication: Bool = false
  ) throws
    -> [String]
  {
    guard !host.isEmpty, host.utf8.count <= 1024, !host.hasPrefix("-"),
      !host.contains(where: { $0.isWhitespace || $0.isNewline }),
      !user.hasPrefix("-"), !user.contains(where: { $0.isWhitespace || $0.isNewline || $0 == "@" }),
      let number = Int(port), (1...65535).contains(number)
    else { throw ToolError.message("SSH 主机、用户名或端口无效。") }
    var args = [
      "-o", "UseKeychain=no", "-o", "AddKeysToAgent=no", "-o", "StrictHostKeyChecking=ask",
      sftp ? "-P" : "-p", String(number),
    ]
    if passwordAuthentication {
      args.insert(
        contentsOf: [
          "-o", "PreferredAuthentications=password", "-o", "PubkeyAuthentication=no",
          "-o", "KbdInteractiveAuthentication=no", "-o", "NumberOfPasswordPrompts=1", "-o",
          "BatchMode=no",
        ], at: 0)
    }
    if sftp {
      args += ["--", user.isEmpty ? host : "\(user)@\(host)"]
    } else {
      if !user.isEmpty { args += ["-l", user] }
      args += ["--", host]
    }
    return args
  }
}
