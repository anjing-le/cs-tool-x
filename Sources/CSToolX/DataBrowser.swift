import AppKit
import ToolCore

/// A small object browser: local filtering, explicit refresh and one query entry.
@MainActor
final class DataBrowser: NSView, NSTextFieldDelegate {
  private let titleLabel = Theme.label("", size: 18, weight: .medium)
  private let location = Theme.label("", size: 10, muted: true)
  private let filter = Theme.field("筛选已加载对象")
  private let count = Theme.label("", size: 10, muted: true)
  private let table = TextTable()
  private let empty = Theme.label("", size: 12, muted: true)
  private var refresh: NSButton!
  private var back: NSButton!
  private var allNodes: [DataTreeNode] = []
  private var shown: [DataTreeNode] = []
  private var kind: DatabaseKind = .mysql
  var onOpen: ((DataTreeNode) -> Void)?
  var onRefresh: (() -> Void)?
  var onQuery: (() -> Void)?
  var onBack: (() -> Void)?

  override init(frame: NSRect) {
    super.init(frame: frame)
    let browse = Theme.button("浏览", target: nil, action: #selector(noop)) as! PaperButton
    browse.selected = true
    let query = Theme.button("查询", target: self, action: #selector(query))
    back = Theme.button("‹", target: self, action: #selector(goBack))
    back.setAccessibilityLabel("返回上级目录")
    refresh = Theme.button("刷新", target: self, action: #selector(reload))
    let heading = Theme.stack([back, titleLabel, NSView()], vertical: false, spacing: 10)
    heading.detachesHiddenViews = true
    let modes = Theme.stack([browse, query, NSView()], vertical: false, spacing: 6)
    let controls = Theme.stack([filter, count, refresh], vertical: false, spacing: 12)
    filter.delegate = self
    filter.setAccessibilityLabel("筛选已加载对象")
    let root = Theme.stack(
      [heading, location, modes, Theme.separator(), controls, empty, table.scroll], spacing: 12)
    root.detachesHiddenViews = true
    Theme.pin(root, to: self, inset: 24)
    for view in [heading, location, modes, controls, table.scroll] {
      view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
    }
    filter.setContentHuggingPriority(.defaultLow, for: .horizontal)
    table.table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    table.scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
    table.onActivate = { [weak self] row, _ in
      guard let self, shown.indices.contains(row) else { return }
      let node = shown[row]
      guard node.kind != .message else { return }
      onOpen?(node)
    }
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  func update(_ node: DataTreeNode, breadcrumb: String) {
    kind = node.profile?.kind ?? .mysql
    titleLabel.stringValue = node.title
    titleLabel.toolTip = node.detail
    location.stringValue =
      node.parentID == nil
      ? (node.profile.map { ConnectionIdentity($0).address + " · " + $0.environment } ?? breadcrumb)
      : breadcrumb
    location.toolTip = node.profile?.address
    back.isHidden = node.parentID == nil
    refresh.isEnabled = !node.loading
    refresh.title = node.loading ? "读取中…" : "刷新"
    allNodes = node.children
    empty.stringValue = node.loading ? "正在读取…" : node.loaded ? "没有可见对象" : "双击左侧对象打开"
    if let error = node.openError { empty.stringValue = error }
    empty.maximumNumberOfLines = 2
    empty.isHidden = node.openError == nil && !allNodes.isEmpty
    if node.kind == .connection, kind == .es {
      table.setColumns(["索引", "健康", "文档数", "大小"], widths: [320, 85, 110, 110])
    } else if node.kind == .database, kind == .redis {
      table.setColumns(["Key"], widths: [600])
    } else if node.kind == .schema || (node.kind == .database && kind == .mysql) {
      table.setColumns(["表 / 视图", "类型"], widths: [390, 150])
    } else {
      table.setColumns(
        [node.kind == .database && kind == .pg ? "Schema" : kind == .redis ? "DB" : "数据库 / Schema"],
        widths: [600])
    }
    applyFilter()
  }
  func controlTextDidChange(_ obj: Notification) { applyFilter() }
  private func applyFilter() {
    let text = filter.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    shown = allNodes.filter { text.isEmpty || $0.title.localizedCaseInsensitiveContains(text) }
    table.update(
      shown.map { node in
        if node.kind == .index, node.object.count >= 4 {
          return node.object.prefix(4).map { String($0.text.prefix(2048)) }
        }
        if node.kind == .table {
          return [node.title, node.object.count > 2 ? node.object[2].text : ""]
        }
        return [String(node.title.prefix(2048))]
      })
    let total = allNodes.filter { $0.kind != .message && $0.kind != .more }.count
    let visible = shown.filter { $0.kind != .message && $0.kind != .more }.count
    count.stringValue = text.isEmpty ? "\(total) 项" : "\(visible) / \(total) 项"
  }
  @objc private func noop() {}
  @objc private func query() { onQuery?() }
  @objc private func reload() { onRefresh?() }
  @objc private func goBack() { onBack?() }
}
