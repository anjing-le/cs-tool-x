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
    let sidebar = GitSidebar()
    sidebar.update(workspace.repositories)
    let repositoryRow = sidebar.rows.firstIndex { $0.repository?.references.isEmpty == false }!
    let repository = sidebar.rows[repositoryRow].repository!
    precondition(sidebar.rows.count == 4, "Repositories begin collapsed")
    precondition(sidebar.table.doubleAction != nil, "Whole-row double click has an action")
    sidebar.table.selectRowIndexes(IndexSet(integer: repositoryRow), byExtendingSelection: false)
    let cell = sidebar.tableView(sidebar.table, viewFor: sidebar.table.tableColumns[0], row: repositoryRow)!
    precondition(!allViews(cell).contains { $0 is NSButton }, "Sidebar has no disclosure buttons")
    let labels = allViews(cell).compactMap { $0 as? NSTextField }
    precondition(labels.contains { $0.stringValue == "✓" && !$0.isHidden }, "Selected row has trailing cue")
    precondition(labels.contains { $0.stringValue == repository.branchLabel }, "Selected branch moves to the right")
    sidebar.activateSelection()
    precondition(sidebar.rows.count > 4, "Double click expands branch rows")
    sidebar.activateSelection()
    precondition(sidebar.rows.count == 4, "Double click collapses branch rows")
    sidebar.discloseSelection(true)
    let referenceRow = sidebar.rows.firstIndex { $0.reference != nil }!
    sidebar.table.selectRowIndexes(IndexSet(integer: referenceRow), byExtendingSelection: false)
    let rowCount = sidebar.rows.count
    sidebar.activateSelection()
    precondition(sidebar.rows.count == rowCount, "Activating a branch does not toggle its repository")
    sidebar.select(repository: repository.id)
    sidebar.discloseSelection(false)
    precondition(sidebar.rows.count == 4, "Keyboard collapse is available without a visible arrow")
    let tables = allViews(workspace).compactMap { $0 as? NSTableView }
    let actualSidebar = tables.first { $0.tableColumns.first?.identifier.rawValue == "branch" }!
    precondition(actualSidebar.frame.width <= actualSidebar.enclosingScrollView!.contentSize.width + 1,
      "Trailing branch and selection remain inside sidebar viewport")
    let log = tables.first { $0.tableColumns.contains { $0.identifier.rawValue == "subject" } }!
    precondition(log.numberOfRows == 4, "Selected repository has four commits with a merge")
    let graph = log.view(atColumn: 1, row: 0, makeIfNecessary: true) as! GitGraphCell
    precondition(
      graph.row?.segments.filter { $0.part == .outgoing }.count == 2,
      "Merge graph has two real parent edges")
    let fullWidth = log.enclosingScrollView!.frame.width
    log.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    try await idle()
    precondition(
      log.headerView == nil && log.tableColumns.count == 3,
      "History omits headers and author/date/hash columns")
    let files = allViews(workspace).compactMap { $0 as? NSTableView }.first {
      $0.tableColumns.contains { $0.title == "变更文件" }
    }!
    precondition(
      log.enclosingScrollView!.frame.width < fullWidth, "Details appear only after selection")
    precondition(files.headerView == nil, "Changed files omit redundant column headings")
    precondition(files.numberOfRows == 1, "Selected merge shows first-parent changed files")
    let handles = allViews(workspace).compactMap { $0 as? PaperResizeHandle }
    precondition(
      handles.count == 2 && handles.allSatisfy { $0.writingCursorRole == .columnResize },
      "Both pane dividers use custom resize cursors")
    let handle = handles[0]
    let width = handles[0].initialWidth!()
    handle.onChange?(width > 210 ? width - 24 : width + 24)
    workspace.layoutSubtreeIfNeeded()
    precondition(abs(handle.initialWidth!() - width) > 10, "Sidebar can be resized")
    handle.onChange?(width)
    workspace.layoutSubtreeIfNeeded()
    let longPath =
      "Sources/Features/Git/Presentation/ViewModels/GitRepositoryHistoryPresentationModel.swift"
    let pathList = files.dataSource as! GitFilesList
    let examples = try JSONDecoder().decode(
      [GitFileChange].self,
      from: JSONSerialization.data(withJSONObject: [
        ["status": "M", "path": "README.md"], ["status": "A", "path": longPath],
      ]))
    pathList.update(examples)
    workspace.layoutSubtreeIfNeeded()
    precondition(
      files.rect(ofRow: 1).height > files.rect(ofRow: 0).height,
      "Nested paths keep the file name primary and directory on a second line")
    precondition(
      files.frame.width <= files.enclosingScrollView!.contentSize.width + 1,
      "Path table has no automatic horizontal inset overflow")
    if CommandLine.arguments.count > 2 {
      window.layoutIfNeeded()
      let rep = workspace.bitmapImageRepForCachingDisplay(in: workspace.bounds)!
      workspace.cacheDisplay(in: workspace.bounds, to: rep)
      try rep.representation(using: .png, properties: [:])!.write(
        to: URL(fileURLWithPath: CommandLine.arguments[2]))
    }
    let close = allViews(workspace).compactMap { $0 as? PaperIconButton }.first {
      $0.toolTip == "收起详情"
    }!
    close.performClick(nil)
    workspace.layoutSubtreeIfNeeded()
    precondition(
      abs(log.enclosingScrollView!.frame.width - fullWidth) < 2,
      "Closing details returns space to history")
    let filterButton = allViews(workspace).compactMap { $0 as? PaperIconButton }.first {
      $0.toolTip == "筛选"
    }!
    filterButton.performClick(nil)
    workspace.layoutSubtreeIfNeeded()
    precondition(
      allViews(workspace).compactMap { $0 as? NSTextField }.contains {
        $0.placeholderString == "作者"
      }, "Secondary filters remain accessible on demand")
    filterButton.performClick(nil)
    let fields = allViews(workspace).compactMap { $0 as? NSTextField }
    let search = fields.first { $0.placeholderString == "搜索…" }!
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
