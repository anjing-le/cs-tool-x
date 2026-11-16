import AppKit
import SwiftUI

// Native hit targets let the same cursorUpdate owner resolve every button.
struct ActionTarget: NSViewRepresentable {
  let label: String
  var enabled = true
  var doubleClick = false
  var onSelect: (() -> Void)? = nil
  var onDisclosure: ((Bool) -> Void)? = nil
  var onDoubleClick: (() -> Void)? = nil
  var onFocusChange: ((Bool) -> Void)? = nil
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
    button.disclosureHandler = onDisclosure
    button.doubleClickHandler = onDoubleClick
    button.focusHandler = onFocusChange
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
  var disclosureHandler: ((Bool) -> Void)?
  var doubleClickHandler: (() -> Void)?
  var focusHandler: ((Bool) -> Void)?
  private var pendingClick: DispatchWorkItem?
  override func becomeFirstResponder() -> Bool {
    let accepted = super.becomeFirstResponder()
    if accepted { focusHandler?(true) }
    return accepted
  }
  override func resignFirstResponder() -> Bool {
    let accepted = super.resignFirstResponder()
    if accepted { focusHandler?(false) }
    return accepted
  }
  override func viewWillMove(toWindow newWindow: NSWindow?) {
    if newWindow == nil { pendingClick?.cancel(); pendingClick = nil }
    super.viewWillMove(toWindow: newWindow)
  }
  override func mouseDown(with event: NSEvent) {
    guard isEnabled else { return }
    if let doubleClickHandler {
      window?.makeFirstResponder(self)
      selectionHandler?()
      pendingClick?.cancel()
      if event.clickCount == 2 {
        pendingClick = nil
        doubleClickHandler()
      } else if event.clickCount == 1 {
        let work = DispatchWorkItem { [weak self] in
          guard let self, isEnabled else { return }
          pendingClick = nil
          sendAction(action, to: target)
        }
        pendingClick = work
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: work)
      }
      return
    }
    guard requiredClicks == 2 else {
      super.mouseDown(with: event)
      return
    }
    window?.makeFirstResponder(self)
    selectionHandler?()
    if event.clickCount == 2 { sendAction(action, to: target) }
  }
  override func keyDown(with event: NSEvent) {
    pendingClick?.cancel()
    pendingClick = nil
    if isEnabled, event.keyCode == 120, let doubleClickHandler {
      selectionHandler?()
      doubleClickHandler()
    } else if isEnabled, let disclosureHandler, [123, 124].contains(event.keyCode) {
      selectionHandler?()
      disclosureHandler(event.keyCode == 124)
    } else if isEnabled && [36, 76, 49].contains(event.keyCode) {
      selectionHandler?()
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
