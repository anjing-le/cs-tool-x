import AppKit
import Foundation
import ToolCore

@main struct GitUIRegression {
  @MainActor static func main() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    let fixture = CommandLine.arguments[1]
    let workspace = GitWorkspace(frame: NSRect(x: 0, y: 0, width: 1440, height: 850))
    let window = WorkbenchWindow(contentRect: workspace.frame)
    window.contentView = workspace
    workspace.scanDirectory(fixture)
    func idle() async throws {
      let deadline = Date().addingTimeInterval(25)
      while workspace.hasPendingWork {
        guard Date() < deadline else { throw ToolError.message("UI fixture timed out") }
        try await Task.sleep(nanoseconds: 20_000_000)
      }
      workspace.layoutSubtreeIfNeeded()
    }
    try await idle()
    precondition(workspace.repositories.count == 3, "UI discovers every fixture repository")
    func allViews(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(allViews) }
    let tables = allViews(workspace).compactMap { $0 as? NSTableView }
    let log = tables.first { $0.tableColumns.contains { $0.identifier.rawValue == "subject" } }!
    precondition(log.numberOfRows == 4, "Selected repository has four commits with a merge")
    let graph = log.view(atColumn: 1, row: 0, makeIfNecessary: true) as! GitGraphCell
    precondition(
      graph.row?.segments.filter { $0.part == .outgoing }.count == 2,
      "Merge graph has two real parent edges")
    log.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    try await idle()
    let files = tables.first { $0.tableColumns.contains { $0.title == "变更文件" } }!
    precondition(files.numberOfRows == 1, "Selected merge shows first-parent changed files")
    if CommandLine.arguments.count > 2 {
      window.layoutIfNeeded()
      let rep = workspace.bitmapImageRepForCachingDisplay(in: workspace.bounds)!
      workspace.cacheDisplay(in: workspace.bounds, to: rep)
      try rep.representation(using: .png, properties: [:])!.write(
        to: URL(fileURLWithPath: CommandLine.arguments[2]))
    }
    let fields = allViews(workspace).compactMap { $0 as? NSTextField }
    let search = fields.first { $0.placeholderString == "搜索提交信息 / 哈希" }!
    search.stringValue = "Search across commit history"
    search.sendAction(search.action, to: search.target)
    try await idle()
    precondition(log.numberOfRows == 1, "Commit search reads unshown commit body through Git")
    workspace.pause()
    precondition(!workspace.hasPendingWork, "Leaving module clears active UI read tasks")
    print(
      "PASS: offscreen Git workspace discovery, branch/graph layout, merge details, server-side history search and pause lifecycle; no live-app automation"
    )
  }
}
