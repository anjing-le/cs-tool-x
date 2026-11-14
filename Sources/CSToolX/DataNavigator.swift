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

/// Virtualized rows with custom disclosure controls; expansion has no polling.
@MainActor
final class DataNavigator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
  struct Visible {
    let node: DataTreeNode
    let depth: Int
  }
  private let table = NavigatorTable()
  let scroll = NSScrollView()
  private(set) var roots: [DataTreeNode] = []
  private var visible: [Visible] = []
  private var expanded: Set<String> = []
  private var source: [String: [ConnectionProfile]] = [:]
  private var rebuilding = false
  private var connectionFilter: String?
  var onSelect: ((DataTreeNode) -> Void)?
  var onExpand: ((DataTreeNode) -> Void)?
  var onActivate: ((DataTreeNode) -> Void)?
  override init() {
    super.init()
    table.delegate = self
    table.dataSource = self
    table.headerView = nil
    table.backgroundColor = Theme.sidebar
    table.focusRingType = .none
    table.rowHeight = 32
    table.intercellSpacing = NSSize(width: 0, height: 1)
    table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    table.target = self
    table.doubleAction = #selector(activate)
    table.setAccessibilityLabel("数据连接树")
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
  func expand(_ node: DataTreeNode) {
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
      table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
    }
    scroll.contentView.scroll(to: origin)
    scroll.reflectScrolledClipView(scroll.contentView)
    rebuilding = false
  }
  private func toggle(_ node: DataTreeNode) {
    guard node.expandable else {
      onActivate?(node)
      return
    }
    if expanded.remove(node.id) == nil {
      expanded.insert(node.id)
      rebuild()
      onExpand?(node)
    } else {
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
      if node.kind == .connection { toggle(node) } else { onActivate?(node) }
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
    cell.configure(node, depth: item.depth, expanded: expanded.contains(node.id)) {
      [weak self, weak node] in
      guard let node else { return }
      self?.toggle(node)
    }
    return cell
  }
  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    PaperTableRow()
  }
  func tableViewSelectionDidChange(_ notification: Notification) {
    guard !rebuilding, visible.indices.contains(table.selectedRow) else { return }
    onSelect?(visible[table.selectedRow].node)
  }
  @objc private func activate() {
    guard visible.indices.contains(table.clickedRow) else { return }
    let node = visible[table.clickedRow].node
    if node.kind == .connection { toggle(node) } else { onActivate?(node) }
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
  private let disclosure = PaperButton()
  private let heading = Theme.label("", size: 11)
  private let detail = Theme.label("", size: 9, muted: true)
  private var inset: NSLayoutConstraint!
  private var center: NSLayoutConstraint!
  private var action: (() -> Void)?
  override init(frame: NSRect) {
    super.init(frame: frame)
    disclosure.target = self
    disclosure.action = #selector(toggle)
    for view in [disclosure, heading, detail] {
      view.translatesAutoresizingMaskIntoConstraints = false
      addSubview(view)
    }
    inset = disclosure.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8)
    center = heading.centerYAnchor.constraint(equalTo: centerYAnchor)
    NSLayoutConstraint.activate([
      inset, disclosure.widthAnchor.constraint(equalToConstant: 22),
      disclosure.heightAnchor.constraint(equalToConstant: 22),
      disclosure.centerYAnchor.constraint(equalTo: centerYAnchor),
      heading.leadingAnchor.constraint(equalTo: disclosure.trailingAnchor, constant: 5),
      heading.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8), center,
      detail.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 3),
      detail.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
      detail.trailingAnchor.constraint(equalTo: heading.trailingAnchor),
    ])
    textField = heading
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  func configure(_ node: DataTreeNode, depth: Int, expanded: Bool, action: @escaping () -> Void) {
    self.action = action
    inset.constant = CGFloat(8 + depth * 16)
    heading.stringValue =
      String(node.title.prefix(200)) + (node.title.count > 200 ? "…" : "")
      + (node.loading ? " · 读取中…" : "")
    detail.stringValue = node.kind == .connection ? node.detail : ""
    detail.isHidden = node.kind != .connection
    center.constant = node.kind == .connection ? -7 : 0
    disclosure.isHidden = !node.expandable
    disclosure.title = expanded ? "⌄" : "›"
    disclosure.setAccessibilityLabel((expanded ? "收起 " : "展开 ") + node.title)
    heading.setAccessibilityLabel(node.title)
    toolTip = String(
      (node.detail.isEmpty ? node.title : node.title + "\n" + node.detail).prefix(2000))
  }
  @objc private func toggle() { action?() }
}
