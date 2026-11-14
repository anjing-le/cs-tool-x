import AppKit
import ToolCore

struct GitFileGlyph: Sendable {
  let mark: String
  let type: String
  let color: Int
  static func identify(_ path: String, binary: Bool?) -> Self {
    let name = (path as NSString).lastPathComponent.lowercased()
    let ext = (name as NSString).pathExtension
    if name.hasPrefix(".env") { return Self(mark: "=", type: "环境配置", color: 6) }
    if [".gitignore", ".gitattributes", ".gitmodules"].contains(name) { return Self(mark: "·", type: "Git 配置", color: 3) }
    if name == "dockerfile" { return Self(mark: "▤", type: "容器配置", color: 0) }
    switch ext {
    case "js", "jsx", "mjs", "cjs": return Self(mark: "JS", type: "JavaScript", color: 6)
    case "ts", "tsx": return Self(mark: "TS", type: "TypeScript", color: 0)
    case "swift": return Self(mark: "S", type: "Swift", color: 3)
    case "rs": return Self(mark: "R", type: "Rust", color: 3)
    case "py": return Self(mark: "Py", type: "Python", color: 0)
    case "java", "kt", "go", "c", "h", "cpp", "cs", "rb", "php": return Self(mark: "‹›", type: ext.uppercased() + " 源码", color: 0)
    case "json", "jsonc": return Self(mark: "{}", type: "JSON", color: 6)
    case "yaml", "yml", "toml", "ini", "conf", "xml", "plist": return Self(mark: "=", type: "配置", color: 7)
    case "md", "mdx", "txt", "rst": return Self(mark: "≡", type: "文档", color: 0)
    case "html", "vue", "svelte": return Self(mark: "‹›", type: "页面", color: 3)
    case "css", "scss", "less": return Self(mark: "#", type: "样式", color: 1)
    case "sh", "zsh", "bash", "fish": return Self(mark: ">_", type: "Shell", color: 2)
    case "sql": return Self(mark: "▤", type: "SQL", color: 0)
    case "png", "jpg", "jpeg", "gif", "webp", "svg", "icns": return Self(mark: "◇", type: "图像", color: 2)
    case "zip", "gz", "tar", "7z": return Self(mark: "▥", type: "归档", color: 3)
    default: return Self(mark: binary == true ? "▥" : "·", type: binary == true ? "二进制" : "文件", color: 7)
    }
  }
}
struct GitFileSummary: Sendable {
  let files: Int, known: Int, binary: Int, added: Int, removed: Int
  let overflow: Bool
  init(_ changes: [GitFileChange]) {
    files = changes.count
    known = changes.filter { $0.binary != nil }.count
    binary = changes.filter { $0.binary == true }.count
    var a = 0, d = 0, exceeded = false
    for change in changes {
      let add = a.addingReportingOverflow(change.additions ?? 0)
      let del = d.addingReportingOverflow(change.deletions ?? 0)
      exceeded = exceeded || add.overflow || del.overflow
      a = add.overflow ? Int.max : add.partialValue
      d = del.overflow ? Int.max : del.partialValue
    }
    added = a; removed = d; overflow = exceeded
  }
}
@MainActor final class GitFileSummaryView: NSView {
  var summary = GitFileSummary([]) { didSet { needsDisplay = true; updateAccessibility() } }
  var pending = false { didSet { needsDisplay = true; updateAccessibility() } }
  var partial = false { didSet { needsDisplay = true; updateAccessibility() } }
  var error: String? { didSet { needsDisplay = true; updateAccessibility() } }
  private func updateAccessibility() {
    let description = "\(partial ? "已显示 " : "")\(summary.files) 个文件，新增 \(summary.added) 行，删除 \(summary.removed) 行，\(summary.binary) 个二进制文件"
    toolTip = pending ? "正在按第一父提交比较读取行数" : error ?? description + (partial ? "；统计仅包含已显示文件" : "；合并提交与第一父提交比较")
    setAccessibilityLabel(toolTip)
  }
  override func draw(_ dirtyRect: NSRect) {
    let p = NSMutableParagraphStyle(); p.lineBreakMode = .byTruncatingTail
    let title = pending && summary.files == 0 ? "读取文件…" : error != nil && summary.files == 0 ? "文件读取失败" : partial ? "已显示 \(summary.files)" : "\(summary.files) 文件"
    (title as NSString).draw(in: NSRect(x: 0, y: 5, width: bounds.width * 0.34, height: 20),
      withAttributes: [.font: Theme.font(12, weight: .medium), .foregroundColor: Theme.ink, .paragraphStyle: p])
    var text: [(String, NSColor)] = []
    if pending { text = [("行数读取中…", Theme.muted)] }
    else if error != nil || summary.known != summary.files { text = [("统计不可用", Theme.muted)] }
    else {
      if summary.files > summary.binary {
        text += [("+\(summary.added)", Theme.sage), ("−\(summary.removed)", GitPalette.lines[4])]
      }
      if summary.binary > 0 { text.append(("\(summary.binary) 二进制", Theme.muted)) }
      if summary.overflow { text = [("统计值过大", Theme.muted)] }
    }
    let available = bounds.width * 0.65
    let slot = available / CGFloat(max(1, text.count))
    for (i, item) in text.enumerated() {
      (item.0 as NSString).draw(in: NSRect(x: bounds.width * 0.35 + CGFloat(i) * slot, y: 5, width: slot - 4, height: 20),
        withAttributes: [.font: Theme.font(11), .foregroundColor: item.1, .paragraphStyle: p])
    }
  }
}

@MainActor final class GitFilesList: NSObject, NSTableViewDataSource, NSTableViewDelegate {
  struct FileRow: Sendable {
    let change: GitFileChange
    let name: String, directory: String
    let glyph: GitFileGlyph
  }
  struct Presentation: Sendable { let rows: [FileRow]; let summary: GitFileSummary }
  let table = NSTableView()
  let scroll = GitLogScroll()
  private var rows: [FileRow] = []
  private var measuredWidth: CGFloat = 0
  override init() {
    super.init()
    table.style = .plain; table.delegate = self; table.dataSource = self
    table.headerView = nil; table.focusRingType = .none; table.backgroundColor = CrayonInk.paper
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
    column.title = "变更文件"; column.width = 290; column.minWidth = 100
    table.addTableColumn(column)
    table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle; table.intercellSpacing = .zero
    scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
    scroll.drawsBackground = false; scroll.scrollerStyle = .overlay
    scroll.onWidth = { [weak self] width in
      guard let self, width > 0, abs(measuredWidth - width) > 0.5 else { return }
      measuredWidth = width
      table.setFrameSize(NSSize(width: width, height: table.frame.height))
      table.tableColumns[0].width = width
    }
    table.setAccessibilityLabel("提交变更文件及增删行数")
  }
  nonisolated static func prepare(_ changes: [GitFileChange]) -> Presentation {
    let rows = changes.map { change in
      let path = String(change.path.prefix(1000)).replacingOccurrences(of: "\n", with: "↵").replacingOccurrences(of: "\t", with: "⇥")
      return FileRow(change: change, name: (path as NSString).lastPathComponent,
        directory: (path as NSString).deletingLastPathComponent,
        glyph: GitFileGlyph.identify(change.path, binary: change.binary))
    }
    return Presentation(rows: rows, summary: GitFileSummary(changes))
  }
  func apply(_ presentation: Presentation) { rows = presentation.rows; table.reloadData() }
  func update(_ changes: [GitFileChange]) { apply(Self.prepare(changes)) }
  func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { rows[row].directory.isEmpty ? 34 : 48 }
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    guard rows.indices.contains(row) else { return nil }
    let id = NSUserInterfaceItemIdentifier("git-path")
    let view = (table.makeView(withIdentifier: id, owner: self) as? GitPathCell) ?? GitPathCell()
    view.identifier = id; view.row = rows[row]
    let change = rows[row].change
    let state = change.status == "A" ? "新增" : change.status == "D" ? "删除" : change.status == "T" ? "类型改变" : "修改"
    let lines = change.binary == true ? "二进制，不适用行数" : change.additions.map { "+\($0) −\(change.deletions ?? 0)" } ?? "行数未读取"
    view.toolTip = change.path + "\n" + rows[row].glyph.type + "（按文件名识别） · " + state + " · " + lines
    view.setAccessibilityLabel(view.toolTip); view.needsDisplay = true
    return view
  }
  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { PaperTableRow() }
}
@MainActor private final class GitPathCell: NSView {
  var row: GitFilesList.FileRow?
  override func draw(_ dirtyRect: NSRect) {
    guard let row else { return }
    NSGraphicsContext.saveGraphicsState(); bounds.clip()
    defer { NSGraphicsContext.restoreGraphicsState() }
    let change = row.change
    let tint = GitPalette.lines[row.glyph.color]
    let iconY = (bounds.height - 21) / 2
    let outline = NSBezierPath()
    outline.move(to: NSPoint(x: 4, y: iconY)); outline.line(to: NSPoint(x: 4, y: iconY + 21))
    outline.line(to: NSPoint(x: 16, y: iconY + 21)); outline.line(to: NSPoint(x: 23, y: iconY + 14))
    outline.line(to: NSPoint(x: 23, y: iconY)); outline.close()
    CrayonInk.stroke(outline, color: tint.withAlphaComponent(0.6), width: 0.9)
    let centered = NSMutableParagraphStyle(); centered.alignment = .center
    (row.glyph.mark as NSString).draw(in: NSRect(x: 5, y: iconY + 3, width: 17, height: 14),
      withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 8, weight: .medium), .foregroundColor: tint, .paragraphStyle: centered])
    let status = change.status == "A" ? "+" : change.status == "D" ? "−" : "·"
    let color = change.status == "A" ? Theme.sage : change.status == "D" ? GitPalette.lines[4] : GitPalette.lines[0]
    (status as NSString).draw(in: NSRect(x: 20, y: iconY - 4, width: 10, height: 13),
      withAttributes: [.font: Theme.font(10, weight: .medium), .foregroundColor: color])
    let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingMiddle
    let nameY = row.directory.isEmpty ? (bounds.height - 16) / 2 : bounds.height - 20
    let statsWidth: CGFloat = change.binary == true ? 47 : 80
    let width = max(0, bounds.width - 37 - statsWidth)
    (row.name as NSString).draw(in: NSRect(x: 34, y: nameY, width: width, height: 17),
      withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: Theme.ink, .paragraphStyle: style])
    if !row.directory.isEmpty {
      (row.directory as NSString).draw(in: NSRect(x: 34, y: 5, width: bounds.width - 39, height: 15),
        withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular), .foregroundColor: Theme.muted, .paragraphStyle: style])
    }
    let statsX = bounds.width - statsWidth
    if change.binary == true || change.additions == nil {
      ((change.binary == true ? "二进制" : "…") as NSString).draw(in: NSRect(x: statsX, y: nameY, width: statsWidth - 4, height: 17),
        withAttributes: [.font: Theme.font(10), .foregroundColor: Theme.muted, .paragraphStyle: style])
    } else {
      for (text, x, color) in [("+\(change.additions!)", statsX, Theme.sage), ("−\(change.deletions ?? 0)", statsX + 39, GitPalette.lines[4])] {
        (text as NSString).draw(in: NSRect(x: x, y: nameY, width: 37, height: 17),
          withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 9, weight: .regular), .foregroundColor: color, .paragraphStyle: style])
      }
    }
  }
}
