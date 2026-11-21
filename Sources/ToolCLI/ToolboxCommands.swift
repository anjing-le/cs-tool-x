import ArgumentParser
import Foundation
import ToolCore

struct ToolboxCommands: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "toolbox", abstract: "Offline utilities; no network or configuration writes.",
    subcommands: [List.self, Run.self])
  struct List: ParsableCommand {
    func run() throws { try emit(value(Toolbox.items)) }
  }
  struct Run: AsyncParsableCommand {
    @OptionGroup var input: Input
    @OptionGroup var options: Options
    func run() async throws {
      let r = try input.read()
      try r.allow(["tool", "mode", "text", "other", "replacement", "length", "count", "file"])
      let request = ToolboxRequest(
        tool: try r.string("tool"), mode: try r.string("mode", default: ""),
        text: try r.string("text", default: ""), other: try r.string("other", default: ""),
        length: try r.integer("length", default: 24), count: try r.integer("count", default: 1),
        file: r.fields["file"] == nil ? nil : try r.string("file"),
        replacement: try r.string("replacement", default: ""))
      do {
        try await emit(value(ToolboxWorker.run(request, executable: options.executable)))
      } catch let error as ToolboxError {
        throw CLIProblem(code: "toolbox_failed", message: error.localizedDescription, status: 5)
      }
    }
  }
}
