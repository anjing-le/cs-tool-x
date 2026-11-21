import ArgumentParser
import Darwin
import Foundation
import ToolCore

struct CLIProblem: Error {
  let code: String
  let message: String
  let status: Int32
  var details: JSONValue? = nil
  static func input(_ message: String = "Invalid JSON input; see cs-tool-x schema.") -> Self {
    Self(code: "invalid_input", message: message, status: 2)
  }
}
struct Failure: Encodable {
  let code: String
  let message: String
  let details: JSONValue?
}
struct Envelope: Encodable {
  let schemaVersion = 1
  let ok: Bool
  let result: JSONValue?
  let error: Failure?
}
func value<T: Encodable>(_ object: T) throws -> JSONValue {
  try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(object))
}
func emit(_ result: JSONValue) throws {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys]
  var data = try encoder.encode(Envelope(ok: true, result: result, error: nil))
  data.append(10)
  try FileHandle.standardOutput.write(contentsOf: data)
}
func fail(_ problem: CLIProblem) -> Never {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.sortedKeys]
  if var bytes = try? encoder.encode(
    Envelope(
      ok: false, result: nil,
      error: Failure(code: problem.code, message: problem.message, details: problem.details)))
  {
    bytes.append(10)
    try? FileHandle.standardOutput.write(contentsOf: bytes)
  }
  exit(problem.status)
}
struct Options: ParsableArguments {
  @Option(name: .long, help: "Configuration directory; defaults to the GUI's local configuration.")
  var configDir: String?
  @Option(name: .long, help: "Override the packaged data-engine path.") var engine: String?
  var directory: URL {
    configDir.map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
      ?? ConfigurationPaths.directory
  }
  var application: URL {
    let binary = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    let root = binary.deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
    return FileManager.default.fileExists(
      atPath: root.appendingPathComponent("Contents/Info.plist").path)
      ? root : URL(fileURLWithPath: "/Applications/cs-tool-x.app")
  }
  var markdownURL: URL {
    let adjacent = executable.deletingLastPathComponent().appendingPathComponent("cs-tool-markdown")
    return FileManager.default.isExecutableFile(atPath: adjacent.path) ? adjacent : application.appendingPathComponent("Contents/Helpers/cs-tool-markdown")
  }
  var engineURL: URL {
    engine.map { URL(fileURLWithPath: $0).standardizedFileURL }
      ?? application.appendingPathComponent("Contents/Helpers/cs-tool-engine")
  }
  var helper: URL { application.appendingPathComponent("Contents/Resources/ssh-askpass") }
  var executable: URL { URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath() }
  func server(_ id: Int) async throws -> ShellServer {
    let snapshot = try await ShellStore(directory: directory).snapshot()
    guard let server = snapshot.value.servers.first(where: { $0.id == id }) else {
      throw CLIProblem(code: "not_found", message: "Server ID not found.", status: 3)
    }
    return server
  }
}
struct Input: ParsableArguments {
  @Option(name: .long, help: "JSON input file or '-' for bounded stdin (EOF required).") var input:
    String = "-"
  func read() throws -> Request {
    let handle: FileHandle
    if input == "-" {
      guard isatty(STDIN_FILENO) == 0 else {
        throw CLIProblem.input(
          "Supply JSON with --input FILE or a pipe; interactive prompts are disabled.")
      }
      handle = FileHandle.standardInput
    } else {
      do { handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: input)) }
      catch { throw CLIProblem.input("Unable to read the JSON input file.") }
    }
    defer { if input != "-" { try? handle.close() } }
    var data = Data()
    while let chunk = try handle.read(
      upToCount: min(64 * 1024, ConfigurationFile.maxBytes + 1 - data.count)), !chunk.isEmpty
    {
      data.append(chunk)
      guard data.count <= ConfigurationFile.maxBytes else {
        throw CLIProblem.input("Input exceeds 1 MiB.")
      }
    }
    guard let object = try? JSONDecoder().decode([String: JSONValue].self, from: data) else {
      throw CLIProblem.input()
    }
    return Request(fields: object)
  }
}
struct Request {
  let fields: [String: JSONValue]
  func allow(_ keys: Set<String>) throws {
    guard Set(fields.keys).isSubset(of: keys) else {
      throw CLIProblem.input("Unknown JSON fields; see cs-tool-x schema.")
    }
  }
  func string(_ name: String, default fallback: String? = nil) throws -> String {
    guard let v = fields[name] else {
      if let fallback { return fallback }
      throw CLIProblem.input("Missing required field: \(name).")
    }
    guard case .string(let text) = v else {
      throw CLIProblem.input("Expected a string field: \(name).")
    }
    return text
  }
  func integer(_ name: String, default fallback: Int? = nil) throws -> Int {
    guard let v = fields[name] else {
      if let fallback { return fallback }
      throw CLIProblem.input("Missing required integer: \(name).")
    }
    guard case .number(let n) = v, let number = Int(NSDecimalNumber(decimal: n).stringValue) else {
      throw CLIProblem.input("Expected an integer field: \(name).")
    }
    return number
  }
  func bool(_ name: String, default fallback: Bool = false) throws -> Bool {
    guard let v = fields[name] else { return fallback }
    guard case .bool(let b) = v else {
      throw CLIProblem.input("Expected a boolean field: \(name).")
    }
    return b
  }
}
func serverValue(_ server: ShellServer, secrets: Bool) throws -> JSONValue {
  guard case .object(var object) = try value(server) else { throw CLIProblem.input() }
  object["passwordStored"] = .bool(!(server.password ?? "").isEmpty)
  if !secrets { object.removeValue(forKey: "password") }
  return .object(object)
}
