import ArgumentParser
import Darwin
import Foundation
import ToolCore

struct Root: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "cs-tool-x", abstract: "Headless local developer tools. JSON schema version 1.",
    version: "schema-1",
    subcommands: [
      Schema.self, Doctor.self, Servers.self, Profiles.self, DataCommands.self, SSHCommands.self,
      SFTPCommands.self, GitCommands.self, ToolboxCommands.self, TextCommands.self,
    ])
}
@main struct Entry {
  static func main() async {
    signal(SIGPIPE, SIG_IGN)
    if CommandLine.arguments == [CommandLine.arguments[0], "--toolbox-worker"] { ToolboxWorker.serve(); return }
    if let status = SSHPassword.helperExitCode() { exit(status) }
    var command: any ParsableCommand
    do { command = try Root.parseAsRoot() } catch {
      if Root.exitCode(for: error) == .success { Root.exit(withError: error) }
      fail(
        CLIProblem(
          code: "usage", message: "Invalid arguments. Run cs-tool-x --help or cs-tool-x schema.",
          status: 2))
    }
    do {
      if var asynchronous = command as? any AsyncParsableCommand {
        try await asynchronous.run()
      } else {
        try command.run()
      }
    } catch let problem as CLIProblem { fail(problem) } catch let error as ConfigurationError {
      switch error {
      case .conflict:
        fail(CLIProblem(code: "revision_conflict", message: error.localizedDescription, status: 4))
      case .busy:
        fail(CLIProblem(code: "configuration_busy", message: error.localizedDescription, status: 4))
      case .invalid:
        fail(
          CLIProblem(code: "invalid_configuration", message: error.localizedDescription, status: 3))
      }
    } catch is DecodingError { fail(.input("Invalid input or configuration JSON.")) } catch {
      if Root.exitCode(for: error) == .success { Root.exit(withError: error) }
      fail(CLIProblem(code: "operation_failed", message: error.localizedDescription, status: 5))
    }
  }
}
struct Doctor: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Local paths and availability; no remote connections or secrets.")
  @OptionGroup var options: Options
  func run() async throws {
    let shell = try await ShellStore(directory: options.directory).snapshot()
    let profiles = try ProfileStore(directory: options.directory).snapshot()
    let info =
      (try? Data(contentsOf: options.application.appendingPathComponent("Contents/Info.plist")))
      .flatMap {
        try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any]
      }
    try emit(
      .object([
        "configDirectory": .string(options.directory.path),
        "application": .string(options.application.path),
        "appVersion": .string(info?["CFBundleShortVersionString"] as? String ?? "unknown"),
        "enginePath": .string(options.engineURL.path),
        "engineAvailable": .bool(
          FileManager.default.isExecutableFile(atPath: options.engineURL.path)),
        "askpassAvailable": .bool(
          FileManager.default.isExecutableFile(atPath: options.helper.path)),
        "serverCount": .number(Decimal(shell.value.servers.count)),
        "profileCount": .number(Decimal(profiles.value.count)),
        "gitExecutableAvailable": .bool(
          FileManager.default.isExecutableFile(atPath: "/usr/bin/git")),
        "headless": .bool(true),
        "markdownWorkerAvailable": .bool(FileManager.default.isExecutableFile(atPath: options.application.appendingPathComponent("Contents/Helpers/cs-tool-markdown").path)),
      ]))
  }
}
struct Schema: ParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: "Machine-readable commands, limits, inputs and exit codes.")
  func run() throws {
    let data = Data(Self.document.utf8)
    try emit(try JSONDecoder().decode(JSONValue.self, from: data))
  }
  static let document = """
    {"protocol":"cs-tool-x-cli","version":1,"output":"one JSON envelope on stdout; diagnostics on stderr; --help and --version are text",
     "optionsPlacement":"put options after the leaf command","configuration":"shared with GUI; atomic 0600 writes, 2s lock deadline, SHA256 revision and one .backup per file",
     "secrets":"SSH plaintext stays in local config; read only with servers show --show-secrets. Database credentials can be stored explicitly in local 0600 data-credentials.json (no Keychain/backups); explicit per-command stdin fields override the saved credential as a whole.",
     "commands":[
      {"command":"text inspect FILE","effect":"read one local regular UTF-8 file, no writes or GUI session access","limits":"32MiB file / 128KiB per line / 15s worker deadline; reject binary/NUL/UTF-16; UTF-8 BOM accepted","output":"encoding, bytes, utf16Units, markdownPreviewWithinByteBudget"},
      {"command":"text preview FILE","effect":"read local UTF-8 file, offline CommonMark/GFM HTML computation, no GUI session access or writes","limits":"input4MiB / 128KiB per line; file read15s; HTML8MiB before JSON escaping; 30000 AST nodes/256 nesting; worker deadline5s; default raw HTML/unsafe links omitted, page CSP disables external resources/scripts; only tables/tasklist/strikethrough/autolinks added, no math/diagrams","output":"html with offline page policy, externalResources=false, inputBytes"},
      {"command":"toolbox list","effect":"local metadata read","output":"id, name, glyph, modes"},
      {"command":"toolbox run --input FILE|-","effect":"offline computation; hash file optionally reads one regular local file; no network or persistence","input":{"tool":"see toolbox list","mode":"one listed mode, defaults to first","text":"UTF-8 source; regex subject; diff original","other":"diff new text; regex ICU pattern; optional hash expected hex","replacement":"regex replace template ($1 captures)","length":"random 1..256, password minimum 4; default 24","count":"random 1..100, default 1","file":"optional hash file path"},"output":"output, detail","limits":"each string <=48KiB; encoded worker request <=128KiB; output <=384KiB; 4s then worker termination, file hash 30s; diff <=1000 lines per side; JSON depth<=128; regex pattern<=4KiB, <=500 matches, 32 capture groups, UTF-16 offsets; replacement template<=1KiB/32 references; file hash streaming 256KiB, regular file <=8GiB; MD5/SHA1 for legacy checksums only; dates use ISO8601 with timezone, UTC output; no clipboard writes"},
      {"command":"git scan DIRECTORY","effect":"local filesystem read","notes":"recursive discovery including worktrees and bare repos; skips nested .build/.swiftpm/node_modules/Pods/Carthage/.gradle/.venv/__pycache__/.cache/.local/dist/target and .git; selected root itself is included; no symlink descent; 20s / 250000 entries / 500 repositories, explicit limited flag"},
      {"command":"git refs REPOSITORY","effect":"local Git read","notes":"current branch, HEAD and local/remote/tag refs; at most 5000 refs, 20000 total refs in GUI; 4 concurrent repositories per batch, 30s batch deadline"},
      {"command":"git log REPOSITORY","effect":"local Git read","options":["--branch refs/heads/NAME","--search TEXT_OR_HASH","--author TEXT","--days 0|7|30|90|365","--offset 0..1999","--limit 1..200"],"notes":"topological history; text searches commit subjects/bodies, hash looks up exact commit, remote refs reflect last local fetch; 12s / 4MiB output"},
      {"command":"git show REPOSITORY OID","effect":"local Git read","notes":"full hash; commit message and at most 1000 changed paths; optional additions/deletions/binary per file; missing counts are unknown, never zero; statisticsError preserves file list when counts fail; first-parent merge comparison, renames as delete+add; no external diff/textconv; 12s per metadata command, 8s statistics, 256KiB message / 1MiB per list output"},
      {"command":"doctor","effect":"local read"},{"command":"schema","effect":"local read"},
      {"command":"servers list","effect":"local read","output":"servers metadata, groups, revision; no password"},
      {"command":"servers show ID","effect":"local read","options":["--show-secrets"]},
      {"command":"servers put --input FILE|-","effect":"local write","input":{"requiredOnCreate":["name","host"],"optional":["id","user","port","group","password","notes"]},"notes":"existing ID requires --if-revision; omitted fields preserve prior values, password empty string clears it"},
      {"command":"servers delete ID --if-revision TOKEN","effect":"local write"},
      {"command":"profiles list","effect":"local read"},{"command":"profiles credentials set UUID --if-revision REV --input FILE|-","effect":"local credential write","input":{"optional":["password","apiKey"]},"notes":"explicitly stores local plaintext; absent/empty fields mean intentionally empty credentials, no Keychain"},{"command":"profiles credentials status UUID","effect":"local read, flags only"},{"command":"profiles credentials clear UUID --if-revision REV","effect":"local credential removal"},{"command":"profiles tree","effect":"local read","output":"connections grouped by identity; original profiles and revision retained"},{"command":"profiles show UUID","effect":"local read"},
      {"command":"profiles put --input FILE|-","effect":"local write","input":{"requiredOnCreate":["kind"],"optional":["id","name","environment","host","port","username","database","tls","endpoint"]},"notes":"existing UUID requires --if-revision; credentials cannot be saved"},
      {"command":"profiles delete UUID --if-revision TOKEN","effect":"local write"},
      {"command":"data query UUID --input FILE|-","effect":"remote query","input":{"required":["text"],"optional":["password","apiKey","target","cursor"]},"notes":"one-shot connection; existing engine limits and SQL read-only policy apply; no arbitrary SQL writes"},
      {"command":"data browse UUID --level databases|schemas|tables --scope NAME --input FILE|-","effect":"remote metadata read","input":{"optional":["password","apiKey"]},"notes":"MySQL/PG metadata and Redis databases (nonempty keyspaces only); schemas is PG-only, tables requires scope; bound scope parameters, at most 500 rows with truncation flag"},
      {"command":"data catalog UUID --input FILE|-","effect":"remote read","input":{"optional":["password","apiKey","text"]}},
      {"command":"ssh exec ID --input FILE|-","effect":"arbitrary remote command, potentially writes","input":{"required":["command"]},"options":["--timeout 1..120","--max-output-bytes 1..8388608"],"notes":"command is a remote sh script; no local shell interpolation; timeout/output limit stop local SSH, remote completion may be unknown"},
      {"command":"sftp ls ID --input FILE|-","effect":"remote read","input":{"optional":["path"]},"options":["--timeout 1..120","--max-output-bytes 1..8388608"],"notes":"native SFTP listing text in stdout field; get/put and resumable transfer not yet exposed"}
     ],"limits":{"inputBytes":1048576,"remoteScriptBytes":65536,"defaultOutputBytes":1048576,"defaultTimeoutSeconds":15},
     "exitCodes":{"0":"success","2":"usage or invalid input","3":"missing/invalid config","4":"revision conflict or busy config","5":"operation failure or nonzero remote exit","6":"deadline","7":"output limit or incomplete drain"},
     "authorization":"Capability is not permission. Agents must follow the user's task scope before modifying config or executing remote commands. Known-host checks remain enabled; no unattended trust enrollment."}
    """
}
