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
  let scroll = NSScrollView()
  let table = NSTableView()
  private var repositories: [GitRepository] = []
  private(set) var rows: [Row] = []
  private var expanded = Set<String>()
  private var selectedID = "all:root"
  private var rebuilding = false
  var query = "" { didSet { rebuild() } }
  var onSelect: ((GitRepository?, GitReference?) -> Void)?
  override init() {
    super.init()
    table.style = .plain
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
    table.setAccessibilityLabel("Git 仓库与分支树")
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
  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    rows[row].depth == 0 && rows[row].repository != nil ? 43 : 29
  }
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    guard rows.indices.contains(row) else { return nil }
    let value = rows[row]
    let id = NSUserInterfaceItemIdentifier("git-side")
    let view = (table.makeView(withIdentifier: id, owner: self) as? GitSideCell) ?? GitSideCell()
    view.identifier = id
    let expandable = value.repository != nil && value.reference == nil
    let open =
      value.group == nil ? expanded.contains(value.id) : !expanded.contains("collapsed:" + value.id)
    view.configure(value, expandable: expandable, expanded: open) { [weak self] in
      guard let self else { return }
      if value.group == nil {
        if !expanded.insert(value.id).inserted { expanded.remove(value.id) }
      } else {
        let key = "collapsed:" + value.id
        if !expanded.insert(key).inserted { expanded.remove(key) }
      }
      rebuild()
    }
    return view
  }
  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    PaperTableRow()
  }
  func tableViewSelectionDidChange(_ notification: Notification) {
    guard !rebuilding, rows.indices.contains(table.selectedRow) else { return }
    let row = rows[table.selectedRow]
    guard row.group == nil else { return }
    selectedID = row.id
    onSelect?(row.repository, row.reference)
  }
}
@MainActor private final class GitSideCell: NSTableCellView {
  private let toggle = PaperIconButton(
    symbol: "chevron.right", label: "展开", target: nil, action: #selector(disclose))
  private let title = Theme.label("", size: 12)
  private let detail = Theme.label("", size: 10, muted: true)
  private let dot = Theme.label("●", size: 10)
  private var action: (() -> Void)?
  private var inset: NSLayoutConstraint!
  override init(frame: NSRect) {
    super.init(frame: frame)
    toggle.target = self
    toggle.action = #selector(disclose)
    for view in [toggle, dot, title, detail] {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
    }
    inset = toggle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8)
    NSLayoutConstraint.activate([
      inset, toggle.widthAnchor.constraint(equalToConstant: 18),
      toggle.heightAnchor.constraint(equalToConstant: 24),
      toggle.centerYAnchor.constraint(equalTo: centerYAnchor),
      dot.leadingAnchor.constraint(equalTo: toggle.trailingAnchor, constant: 2),
      dot.widthAnchor.constraint(equalToConstant: 12),
      dot.centerYAnchor.constraint(equalTo: title.centerYAnchor),
      title.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 4),
      title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
      title.topAnchor.constraint(equalTo: topAnchor, constant: 4),
      detail.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 0),
      detail.leadingAnchor.constraint(equalTo: title.leadingAnchor),
      detail.trailingAnchor.constraint(equalTo: title.trailingAnchor),
    ])
    detail.font = Theme.font(10)
    textField = title
  }
  required init?(coder: NSCoder) { nil }
  func configure(
    _ row: GitSidebar.Row, expandable: Bool, expanded: Bool, action: @escaping () -> Void
  ) {
    self.action = action
    inset.constant = CGFloat(5 + row.depth * 14)
    toggle.isHidden = !expandable
    toggle.symbol = expanded ? "chevron.down" : "chevron.right"
    toggle.setAccessibilityLabel((expanded ? "收起 " : "展开 ") + row.title)
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
    detail.isHidden = row.depth != 0 || row.repository == nil
    detail.stringValue =
      row.repository.map {
        $0.error == nil ? $0.branchLabel + ($0.limited ? " · 分支已截断" : "") : "读取失败"
      } ?? ""
    toolTip = row.repository.map {
      $0.id + "\n" + ($0.error ?? (row.reference?.fullName ?? $0.branchLabel))
    }
    title.setAccessibilityLabel(row.title)
  }
  @objc private func disclose() { action?() }
}
