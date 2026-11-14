import AppKit

enum Theme {
  static let paper = NSColor(srgbRed: 0.99, green: 0.987, blue: 0.975, alpha: 1)
  static let sidebar = NSColor(srgbRed: 0.975, green: 0.973, blue: 0.956, alpha: 1)
  static let ink = NSColor(srgbRed: 0.24, green: 0.26, blue: 0.24, alpha: 1)
  static let muted = NSColor(srgbRed: 0.52, green: 0.53, blue: 0.49, alpha: 1)
  static let sage = NSColor(srgbRed: 0.37, green: 0.49, blue: 0.39, alpha: 1)
  static let pale = NSColor(srgbRed: 0.88, green: 0.91, blue: 0.85, alpha: 1)
  static let line = NSColor(calibratedWhite: 0.84, alpha: 1)
  private static let fonts: NSCache<NSString, NSFont> = {
    let c = NSCache<NSString, NSFont>()
    c.countLimit = 64
    return c
  }()
  static func font(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
    let key = "\(size):\(weight.rawValue)" as NSString
    if let cached = fonts.object(forKey: key) { return cached }
    let names =
      weight.rawValue >= NSFont.Weight.medium.rawValue
      ? ["HanziPenSC-W5", "HanziPenSC-W3", "STKaitiSC-Regular"]
      : ["HanziPenSC-W3", "STKaitiSC-Regular", "STSongti-SC-Regular"]
    let value =
      names.compactMap { NSFont(name: $0, size: size) }.first
      ?? NSFont.systemFont(ofSize: size, weight: weight)
    fonts.setObject(value, forKey: key)
    return value
  }
  static func label(
    _ text: String, size: CGFloat = 12, weight: NSFont.Weight = .regular, muted: Bool = false
  ) -> NSTextField {
    let view = NSTextField(labelWithString: text)
    view.font = font(size + 1, weight: weight)
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
    field.font = font(13)
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
  var colorForCell: ((Int, Int) -> NSColor?)?
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
    cell.textField?.textColor = colorForCell?(row, i) ?? Theme.ink
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

/// Fixed, cached paper and pigment. No random changes during redraw or per-frame bitmap generation.
@MainActor enum CrayonInk {
  private static let cache: NSCache<NSString, NSImage> = {
    let c = NSCache<NSString, NSImage>()
    c.countLimit = 128
    c.totalCostLimit = 8 * 1024 * 1024
    return c
  }()
  static let paper: NSColor = NSColor(patternImage: tile(Theme.paper, sidebar: false))
  static let sidebar: NSColor = NSColor(patternImage: tile(Theme.sidebar, sidebar: true))
  private static func bitmap(_ size: NSSize, draw: (NSRect) -> Void) -> NSImage {
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: Int(ceil(size.width * 2)),
      pixelsHigh: Int(ceil(size.height * 2)), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
      isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let scale = NSAffineTransform()
    scale.scale(by: 2)
    scale.concat()
    draw(NSRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()
    let image = NSImage(size: size)
    image.addRepresentation(rep)
    return image
  }
  private static func tile(_ base: NSColor, sidebar: Bool) -> NSImage {
    bitmap(NSSize(width: 192, height: 192)) { rect in
      base.setFill()
      rect.fill()
      var seed: UInt64 = 0x81bf3
      func random() -> CGFloat {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1
        return CGFloat((seed >> 32) & 65535) / 65535
      }
      for pass in 0..<2 {
        let path = NSBezierPath()
        path.lineWidth = 0.45
        for _ in 0..<600 {
          let x = random() * 192
          let y = random() * 192
          path.move(to: NSPoint(x: x, y: y))
          path.line(to: NSPoint(x: x + 2 + random() * 5, y: y + random() * 1.8 - 0.9))
        }
        (pass == 0
          ? NSColor.white.withAlphaComponent(0.18)
          : Theme.ink.withAlphaComponent(sidebar ? 0.014 : 0.009)).setStroke()
        path.stroke()
      }
    }
  }
  static func stroke(_ path: NSBezierPath, color: NSColor, width: CGFloat = 1.6) {
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.lineWidth = width + 0.7
    color.withAlphaComponent(color.alphaComponent * 0.15).setStroke()
    path.stroke()
    path.lineWidth = width
    color.withAlphaComponent(color.alphaComponent * 0.78).setStroke()
    path.stroke()
  }
  static func swatch(_ rect: NSRect, color: NSColor) {
    let rgb = color.usingColorSpace(.sRGB) ?? color
    let key =
      "\(Int(rect.width.rounded(.up))):\(Int(rect.height.rounded(.up))):\(rgb.redComponent):\(rgb.greenComponent):\(rgb.blueComponent)"
      as NSString
    let image: NSImage
    if let found = cache.object(forKey: key) {
      image = found
    } else {
      let size = NSSize(width: ceil(rect.width), height: ceil(rect.height))
      image = bitmap(size) { bounds in
        let fill = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 3, yRadius: 3)
        color.withAlphaComponent(0.25).setFill()
        fill.fill()
        let strokes = NSBezierPath()
        strokes.lineWidth = 0.65
        for i in stride(from: 2, to: Int(bounds.height) - 1, by: 3) {
          strokes.move(to: NSPoint(x: 2, y: CGFloat(i)))
          strokes.line(to: NSPoint(x: bounds.width - 2, y: CGFloat(i) + 0.55))
        }
        color.withAlphaComponent(0.16).setStroke()
        strokes.stroke()
        let flecks = NSBezierPath()
        flecks.lineWidth = 0.6
        for i in stride(from: 5, to: Int(bounds.width) - 2, by: 11) {
          flecks.move(to: NSPoint(x: CGFloat(i), y: 4))
          flecks.line(to: NSPoint(x: CGFloat(i) + 2, y: 5))
        }
        NSColor.white.withAlphaComponent(0.5).setStroke()
        flecks.stroke()
      }
      cache.setObject(image, forKey: key, cost: Int(size.width * size.height * 16))
    }
    image.draw(in: rect)
  }
}

@MainActor final class PaperResizeHandle: NSView, WritingCursorProviding {
  var writingCursorRole: WritingCursorRole { .columnResize }
  var initialWidth: (() -> CGFloat)?
  var onChange: ((CGFloat) -> Void)?
  var onEnd: (() -> Void)?
  var direction: CGFloat = 1
  private var origin: CGFloat = 0, width: CGFloat = 0
  private var tracking: WritingCursorTracking!
  override init(frame: NSRect) {
    super.init(frame: frame)
    tracking = WritingCursorTracking(view: self)
  }
  required init?(coder: NSCoder) { nil }
  override func draw(_ dirtyRect: NSRect) {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: bounds.midX, y: 0))
    path.line(to: NSPoint(x: bounds.midX + 0.3, y: bounds.height))
    CrayonInk.stroke(path, color: Theme.muted.withAlphaComponent(0.22), width: 0.5)
  }
  override func mouseDown(with event: NSEvent) {
    origin = event.locationInWindow.x
    width = initialWidth?() ?? 0
  }
  override func mouseDragged(with event: NSEvent) {
    onChange?(width + (event.locationInWindow.x - origin) * direction)
  }
  override func mouseUp(with event: NSEvent) { onEnd?() }
}
