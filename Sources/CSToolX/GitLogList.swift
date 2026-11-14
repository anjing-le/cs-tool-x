import AppKit
import ToolCore

enum GitPalette {
  static let lines: [NSColor] = [
    NSColor(srgbRed: 0.29, green: 0.53, blue: 0.86, alpha: 1),
    NSColor(srgbRed: 0.74, green: 0.41, blue: 0.79, alpha: 1),
    NSColor(srgbRed: 0.26, green: 0.65, blue: 0.53, alpha: 1),
    NSColor(srgbRed: 0.88, green: 0.52, blue: 0.25, alpha: 1),
    NSColor(srgbRed: 0.76, green: 0.42, blue: 0.40, alpha: 1),
    NSColor(srgbRed: 0.39, green: 0.64, blue: 0.78, alpha: 1),
    NSColor(srgbRed: 0.64, green: 0.62, blue: 0.28, alpha: 1),
    NSColor(srgbRed: 0.51, green: 0.46, blue: 0.77, alpha: 1),
  ]
  static let head = NSColor(srgbRed: 0.95, green: 0.80, blue: 0.36, alpha: 1)
  static let local = NSColor(srgbRed: 0.55, green: 0.76, blue: 0.44, alpha: 1)
  static let remote = NSColor(srgbRed: 0.70, green: 0.57, blue: 0.84, alpha: 1)
  static let tag = NSColor(srgbRed: 0.85, green: 0.75, blue: 0.56, alpha: 1)
  static func reference(_ reference: GitReference) -> NSColor {
    reference.current
      ? head : reference.kind == .local ? local : reference.kind == .remote ? remote : tag
  }
}

@MainActor final class GitLogList: NSObject, NSTableViewDataSource, NSTableViewDelegate {
  let scroll = GitLogScroll()
  let table = NSTableView()
  private(set) var commits: [GitCommit] = []
  private var graph: [GitGraphRow] = []
  private var references: [String: [GitReference]] = [:]
  private var repositories: [String: GitRepository] = [:]
  private var rebuilding = false
  var graphLimited: Bool { graph.contains(where: \.overflow) }
  var onSelect: ((GitCommit) -> Void)?
  override init() {
    super.init()
    table.style = .plain
    table.delegate = self
    table.dataSource = self
    scroll.onWidth = { [weak self] width in self?.fitColumns(width) }
    table.rowHeight = 31
    table.intercellSpacing = .zero
    table.backgroundColor = CrayonInk.paper
    table.focusRingType = .none
    table.columnAutoresizingStyle = .noColumnAutoresizing
    table.headerView = nil
    for (name, title, width) in [
      ("root", "", 88.0), ("graph", "", 90.0), ("subject", "", 470.0),
    ] {
      let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(name))
      column.title = title
      column.width = width
      column.minWidth = name == "graph" ? 45 : 70
      table.addTableColumn(column)
    }
    scroll.documentView = table
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = true
    scroll.autohidesScrollers = true
    scroll.scrollerStyle = .overlay
    scroll.drawsBackground = false
    table.setAccessibilityLabel("Git 彩色提交历史")
  }
  struct Presentation: Sendable {
    let commits: [GitCommit]
    let graph: [GitGraphRow]
    let repositories: [String: GitRepository]
    let references: [String: [GitReference]]
    let columns: Int
  }
  nonisolated static func prepare(_ commits: [GitCommit], repositories: [GitRepository])
    -> Presentation
  {
    let graph = GitGraph.rows(commits)
    var references: [String: [GitReference]] = [:]
    for repository in repositories {
      for reference in repository.references {
        let key = repository.id + ":" + reference.oid
        if (references[key]?.count ?? 0) < 6 {
          references[key, default: []].append(reference)
        } else if reference.current {
          references[key]?[0] = reference
        }
      }
    }
    let columns =
      graph.map { max($0.column, $0.segments.map { max($0.from, $0.to) }.max() ?? 0) }.max() ?? 0
    return Presentation(
      commits: commits, graph: graph,
      repositories: Dictionary(uniqueKeysWithValues: repositories.map { ($0.id, $0) }),
      references: references, columns: columns)
  }
  func update(_ commits: [GitCommit], repositories: [GitRepository]) {
    apply(Self.prepare(commits, repositories: repositories))
  }
  func apply(_ presentation: Presentation) {
    let selected =
      table.selectedRow >= 0 && table.selectedRow < self.commits.count
      ? self.commits[table.selectedRow].id : nil
    commits = presentation.commits
    graph = presentation.graph
    repositories = presentation.repositories
    references = presentation.references
    if let graphColumn = table.tableColumns.first(where: { $0.identifier.rawValue == "graph" }) {
      graphColumn.width = min(220, CGFloat(presentation.columns + 1) * 12 + 18)
    }
    table.tableColumns.first { $0.identifier.rawValue == "root" }?.isHidden =
      Set(commits.map(\.repository)).count <= 1
    fitColumns(scroll.contentView.bounds.width)
    rebuilding = true
    table.reloadData()
    if let selected, let row = commits.firstIndex(where: { $0.id == selected }) {
      table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    } else {
      table.deselectAll(nil)
    }
    rebuilding = false
  }
  private func fitColumns(_ width: CGFloat) {
    guard let subject = table.tableColumns.first(where: { $0.identifier.rawValue == "subject" }),
      width > 0
    else { return }
    let fixed = table.tableColumns.filter { $0 !== subject && !$0.isHidden }.reduce(CGFloat(0)) {
      $0 + $1.width
    }
    let desired = max(220, width - fixed)
    if abs(subject.width - desired) > 0.5 { subject.width = desired }
    let height: CGFloat = desired >= 650 ? 31 : 49
    if table.rowHeight != height { table.rowHeight = height }
  }
  func numberOfRows(in tableView: NSTableView) -> Int { commits.count }
  func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
    guard commits.indices.contains(row), let name = column?.identifier.rawValue else { return nil }
    let commit = commits[row]
    let id = NSUserInterfaceItemIdentifier("git-" + name)
    if name == "graph" {
      let view =
        (table.makeView(withIdentifier: id, owner: self) as? GitGraphCell) ?? GitGraphCell()
      view.identifier = id
      view.row = graph[row]
      view.needsDisplay = true
      view.toolTip =
        (graph[row].overflow ? "并行轨道超过 64 条，部分连线已省略。" : "") + "提交父关系；图列可横向扩展。未加载的父提交继续向下，未推断省略的历史。"
      return view
    }
    if name == "subject" {
      let view =
        (table.makeView(withIdentifier: id, owner: self) as? GitSubjectCell) ?? GitSubjectCell()
      view.identifier = id
      view.subject = commit.subject
      view.author = commit.author
      view.timestamp = Self.date.string(from: Date(timeIntervalSince1970: Double(commit.timestamp)))
      view.shortHash = String(commit.oid.prefix(8))
      view.setAccessibilityLabel(commit.subject + "，" + commit.author + "，" + view.timestamp + "，" + view.shortHash)
      view.references = references[commit.id] ?? []
      view.detachedHead =
        repositories[commit.repository].map { $0.head == commit.oid && $0.branch.isEmpty } ?? false
      view.toolTip = String(
        (commit.subject + "\n" + commit.author + " · "
          + Self.date.string(from: Date(timeIntervalSince1970: Double(commit.timestamp))) + "\n"
          + commit.oid + "\n" + view.references.map(\.name).joined(separator: ", ")).prefix(4000))
      view.needsDisplay = true
      return view
    }
    let view = (table.makeView(withIdentifier: id, owner: self) as? GitTextCell) ?? GitTextCell()
    view.identifier = id
    view.stripe = name == "root" ? GitPalette.lines[GitBrowser.colorIndex(commit.repository)] : nil
    switch name {
    case "root":
      view.text =
        repositories[commit.repository]?.location.name
        ?? URL(fileURLWithPath: commit.repository).lastPathComponent
    case "author": view.text = commit.author
    case "date":
      view.text = Self.date.string(from: Date(timeIntervalSince1970: Double(commit.timestamp)))
    default: view.text = String(commit.oid.prefix(8))
    }
    view.mono = name == "hash"
    view.toolTip =
      name == "root"
      ? commit.repository
      : name == "author" ? commit.author + " <" + commit.email + ">" : commit.oid
    view.needsDisplay = true
    return view
  }
  private static let date: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f
  }()
  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    PaperTableRow()
  }
  func tableViewSelectionDidChange(_ notification: Notification) {
    guard !rebuilding, commits.indices.contains(table.selectedRow) else { return }
    onSelect?(commits[table.selectedRow])
  }
}

@MainActor final class GitGraphCell: NSView {
  var row: GitGraphRow?
  override func draw(_ dirtyRect: NSRect) {
    guard let row else { return }
    NSGraphicsContext.saveGraphicsState()
    bounds.clip()
    defer { NSGraphicsContext.restoreGraphicsState() }
    func x(_ column: Int) -> CGFloat { 12 + CGFloat(column) * 12 }
    let mid = bounds.height / 2
    for segment in row.segments {
      let startY: CGFloat = segment.part == .outgoing ? mid : bounds.height
      let endY: CGFloat = segment.part == .incoming ? mid : 0
      let path = NSBezierPath()
      path.lineWidth = 1.7
      path.lineCapStyle = .round
      path.move(to: NSPoint(x: x(segment.from), y: startY))
      if segment.from == segment.to {
        path.line(to: NSPoint(x: x(segment.to), y: endY))
      } else {
        path.curve(
          to: NSPoint(x: x(segment.to), y: endY),
          controlPoint1: NSPoint(x: x(segment.from), y: (startY + endY) / 2),
          controlPoint2: NSPoint(x: x(segment.to), y: (startY + endY) / 2))
      }
      CrayonInk.stroke(
        path, color: GitPalette.lines[segment.color % GitPalette.lines.count], width: 1.7)
    }
    GitPalette.lines[row.color % GitPalette.lines.count].setFill()
    NSBezierPath(ovalIn: NSRect(x: x(row.column) - 3.3, y: mid - 3.3, width: 6.6, height: 6.6))
      .fill()
    if row.overflow {
      ("…" as NSString).draw(
        at: NSPoint(x: bounds.maxX - 12, y: mid - 7),
        withAttributes: [.foregroundColor: Theme.muted])
    }
  }
}
@MainActor final class GitTextCell: NSView {
  var text = ""
  var mono = false
  var stripe: NSColor?
  override func draw(_ dirtyRect: NSRect) {
    if let stripe {
      stripe.setFill()
      NSRect(x: 0, y: 0, width: 3, height: bounds.height).fill()
    }
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byTruncatingTail
    (String(text.prefix(300)) as NSString).draw(
      in: bounds.insetBy(dx: 8, dy: 7),
      withAttributes: [
        .font: mono
          ? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
          : Theme.font(12), .foregroundColor: Theme.ink, .paragraphStyle: paragraph,
      ])
  }
}
@MainActor final class GitSubjectCell: NSView {
  var subject = ""
  var author = "", timestamp = "", shortHash = ""
  var references: [GitReference] = []
  var detachedHead = false
  override func draw(_ dirtyRect: NSRect) {
    NSGraphicsContext.saveGraphicsState()
    bounds.clip()
    defer { NSGraphicsContext.restoreGraphicsState() }
    let font = Theme.font(11.5)
    var labels = references.sorted { a, b in
      a.current != b.current ? a.current : a.kind.rawValue < b.kind.rawValue
    }.prefix(5).map { (String($0.name.prefix(60)), GitPalette.reference($0)) }
    if detachedHead { labels.insert(("HEAD", GitPalette.head), at: 0) }
    let compact = bounds.width < 650
    let contentWidth = compact ? bounds.width : bounds.width - 310
    let subjectY: CGFloat = compact ? bounds.height - 25 : 7
    let labelY: CGFloat = compact ? bounds.height - 26 : 5
    var left: CGFloat = 5
    for (text, color) in labels {
      let width = min(140, (text as NSString).size(withAttributes: [.font: font]).width + 14)
      if left + width > contentWidth * 0.6 { break }
      let rect = NSRect(x: left, y: labelY, width: width, height: 21)
      CrayonInk.swatch(rect, color: color)
      let style = NSMutableParagraphStyle()
      style.lineBreakMode = .byTruncatingTail
      (text as NSString).draw(
        in: rect.insetBy(dx: 6, dy: 2),
        withAttributes: [.font: font, .foregroundColor: Theme.ink, .paragraphStyle: style])
      left += width + 4
    }
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byTruncatingTail
    (String(subject.prefix(1000)) as NSString).draw(
      in: NSRect(
        x: left + 4, y: subjectY, width: max(0, contentWidth - left - 9), height: 22),
      withAttributes: [
        .font: Theme.font(14), .foregroundColor: Theme.ink,
        .paragraphStyle: paragraph,
      ])
    let metadataY: CGFloat = compact ? 3 : 7
    let metadataX: CGFloat = compact ? 9 : contentWidth + 6
    let available = max(0, bounds.width - metadataX - 8)
    let dateWidth: CGFloat = min(116, available * 0.48)
    let hashWidth: CGFloat = 62
    let authorWidth = max(0, available - dateWidth - hashWidth - 12)
    for (text, x, width, mono) in [
      (author, metadataX, authorWidth, false),
      (timestamp, metadataX + authorWidth + 6, dateWidth, false),
      (shortHash, bounds.width - hashWidth - 8, hashWidth, true),
    ] {
      (String(text.prefix(200)) as NSString).draw(
        in: NSRect(x: x, y: metadataY, width: width, height: 19),
        withAttributes: [.font: mono ? NSFont.monospacedSystemFont(ofSize: 10, weight: .regular) : Theme.font(10.5),
          .foregroundColor: Theme.muted, .paragraphStyle: paragraph])
    }
  }
}

@MainActor final class GitLogScroll: NSScrollView {
  var onWidth: ((CGFloat) -> Void)?
  override func tile() {
    super.tile()
    onWidth?(contentView.bounds.width)
  }
}
