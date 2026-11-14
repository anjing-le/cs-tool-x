import ArgumentParser
import Foundation
import ToolCore

struct DataCommands: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "data", subcommands: [Query.self, Catalog.self, Browse.self])
  struct Query: AsyncParsableCommand {
    @OptionGroup var options: Options
    @OptionGroup var source: Input
    @Argument var id: String
    func run() async throws {
      try await query(id: id, options: options, request: source.read(), catalog: false)
    }
  }
  struct Browse: AsyncParsableCommand {
    @OptionGroup var options: Options
    @OptionGroup var source: Input
    @Argument var id: String
    @Option(name: .long, help: "SQL metadata level: databases, schemas (PG), tables.") var level:
      String = "databases"
    @Option(name: .long, help: "Database (MySQL tables) or schema (PG tables).") var scope: String =
      ""
    func run() async throws {
      guard ["databases", "schemas", "tables"].contains(level), level != "tables" || !scope.isEmpty
      else {
        throw CLIProblem.input("Choose databases, schemas, or tables with --scope.")
      }
      try await query(
        id: id, options: options, request: source.read(), catalog: true, browseAction: level,
        scope: scope)
    }
  }
  struct Catalog: AsyncParsableCommand {
    @OptionGroup var options: Options
    @OptionGroup var source: Input
    @Argument var id: String
    func run() async throws {
      try await query(id: id, options: options, request: source.read(), catalog: true)
    }
  }
}
private func query(
  id: String, options: Options, request: Request, catalog: Bool, browseAction: String? = nil,
  scope: String = ""
) async throws {
  try request.allow(
    browseAction != nil
      ? ["password", "apiKey"]
      : catalog
        ? ["password", "apiKey", "text"] : ["password", "apiKey", "text", "target", "cursor"])
  let profile = try findProfile(id, in: ProfileStore(directory: options.directory).load())
  if browseAction != nil, ![DatabaseKind.mysql, .pg].contains(profile.kind) {
    throw CLIProblem.input("data browse supports MySQL and PostgreSQL metadata.")
  }
  let password = try request.string("password", default: "")
  let apiKey = try request.string("apiKey", default: "")
  let text = try request.string("text", default: catalog ? "*" : nil)
  let target = try request.string("target", default: "")
  let cursor = try request.string("cursor", default: "0")
  let engine = EngineClient(executable: options.engineURL)
  do {
    let (session, elapsed) = try await engine.connect(
      profile: profile, password: password, apiKey: apiKey)
    let output = try await engine.run(
      id: session, action: browseAction ?? (catalog ? "catalog" : "query"), text: text,
      target: browseAction == nil ? target : scope, cursor: cursor
    )
    try await engine.disconnect(id: session)
    await engine.stop()
    try emit(
      .object([
        "profileID": .string(profile.id.uuidString), "connectElapsedMs": .number(Decimal(elapsed)),
        "output": try value(output),
      ]))
  } catch {
    await engine.stop()
    throw error
  }
}
struct RemoteOptions: ParsableArguments {
  @Option(name: .long, help: "Whole operation deadline, 1...120 seconds.") var timeout: Int = 15
  @Option(name: .long, help: "Combined stdout/stderr byte budget, at most 8 MiB.")
  var maxOutputBytes: Int = 1024 * 1024
  func validate() throws {
    guard (1...120).contains(timeout), (1...8 * 1024 * 1024).contains(maxOutputBytes) else {
      throw ValidationError("Invalid remote operation limits.")
    }
  }
}
struct SSHCommands: ParsableCommand {
  static let configuration = CommandConfiguration(commandName: "ssh", subcommands: [Exec.self])
  struct Exec: AsyncParsableCommand {
    @OptionGroup var options: Options
    @OptionGroup var source: Input
    @OptionGroup var limits: RemoteOptions
    @Argument var id: Int
    func run() async throws {
      let request = try source.read()
      try request.allow(["command"])
      let command = try request.string("command")
      guard !command.isEmpty, command.utf8.count <= 65536, !command.contains("\0") else {
        throw CLIProblem.input("Remote script must be 1...65536 bytes with no NUL.")
      }
      let server = try await options.server(id)
      var args = try SSHLaunch.noninteractiveArguments(
        server: server, sftp: false, timeout: limits.timeout)
      args.append("sh -s")
      try await remote(
        executable: "/usr/bin/ssh", args: args, input: Data((command + "\n").utf8), server: server,
        options: options, limits: limits)
    }
  }
}
struct SFTPCommands: ParsableCommand {
  static let configuration = CommandConfiguration(commandName: "sftp", subcommands: [List.self])
  struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "ls")
    @OptionGroup var options: Options
    @OptionGroup var source: Input
    @OptionGroup var limits: RemoteOptions
    @Argument var id: Int
    func run() async throws {
      let request = try source.read()
      try request.allow(["path"])
      let path = try request.string("path", default: ".")
      guard !path.isEmpty, path.utf8.count <= 4096,
        !path.contains(where: { $0 == "\r" || $0 == "\n" || $0 == "\0" })
      else { throw CLIProblem.input("Invalid SFTP path.") }
      // Quote the SFTP command language, not a local shell command.
      let quoted = path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(
        of: "\"", with: "\\\"")
      let server = try await options.server(id)
      var args = try SSHLaunch.noninteractiveArguments(
        server: server, sftp: true, timeout: limits.timeout)
      args.insert(contentsOf: ["-b", "-"], at: args.firstIndex(of: "--")!)
      try await remote(
        executable: "/usr/bin/sftp", args: args, input: Data("ls -l -- \"\(quoted)\"\nbye\n".utf8),
        server: server, options: options, limits: limits)
    }
  }
}
private func remote(
  executable: String, args: [String], input: Data, server: ShellServer, options: Options,
  limits: RemoteOptions
) async throws {
  var environment = try SSHLaunch.environment(
    server: server, configuration: options.directory.appendingPathComponent("shell.json"),
    helper: options.helper, executable: options.executable)
  if (server.password ?? "").isEmpty {
    environment["SSH_ASKPASS_REQUIRE"] = "never"
    environment.removeValue(forKey: "SSH_ASKPASS")
  }
  let result = try await BoundedProcess.run(
    executable: URL(fileURLWithPath: executable), arguments: args, environment: environment,
    input: input,
    timeout: Double(limits.timeout), maxOutputBytes: limits.maxOutputBytes)
  let details = try value(result)
  if result.timedOut {
    throw CLIProblem(
      code: "deadline",
      message: "Local SSH/SFTP deadline exceeded; remote completion may be unknown.", status: 6,
      details: details)
  }
  if result.truncated {
    throw CLIProblem(
      code: "output_limit",
      message: "Output was limited or incompletely drained; remote completion may be unknown.",
      status: 7, details: details)
  }
  if result.exitCode != 0 {
    throw CLIProblem(
      code: "remote_exit", message: "SSH/SFTP exited unsuccessfully; inspect bounded stderr.",
      status: 5, details: details)
  }
  try emit(details)
}
