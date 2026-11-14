import AppKit
import SwiftTerm
import ToolCore

@MainActor
final class TerminalWorkspace: NSView, LocalProcessTerminalViewDelegate {
  private let sftp: Bool
  private let savedServer: Server?
  private let passwordDisplay = Theme.field("未保存密码，使用交互认证")
  private let host = Theme.field("SSH Host 别名或地址")
  private let user = Theme.field("用户名，可留空使用 SSH 配置")
  private let port = Theme.field("22")
  private let status = Theme.label("尚未连接", size: 11, muted: true)
  private var terminal: LocalProcessTerminalView?
  private var gate: TerminalGate?
  private let container = NSView()
  private var startButton: NSButton!
  private var localButton: NSButton!
  private var stopButton: NSButton!
  private(set) var running = false
  init(sftp: Bool, server: Server? = nil) {
    self.sftp = sftp
    self.savedServer = server
    super.init(frame: .zero)
    port.stringValue = String(server?.port ?? 22)
    host.stringValue = server?.host ?? ""
    user.stringValue = server?.user ?? ""
    startButton = Theme.button(
      sftp ? "连接 SFTP" : "连接 SSH", target: self, action: #selector(connect), primary: true)
    localButton = Theme.button("本地终端", target: self, action: #selector(local))
    localButton.isHidden = sftp
    stopButton = Theme.button("断开", target: self, action: #selector(stop))
    stopButton.isEnabled = false
    passwordDisplay.stringValue = server?.password ?? ""
    passwordDisplay.isEditable = false
    passwordDisplay.isSelectable = true
    passwordDisplay.setAccessibilityLabel("密码 · 本机明文")
    let credentials = Theme.stack(
      [Theme.label("密码 · 本机明文"), passwordDisplay], vertical: false, spacing: 12)
    credentials.isHidden = (server?.password ?? "").isEmpty
    let title = Theme.label(sftp ? "SFTP 控制台" : "终端", size: 23, weight: .medium)
    let subtitle = Theme.label(
      sftp ? "基于系统 sftp；图形化目录与传输队列正在规划。" : "使用系统 OpenSSH、SSH 配置与 Agent；主机指纹由你确认。", size: 11,
      muted: true)
    let fields = Theme.stack(
      [host, user, port, startButton, localButton, stopButton], vertical: false, spacing: 9)
    port.widthAnchor.constraint(equalToConstant: 64).isActive = true
    user.widthAnchor.constraint(equalToConstant: 180).isActive = true
    let root = Theme.stack(
      [title, subtitle, Theme.separator(), fields, credentials, container, status], spacing: 17)
    Theme.pin(root, to: self, inset: 26)
    for view in [subtitle, fields, credentials, container, status] {
      view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
    }
    if server != nil {
      host.isEnabled = false
      user.isEnabled = false
      port.isEnabled = false
    }
    container.heightAnchor.constraint(greaterThanOrEqualToConstant: 250).isActive = true
    let hint = Theme.label(
      sftp ? "连接后使用 ls、cd、get、put。" : "连接 SSH，或打开一个本地终端。", size: 13, muted: true)
    hint.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(hint)
    NSLayoutConstraint.activate([
      hint.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      hint.centerYAnchor.constraint(equalTo: container.centerYAnchor),
    ])
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  @objc private func connect() {
    guard !running else { return }
    do {
      let args = try SSHCommand.arguments(
        host: host.stringValue, user: user.stringValue, port: port.stringValue, sftp: sftp,
        passwordAuthentication: !(savedServer?.password ?? "").isEmpty)
      launch(executable: sftp ? "/usr/bin/sftp" : "/usr/bin/ssh", args: args)
    } catch { Theme.error(error, window: window) }
  }
  @objc private func local() {
    guard !running else { return }
    launch(executable: "/bin/zsh", args: ["-l"])
  }
  private func launch(executable: String, args: [String]) {
    let environment: [String]?
    do {
      if let savedServer {
        environment = try ShellAuthentication.environment(for: savedServer)
      } else {
        environment = nil
      }
    } catch {
      Theme.error(error, window: window)
      return
    }
    let terminal = CursorTerminalView(frame: container.bounds)
    let gate = TerminalGate(terminal)
    self.gate = gate
    terminal.terminalDelegate = gate
    terminal.processDelegate = self
    terminal.nativeBackgroundColor = Theme.paper
    terminal.nativeForegroundColor = Theme.ink
    terminal.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
    // Bounded scrollback; no session recording or idle screen polling.
    terminal.getTerminal().changeHistorySize(2000)
    container.subviews.forEach { $0.removeFromSuperview() }
    Theme.pin(terminal, to: container)
    self.terminal = terminal
    running = true
    startButton.isEnabled = false
    localButton.isEnabled = false
    stopButton.isEnabled = true
    host.isEnabled = false
    user.isEnabled = false
    port.isEnabled = false
    status.stringValue = "会话运行中 · 输出仅保留在内存"
    terminal.startProcess(
      executable: executable, args: args,
      environment: environment,
      currentDirectory: FileManager.default.homeDirectoryForCurrentUser.path)
    window?.makeFirstResponder(terminal)
  }
  @objc func stop() {
    terminal?.terminate()
    terminal?.processDelegate = nil
    terminal?.removeFromSuperview()
    terminal = nil
    gate = nil
    running = false
    startButton.isEnabled = true
    localButton.isEnabled = true
    stopButton.isEnabled = false
    host.isEnabled = savedServer == nil
    user.isEnabled = savedServer == nil
    port.isEnabled = savedServer == nil
    status.stringValue = "会话已结束"
  }
  nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
  nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
  nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
  nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
    Task { @MainActor [weak self, weak source] in
      guard let self, let source, source === terminal else { return }
      running = false
      startButton.isEnabled = true
      localButton.isEnabled = true
      stopButton.isEnabled = true
      host.isEnabled = savedServer == nil
      user.isEnabled = savedServer == nil
      port.isEnabled = savedServer == nil
      status.stringValue = "会话已退出 · \(exitCode.map(String.init) ?? "未知状态")"
    }
  }
}
