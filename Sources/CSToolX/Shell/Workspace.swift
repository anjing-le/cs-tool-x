import AppKit
import SwiftUI
import ToolCore

enum Ink {
  static let background = Color(red: 0.99, green: 0.987, blue: 0.975)
  static let main = Color(red: 0.24, green: 0.26, blue: 0.24)
  static let muted = Color(red: 0.52, green: 0.53, blue: 0.49)
  static let sage = Color(red: 0.37, green: 0.49, blue: 0.39)
  static let pale = Color(red: 0.88, green: 0.91, blue: 0.85)
  static let blue = Color(red: 0.39, green: 0.53, blue: 0.64)
  static let peach = Color(red: 0.74, green: 0.48, blue: 0.35)
  static let line = Color(red: 0.42, green: 0.43, blue: 0.36).opacity(0.17)
}

struct Server: Identifiable, Codable, Equatable, Sendable {
  let id: Int
  var name: String
  var host: String
  var group: String
  var port: Int = 22
  var user: String = ""
  var tint: Color { Ink.sage }
  var local: Bool { id == -1 }
  static let localServer = Server(id: -1, name: "本地终端", host: "localhost", group: "本机")
}
@MainActor
final class Session: ObservableObject, Identifiable {
  let id = UUID()
  let server: Server
  @Published var main: RealTerminal
  @Published var second: RealTerminal?
  @Published var focusedPane: UUID
  @Published var vertical = false
  @Published var splitFraction: Double =
    UserDefaults.standard.object(forKey: "terminal.fraction") as? Double ?? 0.52
  init(server: Server) {
    self.server = server
    let terminal = RealTerminal(server: server)
    main = terminal
    focusedPane = terminal.id
  }
  func split(vertical: Bool) {
    self.vertical = vertical
    if second == nil { second = RealTerminal(server: server) }
  }
  func closePane(_ id: UUID) {
    if main.id == id, let second {
      main.stop()
      main = second
      self.second = nil
    } else {
      second?.stop()
      second = nil
    }
    focusedPane = main.id
  }
  func stop() {
    main.stop()
    second?.stop()
  }
}
struct ShellConfiguration: Codable, Sendable {
  var servers: [Server]
  var groups: [String]
}
actor ShellStore {
  private var revision = -1
  private var url: URL {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent(
        Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true ? "cs-tool-x-dev" : "cs-tool-x",
        isDirectory: true
      ).appendingPathComponent("shell.json")
  }
  func load() throws -> ShellConfiguration? {
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let data = try Data(contentsOf: url)
    guard data.count <= 1024 * 1024 else { throw ToolError.message("服务器配置过大。") }
    let config = try JSONDecoder().decode(ShellConfiguration.self, from: data)
    guard config.servers.count <= 100, config.groups.count <= 50 else {
      throw ToolError.message("服务器配置超过上限。")
    }
    return config
  }
  func save(_ config: ShellConfiguration, revision: Int) throws {
    guard revision >= self.revision else { return }
    self.revision = revision
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700])
    try JSONEncoder().encode(config).write(to: url, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }
}
@MainActor
final class Workspace: ObservableObject {
  @Published var servers: [Server] = []
  @Published var groups = ["日常开发"]
  @Published var sidebarPanel: SidebarPanel?
  @Published var sessions: [Session] = []
  @Published var selected: UUID?
  @Published var query = ""
  @Published var collapsed: Set<String> = []
  @Published var settings = false
  @Published var notice: String?
  private var noticeTask: Task<Void, Never>?
  private var revision = 0
  private let store = ShellStore()
  init() {
    Task { [weak self] in
      guard let self else { return }
      do {
        if let config = try await store.load(), revision == 0 {
          servers = config.servers
          groups = config.groups.isEmpty ? ["日常开发"] : config.groups
        }
      } catch { message(error.localizedDescription) }
    }
  }
  var active: Session? { sessions.first { $0.id == selected } }
  var searchTerms: [String] { query.split(whereSeparator: { $0.isWhitespace }).map(String.init) }
  var searching: Bool { !searchTerms.isEmpty }
  var matchingServers: [Server] {
    servers.filter { server in
      let text = "\(server.name) \(server.host) \(server.group) \(server.user)"
      return searchTerms.allSatisfy { text.localizedCaseInsensitiveContains($0) }
    }
  }
  func activate(_ server: Server) {
    if let existing = sessions.last(where: { $0.server.id == server.id }) {
      select(existing.id)
    } else {
      open(server)
    }
  }
  func saveServer(id: Int?, name: String, host: String, group: String, user: String, port: String)
    -> String?
  {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
    let user = user.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, name.count <= 100 else { return "请填写不超过 100 字的名称。" }
    guard !host.contains("://"), !host.contains("/"), !host.contains("@") else {
      return "请填写 IP、主机名或 SSH Host 别名。"
    }
    do { _ = try SSHCommand.arguments(host: host, user: user, port: port, sftp: false) } catch {
      return error.localizedDescription
    }
    guard groups.contains(group) else { return "请选择分组。" }
    guard id != nil || servers.count < 100 else { return "最多保存 100 台服务器。" }
    let server = Server(
      id: id ?? ((servers.map(\.id).max() ?? -1) + 1), name: name, host: host, group: group,
      port: Int(port)!, user: user)
    if let index = servers.firstIndex(where: { $0.id == server.id }) {
      servers[index] = server
    } else {
      servers.append(server)
    }
    collapsed.remove(group)
    query = ""
    sidebarPanel = nil
    persist()
    return nil
  }
  func saveGroup(original: String?, name: String) -> String? {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, name.count <= 100 else { return "请填写不超过 100 字的分组名。" }
    guard
      !groups.contains(where: {
        $0 != original && $0.localizedCaseInsensitiveCompare(name) == .orderedSame
      })
    else { return "分组已经存在。" }
    if let original, let i = groups.firstIndex(of: original) {
      groups[i] = name
      for j in servers.indices where servers[j].group == original { servers[j].group = name }
      if collapsed.remove(original) != nil { collapsed.insert(name) }
    } else {
      guard groups.count < 50 else { return "最多 50 个分组。" }
      groups.append(name)
    }
    query = ""
    sidebarPanel = nil
    persist()
    return nil
  }
  private func persist() {
    revision += 1
    let version = revision
    let config = ShellConfiguration(servers: servers, groups: groups)
    Task {
      do { try await store.save(config, revision: version) } catch {
        message(error.localizedDescription)
      }
    }
  }
  func open(_ server: Server) {
    guard sessions.count < 4 else {
      message("最多同时保留 4 个终端标签，每个标签最多两块分屏。")
      return
    }
    let session = Session(server: server)
    sessions.append(session)
    selected = session.id
  }
  func openLocal() { open(.localServer) }
  func newTab() { open(active?.server ?? .localServer) }
  func select(_ id: UUID) { selected = id }
  func close(_ id: UUID) {
    guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
    sessions[i].stop()
    sessions.remove(at: i)
    if selected == id {
      selected = sessions.isEmpty ? nil : sessions[min(i, sessions.count - 1)].id
    }
  }
  func cycle(_ direction: Int) {
    guard !sessions.isEmpty else { return }
    let i = sessions.firstIndex(where: { $0.id == selected }) ?? 0
    select(sessions[(i + direction + sessions.count) % sessions.count].id)
  }
  func message(_ text: String) {
    noticeTask?.cancel()
    notice = text
    noticeTask = Task {
      try? await Task.sleep(nanoseconds: 4_000_000_000)
      if !Task.isCancelled { notice = nil }
    }
  }
  func stop() {
    sessions.forEach { $0.stop() }
    sessions = []
    selected = nil
    noticeTask?.cancel()
  }
}
enum SidebarPanel: Equatable {
  case add
  case server(id: Int?, group: String)
  case group(original: String?)
  case serverActions(Int)
  case groupActions(String)
}
