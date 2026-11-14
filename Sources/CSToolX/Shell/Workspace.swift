import AppKit
import SwiftUI
import ToolCore

enum Ink {
  static let background = Color(nsColor: Theme.paper)
  static let main = Color(nsColor: Theme.ink)
  static let muted = Color(nsColor: Theme.muted)
  static let sage = Color(nsColor: Theme.sage)
  static let pale = Color(nsColor: Theme.pale)
  static let blue = Color(red: 0.39, green: 0.53, blue: 0.64)
  static let peach = Color(red: 0.74, green: 0.48, blue: 0.35)
  static let line = Color(red: 0.42, green: 0.43, blue: 0.36).opacity(0.17)
}

typealias Server = ShellServer
extension ShellServer { var tint: Color { Ink.sage } }
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
  private var reloadSerial = 0
  private var fileRevision = ConfigurationFile.missingRevision
  private var saveTask: Task<Void, Never>?
  init() { reloadConfiguration() }
  func reloadConfiguration() {
    guard sidebarPanel == nil, saveTask == nil else { return }
    reloadSerial += 1
    let generation = reloadSerial
    let current = revision
    Task { [weak self] in
      guard let self else { return }
      do {
        let loaded = try await store.snapshot()
        guard revision == current, reloadSerial == generation, sidebarPanel == nil, saveTask == nil
        else { return }
        servers = loaded.value.servers
        groups = loaded.value.groups.isEmpty ? ["日常开发"] : loaded.value.groups
        fileRevision = loaded.revision
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
  @Published var selectedServerID: Int?
  func activate(_ server: Server) {
    selectedServerID = server.id
    if let existing = sessions.last(where: { $0.server.id == server.id }) {
      select(existing.id)
    } else {
      open(server)
    }
  }
  func saveServer(
    id: Int?, name: String, host: String, group: String, user: String, port: String,
    password: String = "", notes: String = ""
  )
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
    guard password.utf8.count <= 4096,
      !password.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\0" }),
      notes.utf8.count <= 4096
    else { return "密码不能含换行或空字符，密码和备注均不得超过 4 KiB。" }
    guard groups.contains(group) else { return "请选择分组。" }
    guard id != nil || servers.count < 100 else { return "最多保存 100 台服务器。" }
    let server = Server(
      id: id ?? ((servers.map(\.id).max() ?? -1) + 1), name: name, host: host, group: group,
      port: Int(port)!, user: user, password: password.isEmpty ? nil : password,
      notes: notes.isEmpty ? nil : notes)
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
    let current = revision
    let config = ShellConfiguration(servers: servers, groups: groups)
    let previous = saveTask
    saveTask = Task {
      await previous?.value
      do { fileRevision = try await store.save(config, expectedRevision: fileRevision) } catch {
        message(error.localizedDescription)
      }
      if revision == current { saveTask = nil }
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
  func select(_ id: UUID) {
    selected = id
    selectedServerID = active?.server.id
  }
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
