import AppKit
import SwiftTerm

/// Forward PTY I/O and sizing while denying unsolicited OSC clipboard access.
final class TerminalGate: TerminalViewDelegate {
  weak var terminal: LocalProcessTerminalView?
  init(_ terminal: LocalProcessTerminalView) { self.terminal = terminal }
  func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
    terminal?.sizeChanged(source: source, newCols: newCols, newRows: newRows)
  }
  func setTerminalTitle(source: TerminalView, title: String) {
    terminal?.setTerminalTitle(source: source, title: title)
  }
  func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
    terminal?.hostCurrentDirectoryUpdate(source: source, directory: directory)
  }
  func send(source: TerminalView, data: ArraySlice<UInt8>) {
    terminal?.send(source: source, data: data)
  }
  func scrolled(source: TerminalView, position: Double) {
    terminal?.scrolled(source: source, position: position)
  }
  func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
    terminal?.rangeChanged(source: source, startY: startY, endY: endY)
  }
  func clipboardCopy(source: TerminalView, content: Data) {}
  func clipboardRead(source: TerminalView) -> Data? { nil }
  func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
    guard let url = URL(string: link), ["https", "http"].contains(url.scheme?.lowercased() ?? "")
    else { return }
    NSWorkspace.shared.open(url)
  }
}
