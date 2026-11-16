import AppKit
import ToolCore

@MainActor
final class DataTreeNode {
  enum Kind { case connection, database, schema, table, index, key, message, more }
  let id: String
  let kind: Kind
  var title: String
  var detail: String
  var profile: ConnectionProfile?
  let groupID: String
  var schema: String = ""
  var object: [JSONValue] = []
  var children: [DataTreeNode] = []
  var expandable: Bool
  var loaded = false
  var loading = false
  var openError: String?
  var cursor: String = "0"
  var parentID: String?
  init(
    id: String, kind: Kind, title: String, detail: String = "", groupID: String,
    profile: ConnectionProfile? = nil, expandable: Bool = false
  ) {
    self.id = id
    self.kind = kind
    self.title = title
    self.detail = detail
    self.groupID = groupID
    self.profile = profile
    self.expandable = expandable
  }
}

/// Virtualized arrowless rows; selection and explicit activation are separate.
@MainActor
final class DataNavigator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
  struct Visible {
    let node: DataTreeNode
    let depth: Int
  }
  private let table = NavigatorTable()
  let scroll = NavigatorScroll()
  private var measuredWidth: CGFloat = 0
  private(set) var roots: [DataTreeNode] = []
  private var visible: [Visible] = []
  private var expanded: Set<String> = []
  private var userCollapsed: Set<String> = []
  private var selectedID: String?
  private var source: [String: [ConnectionProfile]] = [:]
  private var rebuilding = false
  private var connectionFilter: String?
  var onSelect: ((DataTreeNode) -> Void)?
  var onExpand: ((DataTreeNode) -> Void)?
  var onActivate: ((DataTreeNode) -> Void)?
  override init() {
    super.init()
    table.style = .plain
    table.delegate = self
    table.dataSource = self
    table.headerView = nil
    table.backgroundColor = Theme.sidebar
    table.focusRingType = .none
    table.rowHeight = 32
    table.intercellSpacing = NSSize(width: 0, height: 1)
    table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    table.target = self
    table.doubleAction = #selector(activateSelection)
    table.setAccessibilityLabel("数据连接树")
    table.setAccessibilityHelp("单击选择，双击或回车展开、收起目录或打开对象；左右方向键展开、收起。")
    let column = NSTableColumn(identifier: .init("tree"))
    column.width = 310
    column.minWidth = 120
    table.addTableColumn(column)
    scroll.documentView = table
    scroll.hasVerticalScroller = true
    scroll.drawsBackground = false
    scroll.scrollerStyle = .overlay
    scroll.autohidesScrollers = true
    table.navigate = { [weak self] key in self?.navigate(key) }
    scroll.onWidth = { [weak self] width in
      guard let self, width > 0, abs(width - measuredWidth) > 0.5 else { return }
      measuredWidth = width
      table.setFrameSize(NSSize(width: width, height: table.frame.height))
      table.tableColumns[0].width = width
    }
  }
  func update(_ groups: [ConnectionGroup]) {
    let previous = Dictionary(uniqueKeysWithValues: roots.map { ($0.id, $0) })
    roots = groups.map { group in
      if let existing = previous[group.id], source[group.id] == group.profiles { return existing }
      let root = freshRoot(group)
      if let existing = previous[group.id], source[group.id] != nil {
        existing.title = root.title
        existing.detail = root.detail
        existing.profile = root.profile
        if group.identity.kind != .es {
          let known = Dictionary(
            uniqueKeysWithValues: existing.children.filter { $0.kind == .database }.compactMap {
              node in node.profile.map { ($0.database, node) }
            })
          var children: [DataTreeNode] = existing.loaded ? existing.children : []
          for scope in group.scopes {
            let profile = scope.representative
            let prior = known[scope.database]
            let child: DataTreeNode
            if let prior, prior.profile?.transportPolicy == profile.transportPolicy {
              child = prior
              child.profile = profile
            } else {
              child = databaseNode(profile: profile, groupID: group.id)
            }
            if let index = children.firstIndex(where: { $0.id == child.id }) {
              children[index] = child
            } else {
              children.append(child)
            }
          }
          existing.children = children
        }
        return existing
      }
      return root
    }
    source = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0.profiles) })
    if nodeCount > 5000 { roots = groups.map { freshRoot($0) } }
    var validIDs = Set<String>()
    func collect(_ nodes: [DataTreeNode]) {
      for node in nodes { validIDs.insert(node.id); collect(node.children) }
    }
    collect(roots)
    expanded.formIntersection(validIDs)
    userCollapsed.formIntersection(validIDs)
    rebuild()
  }
  private func freshRoot(_ group: ConnectionGroup) -> DataTreeNode {
    let account = group.identity.username.isEmpty ? "未指定账号" : group.identity.username
    let root = DataTreeNode(
      id: group.id, kind: .connection,
      title: (group.profiles.count == 1 || group.profiles[0].name == group.identity.kind.title)
        && !group.profiles[0].name.isEmpty
        ? group.profiles[0].name : "\(group.identity.kind.title) · \(account)",
      detail:
        "\(group.identity.address) · \(account) · \(group.identity.environment)\(group.hasPolicyVariants ? " · TLS 参数不同" : "")",
      groupID: group.id, profile: group.profiles.first, expandable: true)
    if group.identity.kind != .es {
      root.children = group.scopes.map { scope in
        let node = databaseNode(profile: scope.representative, groupID: group.id)
        node.detail = scope.profiles.map { "\($0.name) · \($0.transportPolicy)" }.joined(
          separator: "\n")
        return node
      }
    }
    return root
  }
  func databaseNode(profile: ConnectionProfile, groupID: String) -> DataTreeNode {
    let node = DataTreeNode(
      id: groupID + "/db/" + ConnectionIdentity.token(profile.database), kind: .database,
      title: profile.kind == .redis ? "DB \(profile.database)" : profile.database,
      detail: profile.name, groupID: groupID, profile: profile, expandable: true)
    node.parentID = groupID
    return node
  }
  func invalidateGroup(_ id: String) { source.removeValue(forKey: id) }
  var nodeCount: Int {
    func count(_ nodes: [DataTreeNode]) -> Int { nodes.reduce(0) { $0 + 1 + count($1.children) } }
    return count(roots)
  }
  func node(_ id: String) -> DataTreeNode? {
    func find(_ nodes: [DataTreeNode]) -> DataTreeNode? {
      for node in nodes {
        if node.id == id { return node }
        if let found = find(node.children) { return found }
      }
      return nil
    }
    return find(roots)
  }
  func root(_ id: String) -> DataTreeNode? { roots.first { $0.id == id } }
  func isCurrent(_ node: DataTreeNode) -> Bool {
    func contains(_ nodes: [DataTreeNode]) -> Bool {
      nodes.contains { $0 === node || contains($0.children) }
    }
    return contains(roots)
  }
  func expand(_ node: DataTreeNode, respectingUserCollapse: Bool = false) {
    guard !respectingUserCollapse || !userCollapsed.contains(node.id) else { return }
    userCollapsed.remove(node.id)
    expanded.insert(node.id)
    rebuild()
  }
  func changed(_ node: DataTreeNode) {
    guard isCurrent(node) else { return }
    rebuild()
  }
  func filterConnection(_ id: String?) {
    connectionFilter = id
    rebuild()
  }
  private func rebuild() {
    let selected =
      table.selectedRow >= 0 && table.selectedRow < visible.count
      ? visible[table.selectedRow].node.id : nil
    let origin = scroll.contentView.bounds.origin
    visible = []
    func add(_ nodes: [DataTreeNode], depth: Int) {
      for node in nodes {
        visible.append(Visible(node: node, depth: depth))
        if expanded.contains(node.id) { add(node.children, depth: depth + 1) }
      }
    }
    add(roots.filter { connectionFilter == nil || $0.id == connectionFilter }, depth: 0)
    rebuilding = true
    table.reloadData()
    if let selected, let index = visible.firstIndex(where: { $0.node.id == selected }) {
      selectedID = selected
      table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    } else {
      selectedID = nil
      table.deselectAll(nil)
    }
    scroll.contentView.scroll(to: origin)
    scroll.reflectScrolledClipView(scroll.contentView)
    rebuilding = false
  }
  private func toggle(_ node: DataTreeNode, opens: Bool = false) {
    guard node.expandable else {
      onActivate?(node)
      return
    }
    if expanded.remove(node.id) == nil {
      userCollapsed.remove(node.id)
      expanded.insert(node.id)
      rebuild()
      if opens { onActivate?(node) } else { onExpand?(node) }
    } else {
      userCollapsed.insert(node.id)
      rebuild()
    }
  }
  private func navigate(_ key: UInt16) {
    let row = table.selectedRow
    guard visible.indices.contains(row) else { return }
    let node = visible[row].node
    switch key {
    case 124:
      if node.expandable, !expanded.contains(node.id) { toggle(node) }
    case 123:
      if expanded.contains(node.id) {
        toggle(node)
      } else if let parent = visible[..<row].lastIndex(where: { $0.depth < visible[row].depth }) {
        table.selectRowIndexes(IndexSet(integer: parent), byExtendingSelection: false)
      }
    default:
      activateSelection()
    }
  }
  func numberOfRows(in tableView: NSTableView) -> Int { visible.count }
  func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
    visible[row].node.kind == .connection ? 49 : 31
  }
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    let item = visible[row]
    let node = item.node
    let id = NSUserInterfaceItemIdentifier("tree-cell")
    let cell =
      (table.makeView(withIdentifier: id, owner: self) as? NavigatorCell) ?? NavigatorCell()
    cell.identifier = id
    cell.configure(node, depth: item.depth, selected: table.selectedRow == row)
    return cell
  }
  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    PaperTableRow()
  }
  func tableViewSelectionDidChange(_ notification: Notification) {
    guard !rebuilding else { return }
    let node = visible.indices.contains(table.selectedRow) ? visible[table.selectedRow].node : nil
    let oldID = selectedID
    selectedID = node?.id
    let changed = IndexSet(visible.indices.filter { visible[$0].node.id == oldID || visible[$0].node.id == selectedID })
    table.reloadData(forRowIndexes: changed, columnIndexes: IndexSet(integer: 0))
    if let node { onSelect?(node) }
  }
  @objc func activateSelection() {
    guard visible.indices.contains(table.selectedRow) else { return }
    toggle(visible[table.selectedRow].node, opens: true)
  }
}
@MainActor
private final class NavigatorTable: NSTableView {
  var navigate: ((UInt16) -> Void)?
  override func keyDown(with event: NSEvent) {
    if [UInt16(123), 124, 36, 76].contains(event.keyCode) {
      navigate?(event.keyCode)
    } else {
      super.keyDown(with: event)
    }
  }
}
@MainActor
private final class NavigatorCell: NSTableCellView {
  private let dot = Theme.label("●", size: 8)
  private let heading = Theme.label("", size: 12)
  private let detail = Theme.label("", size: 9, muted: true)
  private let selection = Theme.label("✓", size: 11)
  private var inset: NSLayoutConstraint!
  private var center: NSLayoutConstraint!
  override init(frame: NSRect) {
    super.init(frame: frame)
    dot.textColor = Theme.sage
    selection.textColor = Theme.sage
    heading.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    for view in [dot, heading, detail, selection] {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
    }
    inset = dot.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8)
    center = heading.centerYAnchor.constraint(equalTo: centerYAnchor)
    NSLayoutConstraint.activate([
      inset, dot.widthAnchor.constraint(equalToConstant: 12),
      dot.centerYAnchor.constraint(equalTo: heading.centerYAnchor),
      heading.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 5),
      heading.trailingAnchor.constraint(equalTo: selection.leadingAnchor, constant: -6), center,
      detail.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 3),
      detail.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
      detail.trailingAnchor.constraint(equalTo: heading.trailingAnchor),
      selection.widthAnchor.constraint(equalToConstant: 12),
      selection.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
      selection.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
    textField = heading
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  func configure(_ node: DataTreeNode, depth: Int, selected: Bool) {
    inset.constant = CGFloat(8 + depth * 16)
    heading.stringValue =
      String(node.title.prefix(200)) + (node.title.count > 200 ? "…" : "")
      + (node.loading
        ? " · 读取中…" : node.openError == nil ? "" : " · " + String(node.openError!.prefix(40)))
    detail.stringValue = node.kind == .connection ? node.detail : ""
    detail.isHidden = node.kind != .connection
    center.constant = node.kind == .connection ? -7 : 0
    selection.isHidden = !selected
    selection.setAccessibilityLabel("已选中")
    heading.setAccessibilityLabel(node.title)
    toolTip = String(
      (node.openError ?? (node.detail.isEmpty ? node.title : node.title + "\n" + node.detail))
        .prefix(2000))
  }
}

@MainActor final class NavigatorScroll: NSScrollView {
  var onWidth: ((CGFloat) -> Void)?
  override func tile() {
    super.tile()
    onWidth?(contentView.bounds.width)
  }
}
