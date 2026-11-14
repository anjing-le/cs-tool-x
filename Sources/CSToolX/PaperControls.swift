import AppKit

final class PaperSurface: NSView {
  private var cursorTracking: WritingCursorTracking!
  override init(frame: NSRect) {
    super.init(frame: frame)
    cursorTracking = WritingCursorTracking(view: self)
  }
  required init?(coder: NSCoder) { nil }
}

/// App-owned controls share ShellX's paper, sage, spacing and focus treatment.
class PaperButton: NSButton {
  override var isFlipped: Bool { false }
  override var acceptsFirstResponder: Bool { isEnabled }
  override var canBecomeKeyView: Bool { isEnabled }
  var primary = false
  var checkbox = false
  var disclosure = false
  var selected = false { didSet { needsDisplay = true } }
  private var hovered = false
  override var isEnabled: Bool { didSet { needsDisplay = true } }
  override var state: NSControl.StateValue { didSet { needsDisplay = true } }
  override var intrinsicContentSize: NSSize {
    NSSize(
      width: max(
        32,
        (title as NSString).size(withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 12)])
          .width + (checkbox ? 38 : 28)), height: checkbox ? 26 : 34)
  }
  override init(frame: NSRect) {
    super.init(frame: frame)
    isBordered = false
    focusRingType = .none
    font = .systemFont(ofSize: 12)
    setButtonType(.momentaryPushIn)
  }
  required init?(coder: NSCoder) { nil }
  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(
      NSTrackingArea(
        rect: .zero,
        options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .cursorUpdate],
        owner: self))
  }
  override func mouseEntered(with event: NSEvent) {
    hovered = true
    needsDisplay = true
  }
  override func mouseExited(with event: NSEvent) {
    hovered = false
    needsDisplay = true
  }
  override func cursorUpdate(with event: NSEvent) {
    WritingCursors.cursor(for: isEnabled ? .clickable : .disabled).set()
  }
  override func becomeFirstResponder() -> Bool {
    let result = super.becomeFirstResponder()
    needsDisplay = true
    return result
  }
  override func resignFirstResponder() -> Bool {
    let result = super.resignFirstResponder()
    needsDisplay = true
    return result
  }
  override func draw(_ dirtyRect: NSRect) {
    let active = isEnabled && (hovered || isHighlighted || selected)
    let rect =
      checkbox
      ? NSRect(x: 1, y: (bounds.height - 15) / 2, width: 15, height: 15)
      : bounds.insetBy(dx: 1, dy: 1)
    let path = NSBezierPath(roundedRect: rect, xRadius: checkbox ? 4 : 8, yRadius: checkbox ? 4 : 8)
    let checked = checkbox && state == .on
    let fill =
      checked
      ? Theme.sage : (primary || active ? Theme.pale : NSColor.white.withAlphaComponent(0.5))
    fill.withAlphaComponent(fill.alphaComponent * (isEnabled ? 1 : 0.35)).setFill()
    path.fill()
    (active || checked ? Theme.sage.withAlphaComponent(0.6) : Theme.line.withAlphaComponent(0.65))
      .setStroke()
    path.lineWidth = 1
    path.stroke()
    if window?.firstResponder === self {
      Theme.sage.setStroke()
      path.lineWidth = 2
      path.stroke()
    }
    if checked {
      let check = NSBezierPath()
      check.lineWidth = 1.6
      check.lineCapStyle = .round
      check.lineJoinStyle = .round
      check.move(to: NSPoint(x: rect.minX + 3.5, y: rect.midY))
      check.line(to: NSPoint(x: rect.minX + 6.5, y: rect.midY - 3))
      check.line(to: NSPoint(x: rect.maxX - 3, y: rect.midY + 3.5))
      NSColor.white.setStroke()
      check.stroke()
    }
    let text = title as NSString
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font ?? NSFont.systemFont(ofSize: 12),
      .foregroundColor: isEnabled
        ? (primary ? Theme.sage : Theme.ink) : Theme.muted.withAlphaComponent(0.55),
    ]
    let size = text.size(withAttributes: attributes)
    let x = checkbox ? 25 : (disclosure ? 11 : (bounds.width - size.width) / 2)
    text.draw(
      in: NSRect(
        x: x, y: (bounds.height - size.height) / 2,
        width: max(0, bounds.width - x - (disclosure ? 28 : 8)), height: size.height),
      withAttributes: attributes)
    if disclosure {
      let chevron = NSBezierPath()
      chevron.lineWidth = 1.2
      chevron.lineCapStyle = .round
      chevron.move(to: NSPoint(x: bounds.maxX - 19, y: bounds.midY + 2))
      chevron.line(to: NSPoint(x: bounds.maxX - 15, y: bounds.midY - 2))
      chevron.line(to: NSPoint(x: bounds.maxX - 11, y: bounds.midY + 2))
      Theme.muted.setStroke()
      chevron.stroke()
    }
  }
}

private func fieldTextRect(_ rect: NSRect, font: NSFont?) -> NSRect {
  let height = ceil((font ?? .systemFont(ofSize: 12)).boundingRectForFont.height) + 2
  return NSRect(
    x: rect.minX + 10, y: rect.midY - height / 2, width: max(0, rect.width - 20), height: height)
}
final class PaperFieldCell: NSTextFieldCell {
  override func drawingRect(forBounds rect: NSRect) -> NSRect { fieldTextRect(rect, font: font) }
  override func edit(
    withFrame rect: NSRect, in view: NSView, editor: NSText, delegate: Any?, event: NSEvent?
  ) {
    super.edit(
      withFrame: drawingRect(forBounds: rect), in: view, editor: editor, delegate: delegate,
      event: event)
  }
  override func select(
    withFrame rect: NSRect, in view: NSView, editor: NSText, delegate: Any?, start: Int, length: Int
  ) {
    super.select(
      withFrame: drawingRect(forBounds: rect), in: view, editor: editor, delegate: delegate,
      start: start, length: length)
  }
}
final class PaperSecureCell: NSSecureTextFieldCell {
  override func drawingRect(forBounds rect: NSRect) -> NSRect { fieldTextRect(rect, font: font) }
  override func edit(
    withFrame rect: NSRect, in view: NSView, editor: NSText, delegate: Any?, event: NSEvent?
  ) {
    super.edit(
      withFrame: drawingRect(forBounds: rect), in: view, editor: editor, delegate: delegate,
      event: event)
  }
  override func select(
    withFrame rect: NSRect, in view: NSView, editor: NSText, delegate: Any?, start: Int, length: Int
  ) {
    super.select(
      withFrame: drawingRect(forBounds: rect), in: view, editor: editor, delegate: delegate,
      start: start, length: length)
  }
}
private func drawField(_ field: NSTextField) {
  let focused = (field.currentEditor() != nil)
  let path = NSBezierPath(roundedRect: field.bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
  NSColor.white.withAlphaComponent(field.isEnabled ? 0.55 : 0.2).setFill()
  path.fill()
  (focused
    ? Theme.sage.withAlphaComponent(0.7)
    : Theme.line.withAlphaComponent(field.isEnabled ? 0.65 : 0.3)).setStroke()
  path.lineWidth = focused ? 1.5 : 1
  path.stroke()
}
private func prepareEditor(_ field: NSTextField) {
  if let editor = field.currentEditor() as? NSTextView {
    editor.insertionPointColor = Theme.sage
    editor.selectedTextAttributes = [.backgroundColor: Theme.pale, .foregroundColor: Theme.ink]
  }
}
final class PaperField: NSTextField {
  override func draw(_ dirtyRect: NSRect) {
    drawField(self)
    super.draw(dirtyRect)
  }
  override func becomeFirstResponder() -> Bool {
    let result = super.becomeFirstResponder()
    prepareEditor(self)
    needsDisplay = true
    return result
  }
  override func textDidEndEditing(_ notification: Notification) {
    super.textDidEndEditing(notification)
    needsDisplay = true
  }
}
final class PaperSecureField: NSSecureTextField {
  override func draw(_ dirtyRect: NSRect) {
    drawField(self)
    super.draw(dirtyRect)
  }
  override func becomeFirstResponder() -> Bool {
    let result = super.becomeFirstResponder()
    prepareEditor(self)
    needsDisplay = true
    return result
  }
  override func textDidEndEditing(_ notification: Notification) {
    super.textDidEndEditing(notification)
    needsDisplay = true
  }
}

final class PaperPopupWindow: CursorSheetWindow {
  var handleKey: ((NSEvent) -> Bool)?
  override var canBecomeKey: Bool { true }
  override func sendEvent(_ event: NSEvent) {
    if event.type == .keyDown, handleKey?(event) == true { return }
    super.sendEvent(event)
  }
}

/// A bounded, keyboard-operable dropdown. No system menu colors or bezels.
@MainActor final class PaperMenu: NSObject {
  private let panel: PaperPopupWindow
  private weak var anchor: NSView?
  private var buttons: [PaperButton] = []
  private var monitor: Any?
  private var observer: NSObjectProtocol?
  private var selected: Int
  private let action: (Int) -> Void
  init(
    titles: [String], selected: Int = 0, enabled: Bool = true, anchor: NSView,
    action: @escaping (Int) -> Void
  ) {
    self.anchor = anchor
    self.selected = max(0, min(selected, titles.count - 1))
    self.action = action
    let width = max(180, min(480, anchor.bounds.width))
    panel = PaperPopupWindow(
      contentRect: NSRect(
        x: 0, y: 0, width: width, height: min(320, CGFloat(max(1, titles.count)) * 36 + 12)),
      styleMask: [.borderless], backing: .buffered, defer: false)
    super.init()
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.isReleasedWhenClosed = false
    let surface = PaperSurface()
    surface.wantsLayer = true
    surface.layer?.backgroundColor = Theme.paper.cgColor
    surface.layer?.cornerRadius = 10
    surface.layer?.borderWidth = 1
    surface.layer?.borderColor = Theme.line.withAlphaComponent(0.7).cgColor
    panel.contentView = surface
    let scroll = NSScrollView()
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.scrollerStyle = .overlay
    Theme.pin(scroll, to: surface, inset: 6)
    let stack = Theme.stack([], spacing: 2)
    for (index, title) in titles.enumerated() {
      let button = PaperButton()
      button.title = title
      button.tag = index
      button.target = self
      button.action = #selector(choose(_:))
      button.isEnabled = enabled
      button.selected = index == self.selected
      button.setAccessibilityLabel(title)
      stack.addArrangedSubview(button)
      button.widthAnchor.constraint(equalToConstant: width - 12).isActive = true
      button.heightAnchor.constraint(equalToConstant: 34).isActive = true
      buttons.append(button)
    }
    stack.setFrameSize(NSSize(width: width - 12, height: CGFloat(titles.count) * 36))
    scroll.documentView = stack
    panel.handleKey = { [weak self] event in self?.key(event) ?? false }
  }
  func show() {
    guard let anchor, let parent = anchor.window else { return }
    var rect = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
    let visible = parent.screen?.visibleFrame ?? parent.frame
    rect.origin.x = min(max(rect.minX, visible.minX + 8), visible.maxX - panel.frame.width - 8)
    let y = rect.minY - panel.frame.height - 5
    panel.setFrameOrigin(
      NSPoint(
        x: rect.minX,
        y: y >= visible.minY ? y : min(rect.maxY + 5, visible.maxY - panel.frame.height)))
    parent.addChildWindow(panel, ordered: .above)
    panel.makeKeyAndOrderFront(nil)
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
      [weak self] event in
      if let self, event.window !== self.panel { self.dismiss() }
      return event
    }
    observer = NotificationCenter.default.addObserver(
      forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.dismiss() }
    }
  }
  func dismiss() {
    let parent = panel.parent
    parent?.removeChildWindow(panel)
    panel.orderOut(nil)
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
    if let observer { NotificationCenter.default.removeObserver(observer) }
    observer = nil
    parent?.makeKey()
    if let anchor { parent?.makeFirstResponder(anchor) }
  }
  private func key(_ event: NSEvent) -> Bool {
    switch event.keyCode {
    case 53, 48:
      dismiss()
      return true
    case 125, 126:
      guard !buttons.isEmpty else { return true }
      selected = (selected + (event.keyCode == 125 ? 1 : buttons.count - 1)) % buttons.count
      for (i, button) in buttons.enumerated() { button.selected = i == selected }
      buttons[selected].scrollToVisible(buttons[selected].bounds)
      return true
    case 36, 49:
      if !buttons.isEmpty { choose(buttons[selected]) }
      return true
    default: return false
    }
  }
  @objc private func choose(_ sender: NSButton) {
    guard sender.isEnabled else { return }
    let callback = action
    dismiss()
    callback(sender.tag)
  }
  deinit {
    if let monitor { NSEvent.removeMonitor(monitor) }
    if let observer { NotificationCenter.default.removeObserver(observer) }
  }
}

final class PaperSelect: PaperButton {
  private var titles: [String] = []
  private(set) var indexOfSelectedItem = 0
  var titleOfSelectedItem: String? {
    titles.indices.contains(indexOfSelectedItem) ? titles[indexOfSelectedItem] : nil
  }
  private var popup: PaperMenu?
  private weak var selectionTarget: AnyObject?
  private var selectionAction: Selector?
  func addItems(withTitles titles: [String]) {
    self.titles = titles
    selectItem(at: 0)
  }
  func selectItem(at index: Int) {
    guard titles.indices.contains(index) else { return }
    indexOfSelectedItem = index
    title = titles[index]
    needsDisplay = true
  }
  func selectItem(withTitle title: String) {
    if let i = titles.firstIndex(of: title) { selectItem(at: i) }
  }
  func onChange(target: AnyObject, action: Selector) {
    selectionTarget = target
    selectionAction = action
  }
  override init(frame: NSRect) {
    super.init(frame: frame)
    disclosure = true
    target = self
    action = #selector(openMenu)
  }
  required init?(coder: NSCoder) { nil }
  override func keyDown(with event: NSEvent) {
    if event.keyCode == 125 || event.keyCode == 126 {
      openMenu()
    } else {
      super.keyDown(with: event)
    }
  }
  func dismissMenu() {
    popup?.dismiss()
    popup = nil
  }
  @objc private func openMenu() {
    popup?.dismiss()
    popup = PaperMenu(titles: titles, selected: indexOfSelectedItem, anchor: self) {
      [weak self] index in
      guard let self else { return }
      selectItem(at: index)
      if let selectionAction { NSApp.sendAction(selectionAction, to: selectionTarget, from: self) }
    }
    popup?.show()
  }
}

@MainActor final class PaperDialog: NSObject {
  private static var visible: [UUID: PaperDialog] = [:]
  private let id = UUID()
  private let panel: CursorSheetWindow
  static func show(title: String, text: String, window: NSWindow?, detail: Bool = false) {
    let dialog = PaperDialog(title: title, text: text, detail: detail)
    visible[dialog.id] = dialog
    if let window, window.attachedSheet == nil {
      window.beginSheet(dialog.panel)
    } else {
      dialog.panel.center()
      dialog.panel.makeKeyAndOrderFront(nil)
    }
  }
  private init(title: String, text: String, detail: Bool) {
    panel = CursorSheetWindow(
      contentRect: NSRect(x: 0, y: 0, width: detail ? 680 : 460, height: detail ? 420 : 230),
      styleMask: [.borderless], backing: .buffered, defer: false)
    super.init()
    panel.title = title
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    let surface = PaperSurface()
    surface.wantsLayer = true
    surface.layer?.backgroundColor = Theme.paper.cgColor
    surface.layer?.cornerRadius = 14
    surface.layer?.borderColor = Theme.line.cgColor
    surface.layer?.borderWidth = 1
    panel.contentView = surface
    let scroll = NSTextView.scrollableTextView()
    scroll.drawsBackground = false
    scroll.scrollerStyle = .overlay
    scroll.autohidesScrollers = true
    let field = scroll.documentView as! NSTextView
    field.isEditable = false
    field.isRichText = false
    field.drawsBackground = false
    field.textColor = Theme.ink
    field.selectedTextAttributes = [.backgroundColor: Theme.pale, .foregroundColor: Theme.ink]
    field.font =
      detail ? .monospacedSystemFont(ofSize: 12, weight: .regular) : .systemFont(ofSize: 12)
    field.textContainerInset = NSSize(width: 2, height: 10)
    field.string = text
    field.setAccessibilityLabel(title)
    let close = Theme.button("关闭", target: self, action: #selector(dismiss), primary: true)
    close.keyEquivalent = "\u{1b}"
    let footer = Theme.stack([NSView(), close], vertical: false)
    let root = Theme.stack(
      [Theme.label(title, size: 19, weight: .medium), scroll, footer], spacing: 14)
    Theme.pin(root, to: surface, inset: 24)
    for view in [scroll, footer] {
      view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
    }
    scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: detail ? 260 : 90).isActive = true
  }
  @objc private func dismiss() {
    panel.sheetParent?.endSheet(panel)
    panel.orderOut(nil)
    Self.visible[id] = nil
  }
}

final class PaperTableRow: NSTableRowView {
  override func drawSelection(in dirtyRect: NSRect) {
    Theme.pale.withAlphaComponent(isEmphasized ? 0.85 : 0.5).setFill()
    bounds.fill()
  }
}
final class PaperTableHeader: NSTableHeaderCell {
  override func draw(withFrame frame: NSRect, in view: NSView) {
    Theme.sidebar.setFill()
    frame.fill()
    Theme.line.withAlphaComponent(0.6).setFill()
    NSRect(x: frame.minX, y: frame.maxY - 1, width: frame.width, height: 1).fill()
    (stringValue as NSString).draw(
      in: frame.insetBy(dx: 9, dy: 4),
      withAttributes: [
        .font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: Theme.muted,
      ])
  }
}

/// Unframed app-owned icon target; no persistent bezel or background.
@MainActor final class PaperIconButton: PaperButton {
  var symbol: String { didSet { needsDisplay = true } }
  var badge = false { didSet { needsDisplay = true } }
  private var over = false
  private var iconKey = ""
  private var icon: NSImage?
  override var intrinsicContentSize: NSSize { NSSize(width: 28, height: 28) }
  init(symbol: String, label: String, target: AnyObject?, action: Selector) {
    self.symbol = symbol
    super.init(frame: .zero)
    self.target = target
    self.action = action
    title = ""
    toolTip = label
    setAccessibilityLabel(label)
  }
  required init?(coder: NSCoder) { nil }
  override func mouseEntered(with event: NSEvent) {
    super.mouseEntered(with: event)
    over = true
  }
  override func mouseExited(with event: NSEvent) {
    super.mouseExited(with: event)
    over = false
  }
  override func draw(_ dirtyRect: NSRect) {
    if isEnabled && (over || isHighlighted || selected) {
      Theme.pale.withAlphaComponent(selected ? 0.7 : 0.45).setFill()
      NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 2), xRadius: 4, yRadius: 4).fill()
    }
    let color = isEnabled ? Theme.ink : Theme.muted.withAlphaComponent(0.4)
    let key = symbol + (isEnabled ? ":on" : ":off")
    if iconKey != key {
      iconKey = key
      icon = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
        .withSymbolConfiguration(
          .init(pointSize: 12, weight: .regular).applying(.init(paletteColors: [color])))
    }
    if let icon {
      let scale = min(14 / max(1, icon.size.width), 14 / max(1, icon.size.height))
      let size = NSSize(width: icon.size.width * scale, height: icon.size.height * scale)
      icon.draw(
        in: NSRect(
          x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
          width: size.width, height: size.height))
    }
    if badge {
      Theme.sage.setFill()
      NSBezierPath(ovalIn: NSRect(x: bounds.maxX - 6, y: bounds.maxY - 6, width: 4, height: 4))
        .fill()
    }
    if window?.firstResponder === self {
      Theme.sage.setStroke()
      let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4)
      path.lineWidth = 1
      path.stroke()
    }
  }
}
