import AppKit
import ToolCore

@MainActor
final class ConnectionSheet: NSWindowController {
  private let engine: EngineClient
  private var profile: ConnectionProfile
  private let kinds = NSPopUpButton()
  private let environment = NSPopUpButton()
  private let nameField = Theme.field("例如：业务库 · 测试")
  private let hostField = Theme.field("主机")
  private let portField = Theme.field("端口")
  private let userField = Theme.field("用户名")
  private let databaseField = Theme.field("数据库")
  private let passwordField = NSSecureTextField()
  private let apiKeyField = NSSecureTextField()
  private let tls = NSButton(checkboxWithTitle: "使用 TLS，并校验证书", target: nil, action: nil)
  private let saveProfile = NSButton(checkboxWithTitle: "保存连接信息（不含密码）", target: nil, action: nil)
  private let message = Theme.label("", size: 11, muted: true)
  private var submit: NSButton!
  private var cancel: NSButton!
  private var busy = false
  var onConnected: ((ConnectionProfile, String, Int, Bool, String?) -> Void)?
  init(engine: EngineClient, profile: ConnectionProfile? = nil) {
    self.engine = engine
    self.profile = profile ?? ConnectionProfile()
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 540, height: 735), styleMask: [.titled],
      backing: .buffered, defer: false)
    window.title = "新建数据连接"
    super.init(window: window)
    kinds.addItems(withTitles: DatabaseKind.allCases.map(\.title))
    kinds.target = self
    kinds.action = #selector(kindChanged)
    kinds.selectItem(at: DatabaseKind.allCases.firstIndex(of: self.profile.kind) ?? 0)
    environment.addItems(withTitles: ["开发", "测试", "生产"])
    environment.selectItem(withTitle: self.profile.environment)
    passwordField.placeholderString = "仅在本次会话保留"
    apiKeyField.placeholderString = "ES API Key，可选，优先于密码"
    saveProfile.state = .on
    cancel = Theme.button("取消", target: self, action: #selector(closeSheet))
    cancel.keyEquivalent = "\u{1b}"
    submit = Theme.button("测试并连接", target: self, action: #selector(connect), primary: true)
    submit.keyEquivalent = "\r"
    let grid = NSGridView(views: [
      [Theme.label("类型"), kinds], [Theme.label("连接名称"), nameField],
      [Theme.label("环境"), environment],
      [Theme.label("主机 / ES URL"), hostField], [Theme.label("端口"), portField],
      [Theme.label("数据库 / Redis DB"), databaseField], [Theme.label("用户名"), userField],
      [Theme.label("密码"), passwordField], [Theme.label("API Key"), apiKeyField],
    ])
    grid.rowSpacing = 12
    grid.columnSpacing = 18
    grid.xPlacement = .fill
    grid.yPlacement = .center
    grid.column(at: 0).width = 110
    grid.column(at: 1).width = 345
    let footer = Theme.stack([NSView(), cancel, submit], vertical: false)
    let root = Theme.stack(
      [
        Theme.label("连接你的数据", size: 21, weight: .medium),
        Theme.label("本地直连 · 连接后不自动扫描", size: 11, muted: true), grid, tls, saveProfile,
        message, NSView(), footer,
      ], spacing: 12)
    Theme.pin(root, to: window.contentView!, inset: 28)
    for view in [grid, message, footer] {
      view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
    }
    message.maximumNumberOfLines = 3
    fill()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  private func fill() {
    nameField.stringValue = profile.name
    hostField.stringValue = profile.kind == .es ? profile.endpoint : profile.host
    portField.stringValue = String(profile.port)
    userField.stringValue = profile.username
    databaseField.stringValue = profile.database
    tls.state = profile.tls ? .on : .off
    portField.isEnabled = profile.kind != .es
    databaseField.isEnabled = profile.kind != .es
    tls.isEnabled = profile.kind != .es
    apiKeyField.isEnabled = profile.kind == .es
  }
  @objc private func kindChanged() {
    let id = profile.id
    let name = nameField.stringValue
    profile = ConnectionProfile(kind: DatabaseKind.allCases[kinds.indexOfSelectedItem])
    profile.id = id
    profile.name = name
    passwordField.stringValue = ""
    apiKeyField.stringValue = ""
    fill()
  }
  @objc private func closeSheet() {
    guard !busy, let window else { return }
    window.sheetParent?.endSheet(window)
    window.orderOut(nil)
    passwordField.stringValue = ""
    apiKeyField.stringValue = ""
  }
  @objc private func connect() {
    guard !busy else { return }
    profile.kind = DatabaseKind.allCases[kinds.indexOfSelectedItem]
    profile.name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    profile.environment = environment.titleOfSelectedItem ?? "开发"
    if profile.kind == .es {
      profile.endpoint = hostField.stringValue
    } else {
      profile.host = hostField.stringValue
    }
    profile.port = Int(portField.stringValue) ?? 0
    profile.database = databaseField.stringValue
    profile.username = userField.stringValue
    profile.tls = tls.state == .on
    do { try profile.validate() } catch {
      message.stringValue = error.localizedDescription
      return
    }
    let password = passwordField.stringValue
    let apiKey = apiKeyField.stringValue
    let save = saveProfile.state == .on
    busy = true
    submit.isEnabled = false
    cancel.isEnabled = false
    kinds.isEnabled = false
    message.stringValue = "正在测试连接…"
    Task { [weak self] in
      guard let self else { return }
      do {
        let result = try await engine.connect(profile: profile, password: password, apiKey: apiKey)
        busy = false
        closeSheet()
        onConnected?(profile, result.0, result.1, save, nil)
      } catch {
        busy = false
        submit.isEnabled = true
        cancel.isEnabled = true
        kinds.isEnabled = true
        message.stringValue = error.localizedDescription
      }
    }
  }
}
