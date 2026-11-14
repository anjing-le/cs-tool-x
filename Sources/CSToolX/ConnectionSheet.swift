import AppKit
import ToolCore

@MainActor
final class ConnectionSheet: NSWindowController {
  private let engine: EngineClient
  private var profile: ConnectionProfile
  private let kinds = PaperSelect()
  private let environment = PaperSelect()
  private let nameField = Theme.field("例如：业务库 · 测试")
  private let hostField = Theme.field("主机")
  private let portField = Theme.field("端口")
  private let userField = Theme.field("用户名")
  private let databaseField = Theme.field("数据库")
  private let passwordField = Theme.secureField("登录密码")
  private let apiKeyField = Theme.secureField("ES API Key，可选，优先于密码")
  private let tls = Theme.checkbox("使用 TLS，并校验证书")
  private let remember = Theme.checkbox("保存登录凭据到本机")
  private let credentialsOnly: Bool
  private let saveProfile = Theme.checkbox("保存连接信息（不含密码）")
  private let message = Theme.label("", size: 11, muted: true)
  private var submit: NSButton!
  private var cancel: NSButton!
  private var busy = false
  var onConnected: ((ConnectionProfile, String, Int, Bool, ConnectionCredentials) -> Void)?
  init(
    engine: EngineClient, profile: ConnectionProfile? = nil,
    credentials: ConnectionCredentials? = nil, saveByDefault: Bool = true,
    credentialsOnly: Bool = false
  ) {
    self.engine = engine
    self.credentialsOnly = credentialsOnly
    self.profile = profile ?? ConnectionProfile()
    let window = CursorSheetWindow(
      contentRect: NSRect(x: 0, y: 0, width: 540, height: credentialsOnly ? 400 : 760),
      styleMask: [.borderless],
      backing: .buffered, defer: false)
    window.title = credentialsOnly ? "补充登录凭据" : "连接设置"
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
    let surface = PaperSurface()
    surface.wantsLayer = true
    surface.layer?.backgroundColor = Theme.paper.cgColor
    surface.layer?.cornerRadius = 14
    surface.layer?.borderWidth = 1
    surface.layer?.borderColor = Theme.line.withAlphaComponent(0.65).cgColor
    window.contentView = surface
    super.init(window: window)
    kinds.addItems(withTitles: DatabaseKind.allCases.map(\.title))
    kinds.onChange(target: self, action: #selector(kindChanged))
    kinds.selectItem(at: DatabaseKind.allCases.firstIndex(of: self.profile.kind) ?? 0)
    environment.addItems(withTitles: ["开发", "测试", "生产"])
    environment.selectItem(withTitle: self.profile.environment)
    passwordField.placeholderString = "登录密码"
    apiKeyField.placeholderString = "ES API Key，可选，优先于密码"
    saveProfile.state = saveByDefault && !credentialsOnly ? .on : .off
    remember.state = .on
    remember.toolTip = "本机明文文件，权限仅当前用户；不使用钥匙串"
    tls.isHidden = credentialsOnly
    saveProfile.isHidden = credentialsOnly
    cancel = Theme.button("取消", target: self, action: #selector(closeSheet))
    cancel.keyEquivalent = "\u{1b}"
    submit = Theme.button(
      credentialsOnly ? "打开" : "保存并打开", target: self, action: #selector(connect), primary: true)
    submit.keyEquivalent = "\r"
    let grid = NSGridView(
      views: credentialsOnly
        ? [[Theme.label("密码"), passwordField], [Theme.label("API Key"), apiKeyField]]
        : [
          [Theme.label("类型"), kinds], [Theme.label("连接名称"), nameField],
          [Theme.label("环境"), environment],
          [Theme.label("主机 / ES URL"), hostField], [Theme.label("端口"), portField],
          [Theme.label("数据库 / Redis DB"), databaseField], [Theme.label("用户名"), userField],
          [Theme.label("密码"), passwordField], [Theme.label("API Key"), apiKeyField],
        ])
    for row in 0..<grid.numberOfRows { grid.row(at: row).height = 34 }
    grid.heightAnchor.constraint(equalToConstant: credentialsOnly ? 74 : 354).isActive = true
    grid.rowSpacing = 6
    grid.columnSpacing = 18
    grid.xPlacement = .fill
    grid.yPlacement = .center
    grid.column(at: 0).width = 110
    grid.column(at: 1).width = 356
    let footer = Theme.stack([NSView(), cancel, submit], vertical: false)
    let root = Theme.stack(
      [
        Theme.label(
          credentialsOnly ? "登录 " + self.profile.displayName : "连接设置", size: 21, weight: .medium),
        Theme.label(credentialsOnly ? self.profile.address : "保存后，双击左侧即可打开", size: 11, muted: true),
        grid, tls, saveProfile, remember,
        message, NSView(), footer,
      ], spacing: 10)
    root.detachesHiddenViews = true
    Theme.pin(root, to: window.contentView!, inset: 24)
    for view in [grid, message, footer] {
      view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
    }
    message.maximumNumberOfLines = 2
    message.heightAnchor.constraint(equalToConstant: 24).isActive = true
    for (label, field) in [
      ("连接名称", nameField), ("主机 / ES URL", hostField), ("端口", portField),
      ("数据库 / Redis DB", databaseField), ("用户名", userField), ("密码", passwordField),
      ("API Key", apiKeyField),
    ] {
      field.setAccessibilityLabel(label)
    }
    kinds.setAccessibilityLabel("数据库类型")
    environment.setAccessibilityLabel("环境")
    let order: [NSView] = [
      kinds, nameField, environment, hostField, portField, databaseField, userField, passwordField,
      apiKeyField, tls, saveProfile, remember, cancel, submit,
    ]
    window.autorecalculatesKeyViewLoop = false
    for i in order.indices { order[i].nextKeyView = order[(i + 1) % order.count] }
    window.initialFirstResponder = credentialsOnly ? passwordField : nameField
    fill()
    passwordField.stringValue = credentials?.password ?? ""
    apiKeyField.stringValue = credentials?.apiKey ?? ""
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
    message.stringValue = ""
    fill()
  }
  @objc private func closeSheet() {
    guard !busy, let window else { return }
    kinds.dismissMenu()
    environment.dismissMenu()
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
    let persist = remember.state == .on
    busy = true
    submit.isEnabled = false
    cancel.isEnabled = false
    kinds.isEnabled = false
    message.stringValue = "正在测试连接…"
    Task { [weak self] in
      guard let self else { return }
      do {
        let profile = self.profile
        let credentialRevision = try await Task.detached {
          try DataCredentialStore().snapshot(for: profile).revision
        }.value
        let result = try await engine.connect(profile: profile, password: password, apiKey: apiKey)
        do {
          let authentication = ConnectionCredentials(password: password, apiKey: apiKey)
          try await Task.detached {
            if persist {
              try DataCredentialStore().save(
                authentication, for: profile, expectedRevision: credentialRevision)
            } else {
              try DataCredentialStore().remove(for: profile, expectedRevision: credentialRevision)
            }
          }.value
        } catch {
          try? await engine.disconnect(id: result.0)
          throw error
        }
        busy = false
        closeSheet()
        onConnected?(
          profile, result.0, result.1, save,
          ConnectionCredentials(password: password, apiKey: apiKey))
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
