import AppKit
import SwiftUI

enum WritingCursorRole: CaseIterable {
  case standard, clickable, text, drag, dragging, disabled, splitResize, columnResize
}
@MainActor protocol WritingCursorProviding: AnyObject {
  var writingCursorRole: WritingCursorRole { get }
}

/// Scoped, event-driven cursor ownership. No global hooks or idle polling.
@MainActor enum WritingCursors {
  static let previewTheme: WritingCursorPreviewTheme? = {
    guard let identifier = Bundle.main.bundleIdentifier,
      ["cc.anjing.cs-tool-x", "cc.anjing.cs-tool-x.dev"].contains(identifier)
    else { return nil }
    let name = identifier.hasSuffix(".dev") ? "cs-tool-x-dev" : "cs-tool-x"
    let directory = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent(name, isDirectory: true).appendingPathComponent(
        "Cursors", isDirectory: true)
    return WritingCursorPreviewTheme.load(from: directory)
  }()
  static let arrow = previewTheme?.arrow ?? make(.standard)
  static let pointer = previewTheme?.pointer ?? WritingDragCursor.open
  static let text = make(.text)
  static let horizontal = make(.columnResize)
  static let vertical = make(.splitResize)
  static let disabled = make(.disabled)
  static func cursor(for role: WritingCursorRole) -> NSCursor {
    if let previewTheme { return previewTheme.cursor(for: role) }
    switch role {
    case .standard: return arrow
    case .clickable: return pointer
    case .text: return text
    case .drag: return WritingDragCursor.open
    case .dragging: return WritingDragCursor.closed
    case .disabled: return disabled
    case .splitResize: return vertical
    case .columnResize: return horizontal
    }
  }
  private static func make(_ role: WritingCursorRole) -> NSCursor {
    let image = NSImage(size: NSSize(width: 24, height: 24))
    image.lockFocus()
    let path = NSBezierPath()
    path.lineWidth = 1.4
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    let ink = NSColor(calibratedWhite: 0.22, alpha: 1)
    let paper = NSColor(calibratedWhite: 0.99, alpha: 1)
    switch role {
    case .text:
      path.move(to: NSPoint(x: 12, y: 4))
      path.line(to: NSPoint(x: 12, y: 20))
      for y: CGFloat in [4, 20] {
        path.move(to: NSPoint(x: 8, y: y))
        path.curve(
          to: NSPoint(x: 16, y: y), controlPoint1: NSPoint(x: 11, y: y + 1),
          controlPoint2: NSPoint(x: 13, y: y + 1))
      }
    case .columnResize, .splitResize:
      path.move(to: NSPoint(x: 3, y: 12))
      path.line(to: NSPoint(x: 21, y: 12))
      path.move(to: NSPoint(x: 7, y: 8))
      path.line(to: NSPoint(x: 3, y: 12))
      path.line(to: NSPoint(x: 7, y: 16))
      path.move(to: NSPoint(x: 17, y: 8))
      path.line(to: NSPoint(x: 21, y: 12))
      path.line(to: NSPoint(x: 17, y: 16))
      if role == .splitResize {
        var t = AffineTransform()
        t.translate(x: 12, y: 12)
        t.rotate(byDegrees: 90)
        t.translate(x: -12, y: -12)
        path.transform(using: t)
      }
    case .disabled:
      path.appendOval(in: NSRect(x: 4, y: 4, width: 16, height: 16))
      path.move(to: NSPoint(x: 7, y: 7))
      path.line(to: NSPoint(x: 17, y: 17))
    default:
      path.move(to: NSPoint(x: 4, y: 22))
      path.line(to: NSPoint(x: 5, y: 4))
      path.line(to: NSPoint(x: 10, y: 9))
      path.line(to: NSPoint(x: 14, y: 2))
      path.line(to: NSPoint(x: 17, y: 4))
      path.line(to: NSPoint(x: 13, y: 11))
      path.line(to: NSPoint(x: 20, y: 12))
      path.close()
      paper.setFill()
      path.fill()
    }
    paper.setStroke()
    path.lineWidth = 3.5
    path.stroke()
    ink.setStroke()
    path.lineWidth = 1.4
    path.stroke()
    image.unlockFocus()
    return NSCursor(
      image: image, hotSpot: role == .standard ? NSPoint(x: 4, y: 2) : NSPoint(x: 12, y: 12))
  }
  static func role(for target: NSView?) -> WritingCursorRole {
    var current = target
    while let view = current {
      if let owner = view as? WritingCursorProviding { return owner.writingCursorRole }
      if let text = view as? NSTextView {
        return text.isEditable || text.isSelectable ? .text : .standard
      }
      if let field = view as? NSTextField, field.isEditable || field.isSelectable {
        return field.isEnabled ? .text : .disabled
      }
      if let button = view as? NSButton { return button.isEnabled ? .clickable : .disabled }
      if let table = view as? NSTableView {
        return table.isEnabled ? (table.numberOfRows > 0 ? .clickable : .standard) : .disabled
      }
      if view is NSTableHeaderView { return .clickable }
      current = view.superview
    }
    return .standard
  }
  @discardableResult static func update(in window: NSWindow, at point: NSPoint)
    -> WritingCursorRole?
  {
    guard let content = window.contentView else { return nil }
    let local = content.convert(point, from: nil)
    guard content.bounds.contains(local) else { return nil }
    // Keep the OS edge-resize interaction intact; all client content is themed.
    if window.styleMask.contains(.resizable), !window.styleMask.contains(.fullScreen),
      !content.bounds.insetBy(dx: 4, dy: 4).contains(local)
    {
      return nil
    }
    let parentPoint = content.superview?.convert(point, from: nil) ?? local
    var role = role(for: content.hitTest(parentPoint))
    if let region = CursorRegionView.at(window: window, point: point) { role = region.role }
    let cursor = cursor(for: role)
    if NSCursor.current !== cursor { cursor.set() }
    return role
  }
}
@MainActor final class WritingCursorTracking: NSObject {
  private weak var view: NSView?
  private var area: NSTrackingArea?
  init(view: NSView) {
    self.view = view
    super.init()
    let area = NSTrackingArea(
      rect: .zero, options: [.cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self)
    self.area = area
    view.addTrackingArea(area)
  }
  @objc(cursorUpdate:) func cursorUpdate(with event: NSEvent) {
    if let window = view?.window { WritingCursors.update(in: window, at: event.locationInWindow) }
  }
}
/// SwiftUI buttons expose a declarative region; it does not intercept clicks.
@MainActor final class CursorRegionView: NSView {
  private final class Weak {
    weak var value: CursorRegionView?
    init(_ value: CursorRegionView) { self.value = value }
  }
  private static var regions: [Weak] = []
  var role: WritingCursorRole = .clickable
  private var tracking: WritingCursorTracking!
  override init(frame: NSRect) {
    super.init(frame: frame)
    tracking = WritingCursorTracking(view: self)
    Self.regions.removeAll { $0.value == nil }
    Self.regions.append(Weak(self))
    setAccessibilityElement(false)
  }
  required init?(coder: NSCoder) { nil }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  static func at(window: NSWindow, point: NSPoint) -> CursorRegionView? {
    regions.removeAll { $0.value == nil }
    return regions.compactMap(\.value).filter { view in
      view.window === window && !view.isHiddenOrHasHiddenAncestor
        && view.visibleRect.contains(view.convert(point, from: nil))
    }.min { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }
  }
}
struct CursorRegion: NSViewRepresentable {
  let role: WritingCursorRole
  func makeNSView(context: Context) -> CursorRegionView { CursorRegionView() }
  func updateNSView(_ view: CursorRegionView, context: Context) { view.role = role }
}
extension View {
  func writingCursor(_ role: WritingCursorRole) -> some View {
    background(CursorRegion(role: role))
  }
}

class CursorSheetWindow: NSWindow {
  override var canBecomeKey: Bool { true }
  override func sendEvent(_ event: NSEvent) {
    super.sendEvent(event)
    if event.type == .cursorUpdate || event.type == .leftMouseUp {
      WritingCursors.update(in: self, at: event.locationInWindow)
    }
  }
}

@MainActor final class CursorEventCoordinator {
  private var monitor: Any?
  init() {
    monitor = NSEvent.addLocalMonitorForEvents(matching: .cursorUpdate) { event in
      guard let window = event.window else { return event }
      // Run after nested controls (including AppKit field editors and SwiftTerm)
      // install their own cursor. No mouseMoved hook or periodic refresh.
      DispatchQueue.main.async { [weak window] in
        guard let window, window.isKeyWindow, window.frame.contains(NSEvent.mouseLocation) else {
          return
        }
        WritingCursors.update(in: window, at: window.mouseLocationOutsideOfEventStream)
      }
      return event
    }
  }
  func stop() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
  }
}
