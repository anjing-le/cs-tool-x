import ArgumentParser
import Foundation
import ToolCore

struct Servers: ParsableCommand {
  static let configuration = CommandConfiguration(subcommands: [
    List.self, Show.self, Put.self, Delete.self,
  ])
  struct List: AsyncParsableCommand {
    @OptionGroup var options: Options
    func run() async throws {
      let state = try await ShellStore(directory: options.directory).snapshot()
      try emit(
        .object([
          "servers": .array(try state.value.servers.map { try serverValue($0, secrets: false) }),
          "groups": .array(state.value.groups.map(JSONValue.string)),
          "revision": .string(state.revision),
        ]))
    }
  }
  struct Show: AsyncParsableCommand {
    @OptionGroup var options: Options
    @Argument var id: Int
    @Flag(
      name: .long, help: "Explicitly include the saved plaintext password in this local output.")
    var showSecrets = false
    func run() async throws {
      let state = try await ShellStore(directory: options.directory).snapshot()
      guard let server = state.value.servers.first(where: { $0.id == id }) else {
        throw CLIProblem(code: "not_found", message: "Server ID not found.", status: 3)
      }
      try emit(
        .object([
          "server": try serverValue(server, secrets: showSecrets),
          "revision": .string(state.revision),
        ]))
    }
  }
  struct Put: AsyncParsableCommand {
    @OptionGroup var options: Options
    @OptionGroup var source: Input
    @Option(name: .long) var ifRevision: String?
    func run() async throws {
      let request = try source.read()
      try request.allow(["id", "name", "host", "user", "port", "group", "password", "notes"])
      let requestedID = try request.fields["id"].map { _ in try request.integer("id") }
      var savedID = 0
      let state = try await ShellStore(directory: options.directory).update(
        expectedRevision: ifRevision
      ) { config in
        let previous = requestedID.flatMap { id in config.servers.first(where: { $0.id == id }) }
        if requestedID != nil, previous == nil {
          throw CLIProblem(
            code: "not_found", message: "Server ID not found; omit id to create a server.",
            status: 3)
        }
        if previous != nil, ifRevision == nil {
          throw CLIProblem.input("Existing server updates require --if-revision from list/show.")
        }
        let maximum = config.servers.map(\.id).max() ?? -1
        guard maximum < Int(Int32.max) else { throw ConfigurationError.invalid }
        var server = previous ?? ShellServer(id: maximum + 1, name: "", host: "", group: "日常开发")
        server.name = try request.string("name", default: previous?.name)
        server.host = try request.string("host", default: previous?.host)
        server.user = try request.string("user", default: server.user)
        server.port = try request.integer("port", default: server.port)
        server.group = try request.string("group", default: server.group)
        if let previous, !(previous.password ?? "").isEmpty,
          previous.host != server.host || previous.user != server.user
            || previous.port != server.port, request.fields["password"] == nil
        {
          throw CLIProblem.input(
            "Endpoint changes with a saved password require an explicit password field; use an empty string to clear it."
          )
        }
        if request.fields["password"] != nil {
          let password = try request.string("password")
          server.password = password.isEmpty ? nil : password
        }
        if request.fields["notes"] != nil { server.notes = try request.string("notes") }
        do { try server.validate() } catch { throw CLIProblem.input("Server validation failed.") }
        if !config.groups.contains(server.group) { config.groups.append(server.group) }
        config.servers.removeAll(where: { $0.id == server.id })
        config.servers.append(server)
        savedID = server.id
      }
      try emit(.object(["id": .number(Decimal(savedID)), "revision": .string(state.revision)]))
    }
  }
  struct Delete: AsyncParsableCommand {
    @OptionGroup var options: Options
    @Argument var id: Int
    @Option(name: .long) var ifRevision: String
    func run() async throws {
      let state = try await ShellStore(directory: options.directory).update(
        expectedRevision: ifRevision
      ) { config in
        guard config.servers.contains(where: { $0.id == id }) else {
          throw CLIProblem(code: "not_found", message: "Server ID not found.", status: 3)
        }
        config.servers.removeAll(where: { $0.id == id })
      }
      try emit(
        .object([
          "deleted": .number(Decimal(id)), "revision": .string(state.revision),
          "backup": .string("shell.json.backup"),
        ]))
    }
  }
}
struct Profiles: ParsableCommand {
  static let configuration = CommandConfiguration(subcommands: [
    List.self, Tree.self, Show.self, Put.self, Delete.self,
  ])
  struct Tree: ParsableCommand {
    static let configuration = CommandConfiguration(
      abstract:
        "Group saved profiles by endpoint, account and environment; preserve all source records.")
    @OptionGroup var options: Options
    func run() throws {
      let state = try ProfileStore(directory: options.directory).snapshot()
      try emit(
        .object([
          "connections": try value(ConnectionGroup.build(state.value)),
          "revision": .string(state.revision),
        ]))
    }
  }
  struct List: ParsableCommand {
    @OptionGroup var options: Options
    func run() throws {
      let state = try ProfileStore(directory: options.directory).snapshot()
      try emit(.object(["profiles": try value(state.value), "revision": .string(state.revision)]))
    }
  }
  struct Show: ParsableCommand {
    @OptionGroup var options: Options
    @Argument var id: String
    func run() throws {
      let state = try ProfileStore(directory: options.directory).snapshot()
      let profile = try findProfile(id, in: state.value)
      try emit(.object(["profile": try value(profile), "revision": .string(state.revision)]))
    }
  }
  struct Put: ParsableCommand {
    @OptionGroup var options: Options
    @OptionGroup var source: Input
    @Option(name: .long) var ifRevision: String?
    func run() throws {
      let request = try source.read()
      try request.allow([
        "id", "kind", "name", "environment", "host", "port", "username", "database", "tls",
        "endpoint",
      ])
      let id: UUID?
      if request.fields["id"] != nil {
        guard let parsed = UUID(uuidString: try request.string("id")) else {
          throw CLIProblem.input("Invalid profile UUID.")
        }
        id = parsed
      } else {
        id = nil
      }
      var saved = UUID()
      let state = try ProfileStore(directory: options.directory).update(
        expectedRevision: ifRevision
      ) { profiles in
        let previous = id.flatMap { id in profiles.first(where: { $0.id == id }) }
        if id != nil, previous == nil {
          throw CLIProblem(
            code: "not_found", message: "Profile UUID not found; omit id to create a profile.",
            status: 3)
        }
        if previous != nil, ifRevision == nil {
          throw CLIProblem.input("Existing profile updates require --if-revision.")
        }
        guard
          let kind = DatabaseKind(
            rawValue: try request.string("kind", default: previous?.kind.rawValue))
        else { throw CLIProblem.input("kind must be mysql, pg, es or redis.") }
        if let previous, previous.kind != kind {
          throw CLIProblem.input("Create a new profile to change database kind.")
        }
        var profile = previous ?? ConnectionProfile(kind: kind)
        profile.name = try request.string("name", default: profile.name)
        profile.environment = try request.string("environment", default: profile.environment)
        profile.host = try request.string("host", default: profile.host)
        profile.port = try request.integer("port", default: profile.port)
        profile.username = try request.string("username", default: profile.username)
        profile.database = try request.string("database", default: profile.database)
        profile.tls = try request.bool("tls", default: profile.tls)
        profile.endpoint = try request.string("endpoint", default: profile.endpoint)
        do { try profile.validate() } catch { throw CLIProblem.input("Profile validation failed.") }
        profiles.removeAll(where: { $0.id == profile.id })
        profiles.append(profile)
        saved = profile.id
      }
      try emit(.object(["id": .string(saved.uuidString), "revision": .string(state.revision)]))
    }
  }
  struct Delete: ParsableCommand {
    @OptionGroup var options: Options
    @Argument var id: String
    @Option(name: .long) var ifRevision: String
    func run() throws {
      let state = try ProfileStore(directory: options.directory).update(
        expectedRevision: ifRevision
      ) { profiles in
        let profile = try findProfile(id, in: profiles)
        profiles.removeAll(where: { $0.id == profile.id })
      }
      try emit(
        .object([
          "deleted": .string(id), "revision": .string(state.revision),
          "backup": .string("connections.json.backup"),
        ]))
    }
  }
}
func findProfile(_ id: String, in profiles: [ConnectionProfile]) throws -> ConnectionProfile {
  guard let uuid = UUID(uuidString: id) else { throw CLIProblem.input("Invalid profile UUID.") }
  guard let profile = profiles.first(where: { $0.id == uuid }) else {
    throw CLIProblem(code: "not_found", message: "Profile UUID not found.", status: 3)
  }
  return profile
}
