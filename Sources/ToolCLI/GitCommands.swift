import ArgumentParser
import Foundation
import ToolCore

struct GitCommands: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "git", abstract: "Local read-only repository browser. No fetch or Git writes.",
    subcommands: [Scan.self, Refs.self, Log.self, Show.self])
  struct Scan: AsyncParsableCommand {
    @OptionGroup var options: Options
    @Argument var directory: String
    func run() async throws { try emit(try value(await GitBrowser.scan(directory: directory))) }
  }
  struct Refs: AsyncParsableCommand {
    @OptionGroup var options: Options
    @Argument var repository: String
    func run() async throws { try emit(try value(await snapshot(repository))) }
  }
  struct Log: AsyncParsableCommand {
    @OptionGroup var options: Options
    @Argument var repository: String
    @Option(name: .long) var branch = ""
    @Option(name: .long) var search = ""
    @Option(name: .long) var author = ""
    @Option(name: .long) var days = 0
    @Option(name: .long) var offset = 0
    @Option(name: .long) var limit = 200
    func run() async throws {
      var filter = GitLogFilter()
      filter.reference = branch
      filter.text = search
      filter.author = author
      filter.days = days
      do { try filter.validate() } catch {
        throw CLIProblem.input("Invalid Git filters or input limits.")
      }
      guard offset >= 0 && offset < GitBrowser.maxLoadedCommits, (1...200).contains(limit) else {
        throw CLIProblem.input("Invalid Git page bounds.")
      }
      let repo = try await snapshot(repository)
      try emit(try value(await GitBrowser.log(repo, filter: filter, offset: offset, limit: limit)))
    }
  }
  struct Show: AsyncParsableCommand {
    @OptionGroup var options: Options
    @Argument var repository: String
    @Argument var oid: String
    func run() async throws {
      guard GitBrowser.validOID(oid) else {
        throw CLIProblem.input("Expected a full 40/64-character commit hash.")
      }
      let repo = try await snapshot(repository)
      try emit(try value(await GitBrowser.detail(repository: repo, oid: oid)))
    }
  }
}
private func snapshot(_ path: String) async throws -> GitRepository {
  let url = URL(fileURLWithPath: try GitBrowser.canonicalPath(path))
  return try await GitBrowser.repository(GitLocation(path: url.path, name: url.lastPathComponent))
}
