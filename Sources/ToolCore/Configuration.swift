import CryptoKit
import Darwin
import Foundation

public enum ConfigurationPaths {
  public static var directory: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent(
        Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true ? "cs-tool-x-dev" : "cs-tool-x",
        isDirectory: true)
  }
}
public struct ConfigurationSnapshot<Value> {
  public let value: Value
  public let revision: String
}
extension ConfigurationSnapshot: Sendable where Value: Sendable {}
public enum ConfigurationError: Error, LocalizedError {
  case conflict, busy, invalid
  public var errorDescription: String? {
    switch self {
    case .conflict: return "配置已被其他进程修改，请重新读取后重试。"
    case .busy: return "配置正被其他进程使用，请稍后重试。"
    case .invalid: return "配置无效、超出上限或不是当前用户的普通文件。"
    }
  }
}
/// Immutable file location; atomic replacement + cross-process locking + optional compare-and-swap.
public struct ConfigurationFile: Sendable {
  public static let missingRevision = "missing"
  public static let maxBytes = 1024 * 1024
  public let url: URL
  public init(url: URL) { self.url = url }
  private func data() throws -> Data? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
    guard attrs[.type] as? FileAttributeType == .typeRegular,
      (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == getuid()
    else { throw ConfigurationError.invalid }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let bytes = try handle.read(upToCount: Self.maxBytes + 1) ?? Data()
    guard bytes.count <= Self.maxBytes else { throw ConfigurationError.invalid }
    return bytes
  }
  private func revision(_ data: Data?) -> String {
    data.map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
      ?? Self.missingRevision
  }
  private func decode<T: Decodable>(_ bytes: Data?, default empty: T) throws -> T {
    guard let bytes else { return empty }
    do { return try JSONDecoder().decode(T.self, from: bytes) }
    catch { throw ConfigurationError.invalid }
  }
  public func snapshot<T: Decodable>(default empty: T) throws -> ConfigurationSnapshot<T> {
    let bytes = try data()
    return ConfigurationSnapshot(
      value: try decode(bytes, default: empty),
      revision: revision(bytes))
  }
  private func locked<T>(_ body: () throws -> T) throws -> T {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    let lock = url.appendingPathExtension("lock")
    let fd = Darwin.open(lock.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
    guard fd >= 0 else { throw ConfigurationError.invalid }
    defer { Darwin.close(fd) }
    var info = stat()
    guard fstat(fd, &info) == 0, info.st_uid == getuid(), (info.st_mode & S_IFMT) == S_IFREG else {
      throw ConfigurationError.invalid
    }
    let end = ProcessInfo.processInfo.systemUptime + 2
    while flock(fd, LOCK_EX | LOCK_NB) != 0 {
      guard errno == EWOULDBLOCK || errno == EAGAIN else { throw ConfigurationError.invalid }
      guard ProcessInfo.processInfo.systemUptime < end else { throw ConfigurationError.busy }
      usleep(10_000)
    }
    defer { flock(fd, LOCK_UN) }
    return try body()
  }
  private func replace(_ bytes: Data) throws {
    guard bytes.count <= Self.maxBytes else { throw ConfigurationError.invalid }
    let temporary = url.deletingLastPathComponent().appendingPathComponent(
      ".config-\(UUID().uuidString)")
    let fd = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
    guard fd >= 0 else { throw ConfigurationError.invalid }
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    defer {
      try? handle.close()
      try? FileManager.default.removeItem(at: temporary)
    }
    try handle.write(contentsOf: bytes)
    try handle.synchronize()
    guard Darwin.rename(temporary.path, url.path) == 0 else { throw ConfigurationError.invalid }
  }
  @discardableResult public func update<T: Codable>(
    default empty: T, expectedRevision: String? = nil,
    _ body: (inout T) throws -> Void
  ) throws -> ConfigurationSnapshot<T> {
    try locked {
      let before = try data()
      if let expectedRevision, revision(before) != expectedRevision {
        throw ConfigurationError.conflict
      }
      var value = try decode(before, default: empty)
      try body(&value)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let bytes = try encoder.encode(value)
      if let before {
        try ConfigurationFile(url: url.appendingPathExtension("backup")).replace(before)
      }
      try replace(bytes)
      return ConfigurationSnapshot(value: value, revision: revision(bytes))
    }
  }
}
