import AppKit

enum Theme {
  static let paper = NSColor(srgbRed: 0.99, green: 0.987, blue: 0.975, alpha: 1)
  static let sidebar = NSColor(srgbRed: 0.975, green: 0.973, blue: 0.956, alpha: 1)
  static let ink = NSColor(srgbRed: 0.24, green: 0.26, blue: 0.24, alpha: 1)
  static let muted = NSColor(srgbRed: 0.52, green: 0.53, blue: 0.49, alpha: 1)
  static let sage = NSColor(srgbRed: 0.37, green: 0.49, blue: 0.39, alpha: 1)
  static let pale = NSColor(srgbRed: 0.88, green: 0.91, blue: 0.85, alpha: 1)
  static let line = NSColor(calibratedWhite: 0.84, alpha: 1)
  static func label(
    _ text: String, size: CGFloat = 12, weight: NSFont.Weight = .regular, muted: Bool = false
  ) -> NSTextField {
    let view = NSTextField(labelWithString: text)
    view.font = .systemFont(ofSize: size, weight: weight)
    view.textColor = muted ? self.muted : ink
    view.lineBreakMode = .byTruncatingTail
    return view
  }
  static func button(_ title: String, target: AnyObject?, action: Selector, primary: Bool = false)
    -> NSButton
  {
    let button = PaperButton()
    button.title = title
    button.target = target
    button.action = action
    button.primary = primary
    return button
  }
  static func stack(_ views: [NSView], vertical: Bool = true, spacing: CGFloat = 12) -> NSStackView
  {
    let stack = NSStackView(views: views)
    stack.orientation = vertical ? .vertical : .horizontal
    stack.alignment = vertical ? .leading : .centerY
    stack.distribution = .fill
    stack.spacing = spacing
    return stack
  }
  static func pin(_ child: NSView, to parent: NSView, inset: CGFloat = 0) {
    child.translatesAutoresizingMaskIntoConstraints = false
    parent.addSubview(child)
    NSLayoutConstraint.activate([
      child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset),
      child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset),
      child.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset),
      child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset),
    ])
  }
  static func separator(vertical: Bool = false) -> NSBox {
    let box = NSBox()
    box.boxType = .separator
    box.translatesAutoresizingMaskIntoConstraints = false
    if vertical {
      box.widthAnchor.constraint(equalToConstant: 1).isActive = true
    } else {
      box.heightAnchor.constraint(equalToConstant: 1).isActive = true
    }
    return box
  }
  static func field(_ placeholder: String) -> NSTextField {
    let field = PaperField()
    field.cell = PaperFieldCell(textCell: "")
    configure(field, placeholder: placeholder)
    return field
  }
  static func secureField(_ placeholder: String) -> NSSecureTextField {
    let field = PaperSecureField()
    field.cell = PaperSecureCell(textCell: "")
    configure(field, placeholder: placeholder)
    return field
  }
  private static func configure(_ field: NSTextField, placeholder: String) {
    field.placeholderString = placeholder
    field.isAutomaticTextCompletionEnabled = false
    field.isEditable = true
    field.isSelectable = true
    field.cell?.isScrollable = true
    field.cell?.wraps = false
    field.isBordered = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.font = .systemFont(ofSize: 12)
    field.textColor = ink
    field.heightAnchor.constraint(equalToConstant: 34).isActive = true
  }
  static func checkbox(_ title: String) -> NSButton {
    let button = PaperButton()
    button.title = title
    button.checkbox = true
    button.setButtonType(.switch)
    return button
  }
  @MainActor static func error(_ error: Error, window: NSWindow?) {
    PaperDialog.show(title: "操作未完成", text: error.localizedDescription, window: window)
  }
}
@MainActor
final class TextTable: NSObject, NSTableViewDataSource, NSTableViewDelegate {
  let table = NSTableView()
  let scroll = NSScrollView()
  var rows: [[String]] = []
  var onSelect: ((Int) -> Void)?
  var onActivate: ((Int, Int) -> Void)?
  init(headers: [String] = [], widths: [CGFloat] = [], header: Bool = true) {
    super.init()
    table.focusRingType = .none
    scroll.focusRingType = .none
    table.delegate = self
    table.dataSource = self
    table.rowHeight = 29
    table.usesAlternatingRowBackgroundColors = false
    table.backgroundColor = Theme.paper
    table.gridStyleMask = [.solidHorizontalGridLineMask]
    table.gridColor = NSColor(calibratedWhite: 0.92, alpha: 1)
    table.columnAutoresizingStyle = .noColumnAutoresizing
    table.target = self
    table.doubleAction = #selector(activate)
    scroll.documentView = table
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = true
    scroll.drawsBackground = false
    scroll.scrollerStyle = .overlay
    scroll.autohidesScrollers = true
    setColumns(headers, widths: widths)
    if !header { table.headerView = nil }
  }
  func setColumns(_ headers: [String], widths: [CGFloat] = []) {
    for column in table.tableColumns { table.removeTableColumn(column) }
    for (i, title) in headers.enumerated() {
      let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(String(i)))
      column.headerCell = PaperTableHeader(textCell: title)
      column.width = i < widths.count ? widths[i] : 220
      column.minWidth = 60
      table.addTableColumn(column)
    }
  }
  func update(_ rows: [[String]]) {
    self.rows = rows
    table.reloadData()
  }
  func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView?
  {
    guard row < rows.count, let column = tableColumn, let i = Int(column.identifier.rawValue),
      i < rows[row].count
    else { return nil }
    let id = NSUserInterfaceItemIdentifier("cell")
    let cell =
      (tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView) ?? NSTableCellView()
    if cell.textField == nil {
      let text = Theme.label("", size: 11)
      text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
      text.translatesAutoresizingMaskIntoConstraints = false
      cell.addSubview(text)
      cell.textField = text
      NSLayoutConstraint.activate([
        text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 9),
        text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -9),
        text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
      ])
    }
    cell.identifier = id
    cell.textField?.stringValue = rows[row][i]
    cell.toolTip = nil
    return cell
  }
  func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
    PaperTableRow()
  }
  func tableViewSelectionDidChange(_ notification: Notification) {
    if table.selectedRow >= 0 { onSelect?(table.selectedRow) }
  }
  @objc private func activate() {
    if table.clickedRow >= 0 { onActivate?(table.clickedRow, max(0, table.clickedColumn)) }
  }
}
