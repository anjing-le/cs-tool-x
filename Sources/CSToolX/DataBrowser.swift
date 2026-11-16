import AppKit
import ToolCore

/// Empty content state for a directory. Objects are listed only in DataNavigator.
@MainActor
final class DataBrowser: NSView {
  private let context = Theme.label("", size: 13, muted: true)
  private let environment = Theme.label("", size: 10, muted: true)
  private let status = Theme.label("", size: 11, muted: true)
  var onQuery: (() -> Void)?

  override init(frame: NSRect) {
    super.init(frame: frame)
    let query = Theme.button("查询", target: self, action: #selector(openQuery))
    let toolbar = Theme.stack([context, environment, NSView(), query], vertical: false, spacing: 10)
    toolbar.detachesHiddenViews = true
    context.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    status.maximumNumberOfLines = 2
    let root = Theme.stack([toolbar, status, NSView()], spacing: 12)
    root.detachesHiddenViews = true
    Theme.pin(root, to: self, inset: 16)
    for view in [toolbar, status] {
      view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
    }
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  func update(_ node: DataTreeNode, breadcrumb: String) {
    context.stringValue = node.title
    context.toolTip = breadcrumb
    environment.stringValue = node.profile?.environment ?? ""
    environment.isHidden = environment.stringValue.isEmpty
    toolTip = [breadcrumb, node.profile?.address].compactMap { $0 }.joined(separator: " · ")
    status.stringValue = node.openError ?? (node.loading ? "读取中…" : "")
    status.isHidden = status.stringValue.isEmpty
  }
  @objc private func openQuery() { onQuery?() }
}

/// Directory navigation must not replace an already open result or query draft.
@MainActor
final class DataContentHost: NSView {
  func showDirectory(_ directory: DataBrowser) {
    guard !subviews.contains(where: { $0 is DataWorkspace }) else { return }
    subviews.forEach { $0.removeFromSuperview() }
    Theme.pin(directory, to: self)
  }
}
