import AppKit
import ToolCore

/// Variable-height, bounded path list. Full paths remain available even when a display row is capped.
@MainActor final class GitFilesList: NSObject, NSTableViewDataSource, NSTableViewDelegate {
  let table = NSTableView()
  let scroll = GitLogScroll()
  private var changes: [GitFileChange] = []
  private var measuredWidth: CGFloat = 0
  override init() {
    super.init()
    table.style = .plain
    table.delegate = self
    table.dataSource = self
    table.headerView = nil
    table.focusRingType = .none
    table.backgroundColor = CrayonInk.paper
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
    column.title = "变更文件"
    column.width = 290
    column.minWidth = 100
    table.addTableColumn(column)
    table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    table.intercellSpacing = .zero
    scroll.documentView = table
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.drawsBackground = false
    scroll.scrollerStyle = .overlay
    scroll.onWidth = { [weak self] width in
      guard let self, width > 0, abs(measuredWidth - width) > 0.5 else { return }
      measuredWidth = width
      table.setFrameSize(NSSize(width: width, height: table.frame.height))
      table.tableColumns[0].width = width

    }
    table.setAccessibilityLabel("变更文件完整路径")
  }
  struct Presentation: Sendable { let changes: [GitFileChange] }
  nonisolated static func prepare(_ changes: [GitFileChange]) -> Presentation {
    Presentation(changes: changes)
  }
  func apply(_ presentation: Presentation) {
    changes = presentation.changes
    table.reloadData()
  }
  func update(_ changes: [GitFileChange]) { apply(Self.prepare(changes)) }
  func numberOfRows(in tableView: NSTableView) -> Int { changes.count }
  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    let directory = (changes[row].path as NSString).deletingLastPathComponent
    return directory.isEmpty ? 30 : 46
  }
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    guard changes.indices.contains(row) else { return nil }
    let id = NSUserInterfaceItemIdentifier("git-path")
    let view = (table.makeView(withIdentifier: id, owner: self) as? GitPathCell) ?? GitPathCell()
    view.identifier = id
    view.change = changes[row]
    view.toolTip = changes[row].path
    view.setAccessibilityLabel(changes[row].status + " " + changes[row].path)
    view.needsDisplay = true
    return view
  }
  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    PaperTableRow()
  }
}
@MainActor private final class GitPathCell: NSView {
  var change: GitFileChange?
  override func draw(_ dirtyRect: NSRect) {
    guard let change else { return }
    NSGraphicsContext.saveGraphicsState()
    bounds.clip()
    defer { NSGraphicsContext.restoreGraphicsState() }
    let color: NSColor =
      change.status == "A"
      ? Theme.sage : change.status == "D" ? GitPalette.lines[4] : GitPalette.lines[0]
    let marker = NSBezierPath()
    let y = bounds.midY
    marker.move(to: NSPoint(x: 6, y: y))
    marker.line(to: NSPoint(x: 13, y: y))
    if change.status == "A" {
      marker.move(to: NSPoint(x: 9.5, y: y - 3.5))
      marker.line(to: NSPoint(x: 9.5, y: y + 3.5))
    } else if change.status != "D" {
      marker.move(to: NSPoint(x: 6.5, y: y - 3))
      marker.line(to: NSPoint(x: 12.5, y: y + 3))
    }
    CrayonInk.stroke(marker, color: color, width: 1)
    let raw = String(change.path.prefix(1000)).replacingOccurrences(of: "\n", with: "↵")
    let name = (raw as NSString).lastPathComponent
    let directory = (raw as NSString).deletingLastPathComponent
    let width = max(0, bounds.width - 29)
    let nominal = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    let measured = (name as NSString).size(withAttributes: [.font: nominal]).width
    let size = max(10, min(11, width / max(1, measured) * 11))
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = .byTruncatingMiddle
    let nameY = directory.isEmpty ? (bounds.height - 15) / 2 : bounds.height - 20
    (name as NSString).draw(
      in: NSRect(x: 23, y: nameY, width: width, height: 16),
      withAttributes: [
        .font: NSFont.monospacedSystemFont(ofSize: size, weight: .regular),
        .foregroundColor: color.blended(withFraction: 0.45, of: Theme.ink) ?? Theme.ink,
        .paragraphStyle: style,
      ])
    if !directory.isEmpty {
      (directory as NSString).draw(
        in: NSRect(x: 23, y: 5, width: width, height: 15),
        withAttributes: [
          .font: NSFont.monospacedSystemFont(ofSize: 9.5, weight: .regular),
          .foregroundColor: Theme.muted, .paragraphStyle: style,
        ])
    }
  }
}
