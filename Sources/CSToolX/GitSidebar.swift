import AppKit
import ToolCore

@MainActor final class GitSidebar: NSObject, NSTableViewDataSource, NSTableViewDelegate {
  struct Row {
    let repository: GitRepository?
    let reference: GitReference?
    let title: String
    let depth: Int
    let group: String?
    var id: String { (repository?.id ?? "all") + ":" + (reference?.id ?? group ?? "root") }
  }
  let scroll = GitLogScroll()
  let table = GitSidebarTable()
  private var repositories: [GitRepository] = []
  private(set) var rows: [Row] = []
  private var expanded = Set<String>()
  private var selectedID = "all:root"
  private var measuredWidth: CGFloat = 0
  private var rebuilding = false
  var query = "" { didSet { rebuild() } }
  var onSelect: ((GitRepository?, GitReference?) -> Void)?
  override init() {
    super.init()
    table.style = .plain
    table.target = self
    table.doubleAction = #selector(activateSelection)
    table.onDisclosure = { [weak self] open in self?.discloseSelection(open) }
    table.delegate = self
    table.dataSource = self
    table.headerView = nil
    table.backgroundColor = CrayonInk.sidebar
    table.focusRingType = .none
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("branch"))
    column.width = 290
    table.addTableColumn(column)
    table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    table.intercellSpacing = .zero
    scroll.documentView = table
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.scrollerStyle = .overlay
    scroll.drawsBackground = false
    scroll.onWidth = { [weak self] width in
      guard let self, width > 0, abs(measuredWidth - width) > 0.5 else { return }
      measuredWidth = width
      table.setFrameSize(NSSize(width: width, height: table.frame.height))
      table.tableColumns[0].width = width
    }
    table.setAccessibilityLabel("Git 仓库与分支树")
    table.setAccessibilityHelp("双击或回车展开、收起仓库；左右方向键展开、收起，单击选择历史。")
  }
  func update(_ repositories: [GitRepository]) {
    self.repositories = repositories
    rebuild()
  }
  func select(repository: String?, reference: String = "") {
    selectedID = (repository ?? "all") + ":" + (reference.isEmpty ? "root" : reference)
    rebuild()
  }
  func expand(_ repository: String) {
    expanded.insert(repository + ":root")
    rebuild()
  }
  private func rebuild() {
    rows = [Row(repository: nil, reference: nil, title: "所有仓库", depth: 0, group: nil)]
    let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
    for repo in repositories {
      let rootMatch =
        search.isEmpty
        || (repo.location.name + " " + repo.id + " " + repo.branch)
          .localizedCaseInsensitiveContains(search)
      if search.isEmpty && !expanded.contains(repo.id + ":root") {
        rows.append(
          Row(repository: repo, reference: nil, title: repo.location.name, depth: 0, group: nil))
        continue
      }
      let matching = repo.references.filter {
        rootMatch || $0.name.localizedCaseInsensitiveContains(search)
      }
      guard rootMatch || !matching.isEmpty else { continue }
      let root = Row(
        repository: repo, reference: nil, title: repo.location.name, depth: 0, group: nil)
      rows.append(root)
      guard expanded.contains(root.id) || !search.isEmpty else { continue }
      rows += matching.sorted { a, b in
        if a.current != b.current { return a.current }
        if a.kind != b.kind { return a.kind.rawValue < b.kind.rawValue }
        return a.name.localizedStandardCompare(b.name) == .orderedAscending
      }.map { Row(repository: repo, reference: $0, title: $0.name, depth: 1, group: nil) }

    }
    rebuilding = true
    table.reloadData()
    if let index = rows.firstIndex(where: { $0.id == selectedID }) {
      table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    } else {
      table.deselectAll(nil)
    }
    rebuilding = false
  }
  func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
  @objc func activateSelection() { discloseSelection(nil) }
  func discloseSelection(_ open: Bool?) {
    guard rows.indices.contains(table.selectedRow) else { return }
    let row = rows[table.selectedRow]
    guard row.repository != nil, row.reference == nil else { return }
    if open ?? !expanded.contains(row.id) { expanded.insert(row.id) }
    else { expanded.remove(row.id) }
    rebuild()
  }
  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { 30 }
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    guard rows.indices.contains(row) else { return nil }
    let value = rows[row]
    let id = NSUserInterfaceItemIdentifier("git-side")
    let view = (table.makeView(withIdentifier: id, owner: self) as? GitSideCell) ?? GitSideCell()
    view.identifier = id
    view.configure(value, selected: value.id == selectedID)
    return view
  }
  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    PaperTableRow()
  }
  func tableViewSelectionDidChange(_ notification: Notification) {
    guard !rebuilding, rows.indices.contains(table.selectedRow) else { return }
    let row = rows[table.selectedRow]
    guard row.group == nil else { return }
    let oldID = selectedID
    selectedID = row.id
    let changed = IndexSet(rows.indices.filter { rows[$0].id == oldID || rows[$0].id == selectedID })
    table.reloadData(forRowIndexes: changed, columnIndexes: IndexSet(integer: 0))
    onSelect?(row.repository, row.reference)
  }
}
@MainActor final class GitSidebarTable: NSTableView {
  var onDisclosure: ((Bool?) -> Void)?
  override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 36, 76: onDisclosure?(nil)
    case 124: onDisclosure?(true)
    case 123: onDisclosure?(false)
    default: super.keyDown(with: event)
    }
  }
}
@MainActor private final class GitSideCell: NSTableCellView {
  private let title = Theme.label("", size: 12)
  private let detail = Theme.label("", size: 10, muted: true)
  private let dot = Theme.label("●", size: 10)
  private let selection = Theme.label("✓", size: 11)
  private var inset: NSLayoutConstraint!
  override init(frame: NSRect) {
    super.init(frame: frame)
    for view in [dot, title, detail, selection] {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
    }
    inset = dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10)
    title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    detail.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    detail.setContentHuggingPriority(.required, for: .horizontal)
    selection.textColor = Theme.sage
    NSLayoutConstraint.activate([
      inset, dot.widthAnchor.constraint(equalToConstant: 12),
      dot.centerYAnchor.constraint(equalTo: centerYAnchor),
      title.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 5),
      title.centerYAnchor.constraint(equalTo: centerYAnchor),
      title.trailingAnchor.constraint(equalTo: detail.leadingAnchor, constant: -8),
      detail.centerYAnchor.constraint(equalTo: centerYAnchor),
      detail.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.34),
      detail.trailingAnchor.constraint(equalTo: selection.leadingAnchor, constant: -5),
      selection.widthAnchor.constraint(equalToConstant: 12),
      selection.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
      selection.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    detail.font = Theme.font(10)
    textField = title
  }
  required init?(coder: NSCoder) { nil }
  func configure(_ row: GitSidebar.Row, selected: Bool) {
    inset.constant = CGFloat(10 + row.depth * 18)
    title.stringValue = String(row.title.prefix(200))
    title.font = Theme.font(13, weight: row.reference?.current == true ? .medium : .regular)
    dot.stringValue = row.reference?.kind == .tag ? "◇" : "●"
    if let reference = row.reference {
      dot.textColor = GitPalette.reference(reference)
    } else if let repo = row.repository {
      dot.textColor = GitPalette.lines[GitBrowser.colorIndex(repo.id)]
    } else {
      dot.textColor = Theme.sage
    }
    selection.isHidden = !selected
    // Only the selected repository needs a current-branch cue. Errors stay visible.
    detail.stringValue = row.reference == nil ? row.repository.map {
      if $0.error != nil { return "读取失败" }
      if $0.limited { return selected ? $0.branchLabel + " · …" : "…" }
      return selected ? $0.branchLabel : ""
    } ?? "" : ""
    toolTip = row.repository.map {
      $0.id + "\n" + ($0.error ?? (row.reference?.fullName ?? $0.branchLabel))
        + ($0.limited ? "\n部分分支超出读取上限" : "")
    }
    title.setAccessibilityLabel(row.title)
    setAccessibilityLabel(row.title + (detail.stringValue.isEmpty ? "" : "，" + detail.stringValue))
    setAccessibilityValue(selected ? "已选中" : "")
  }
}
