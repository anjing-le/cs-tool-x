import AppKit
import SwiftTerm
import SwiftUI
import ToolCore

@MainActor
final class RealTerminal: ObservableObject, Identifiable, LocalProcessTerminalViewDelegate {
  let id = UUID()
  let server: Server
  @Published var status = "准备连接"
  private var view: LocalProcessTerminalView?
  private var gate: TerminalGate?
  private var stopped = false
  init(server: Server) { self.server = server }
  func terminalView() -> LocalProcessTerminalView {
    if let view { return view }
    let terminal = CursorTerminalView(frame: NSRect(x: 0, y: 0, width: 700, height: 400))
    let gate = TerminalGate(terminal)
    self.gate = gate
    terminal.terminalDelegate = gate
    terminal.processDelegate = self
    terminal.nativeBackgroundColor = Theme.paper
    terminal.nativeForegroundColor = Theme.ink
    terminal.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
    terminal.getTerminal().changeHistorySize(2000)
    self.view = terminal
    guard !stopped else { return terminal }
    do {
      let executable: String
      let args: [String]
      if server.local {
        executable = "/bin/zsh"
        args = ["-l"]
      } else {
        executable = "/usr/bin/ssh"
        args = try SSHCommand.arguments(
          host: server.host, user: server.user, port: String(server.port), sftp: false)
      }
      terminal.startProcess(
        executable: executable, args: args,
        currentDirectory: FileManager.default.homeDirectoryForCurrentUser.path)
      status = server.local ? "本地终端" : "SSH · 正在连接或等待认证"
    } catch { status = error.localizedDescription }
    return terminal
  }
  func stop() {
    stopped = true
    view?.processDelegate = nil
    view?.terminate()
    view?.removeFromSuperview()
    view = nil
    gate = nil
    status = "已断开"
  }
  nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
  nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
  nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
  nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
    Task { @MainActor [weak self, weak source] in
      guard let self, let source, source === view else { return }
      status = "会话已退出 · \(exitCode.map(String.init) ?? "未知状态")"
    }
  }
}
struct LiveTerminalView: NSViewRepresentable {
  let terminal: RealTerminal
  func makeNSView(context: Context) -> NSView { NSView() }
  func updateNSView(_ holder: NSView, context: Context) {
    let view = terminal.terminalView()
    if view.superview !== holder { Theme.pin(view, to: holder) }
  }
  // Removing a view for tab switching or returning home keeps the explicit
  // session alive. Closing a pane/tab or quitting owns process termination.
}
