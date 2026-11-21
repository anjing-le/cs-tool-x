import AppKit

/// The same borderless native window pattern used by FinanceX / EnglishX.
final class WorkbenchWindow: NSWindow {
  private var restoredFrame: NSRect?
  var onNavigate: ((Bool) -> Bool)?
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
    if flags == .command, event.keyCode == 33 || event.keyCode == 30,
      let onNavigate
    {
      if event.isARepeat { return true }
      if onNavigate(event.keyCode == 30) { return true }
    }
    return super.performKeyEquivalent(with: event)
  }
  init(contentRect: NSRect) {
    super.init(
      contentRect: contentRect, styleMask: [.borderless, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false)
    title = "cs-tool-x"
    isReleasedWhenClosed = false
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    collectionBehavior.insert(.fullScreenPrimary)
  }
  override func sendEvent(_ event: NSEvent) {
    if attachedSheet == nil, NSApp.modalWindow == nil,
      event.type == .otherMouseDown || event.type == .otherMouseUp,
      event.buttonNumber == 3 || event.buttonNumber == 4,
      let onNavigate
    {
      // Consume the pair; one navigation on release, scoped to this window only.
      if event.type == .otherMouseDown { return }
      if onNavigate(event.buttonNumber == 4) { return }
    }
    super.sendEvent(event)
    if event.type == .cursorUpdate || event.type == .leftMouseUp {
      WritingCursors.update(in: self, at: event.locationInWindow)
    }
  }
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
  override func performClose(_ sender: Any?) { if attachedSheet == nil { close() } }
  override func performMiniaturize(_ sender: Any?) { miniaturize(sender) }
  func toggleDesktopMaximize() {
    guard !styleMask.contains(.fullScreen), let visible = screen?.visibleFrame else { return }
    if let previous = restoredFrame, frame == visible {
      let width = min(previous.width, visible.width)
      let height = min(previous.height, visible.height)
      let restored = NSRect(
        x: min(max(previous.minX, visible.minX), visible.maxX - width),
        y: min(max(previous.minY, visible.minY), visible.maxY - height), width: width,
        height: height)
      setFrame(restored, display: true)
      restoredFrame = nil
    } else {
      restoredFrame = frame
      setFrame(visible, display: true)
    }
  }
}
final class WorkbenchSurface: NSView {
  private let dragRegion = WorkbenchDragRegion()
  private var cursorTracking: WritingCursorTracking!
  override var isFlipped: Bool { true }
  override init(frame: NSRect) {
    super.init(frame: frame)
    cursorTracking = WritingCursorTracking(view: self)
    wantsLayer = true
    layer?.cornerRadius = 12
    layer?.masksToBounds = true
    layer?.backgroundColor = Theme.paper.cgColor
  }
  required init?(coder: NSCoder) { nil }
  override func draw(_ dirtyRect: NSRect) {
    CrayonInk.paper.setFill()
    bounds.fill()
  }
  func installDragRegion() { addSubview(dragRegion, positioned: .above, relativeTo: nil) }
  override func layout() {
    super.layout()
    dragRegion.frame = NSRect(x: 148, y: 0, width: max(0, bounds.width - 248), height: 28)
  }
}
final class WorkbenchDragRegion: NSView, WritingCursorProviding {
  private var dragging = false
  var writingCursorRole: WritingCursorRole { dragging ? .dragging : .drag }
  override var mouseDownCanMoveWindow: Bool { false }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func mouseDown(with event: NSEvent) {
    guard let window = window as? WorkbenchWindow, !window.styleMask.contains(.fullScreen) else {
      return
    }
    if event.clickCount == 2 {
      window.toggleDesktopMaximize()
      return
    }
    dragging = true
    WritingCursors.cursor(for: .dragging).push()
    defer {
      dragging = false
      NSCursor.pop()
      WritingCursors.update(in: window, at: window.mouseLocationOutsideOfEventStream)
    }
    window.performDrag(with: event)
  }
}
