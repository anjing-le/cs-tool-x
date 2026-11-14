import AppKit
import SwiftUI

// Native hit targets let the same cursorUpdate owner resolve every button.
struct ActionTarget: NSViewRepresentable {
  let label: String
  var enabled = true
  var doubleClick = false
  var onSelect: (() -> Void)? = nil
  let action: () -> Void
  func makeCoordinator() -> Coordinator { Coordinator() }
  func makeNSView(context: Context) -> HitButton {
    let button = HitButton()
    button.isBordered = false
    button.title = ""
    button.bezelStyle = .regularSquare
    button.setButtonType(.momentaryChange)
    button.target = context.coordinator
    button.action = #selector(Coordinator.activate)
    return button
  }
  func updateNSView(_ button: HitButton, context: Context) {
    context.coordinator.action = action
    button.isEnabled = enabled
    button.requiredClicks = doubleClick ? 2 : 1
    button.selectionHandler = onSelect
    button.setAccessibilityLabel(label)
    button.toolTip = label
  }
  final class Coordinator: NSObject {
    var action: (() -> Void)?
    @objc func activate() { action?() }
  }
}
final class HitButton: NSButton {
  override var acceptsFirstResponder: Bool { isEnabled }
  var requiredClicks = 1
  var selectionHandler: (() -> Void)?
  override func mouseDown(with event: NSEvent) {
    guard isEnabled else { return }
    guard requiredClicks == 2 else {
      super.mouseDown(with: event)
      return
    }
    window?.makeFirstResponder(self)
    selectionHandler?()
    if event.clickCount == 2 { sendAction(action, to: target) }
  }
  override func keyDown(with event: NSEvent) {
    if isEnabled && [36, 76, 49].contains(event.keyCode) {
      sendAction(action, to: target)
    } else {
      super.keyDown(with: event)
    }
  }
  override init(frame: NSRect) { super.init(frame: frame) }
  required init?(coder: NSCoder) { nil }
  override func draw(_ dirtyRect: NSRect) {
    if window?.firstResponder === self {
      let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 2), xRadius: 6, yRadius: 6)
      Theme.sage.withAlphaComponent(0.65).setStroke()
      path.lineWidth = 2
      path.stroke()
    }
  }
}
