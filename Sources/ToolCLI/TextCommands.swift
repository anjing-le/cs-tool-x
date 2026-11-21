import ArgumentParser
import Foundation
import ToolCore

struct TextCommands: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "text",
    abstract: "Read-only local text utilities; never modify GUI manuscripts or files.",
    subcommands: [Inspect.self, Preview.self])
  struct Inspect: AsyncParsableCommand {
    @Argument var file: String
    @OptionGroup var options: Options
    func run() async throws {
      let text = try await TextWorkbench.importText(
        URL(fileURLWithPath: file), executable: options.markdownURL)
      let statistics = try await Task.detached(priority: .userInitiated) {
        try TextStatisticsIndex(text).snapshot
      }.value
      try emit(
        .object([
          "statistics": try value(statistics),
          "encoding": .string("UTF-8"), "bytes": .number(Decimal(text.utf8.count)),
          "utf16Units": .number(Decimal((text as NSString).length)),
          "markdownPreviewWithinByteBudget": .bool(text.utf8.count <= TextWorkbench.previewBytes),
        ]))
    }
  }
  struct Preview: AsyncParsableCommand {
    @Argument var file: String
    @OptionGroup var options: Options
    func run() async throws {
      let text = try await TextWorkbench.importText(
        URL(fileURLWithPath: file), executable: options.markdownURL,
        limit: TextWorkbench.previewBytes)
      let executable = options.markdownURL
      let html = try await TextWorkbench.preview(text, executable: executable)
      try emit(
        .object([
          "html": .string(TextWorkbench.page(html)), "externalResources": .bool(false),
          "inputBytes": .number(Decimal(text.utf8.count)),
        ]))
    }
  }
}
