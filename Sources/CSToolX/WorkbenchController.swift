import AppKit
import SwiftUI
import ToolCore

@MainActor
final class WorkbenchController: NSWindowController {
  private let engine: EngineClient
  private var profiles: [ConnectionProfile] = []
  private var temporary: [ConnectionProfile] = []
  private var dataViews: [UUID: DataWorkspace] = [:]
  private var catalogs: [UUID: QueryOutput] = [:]
  private var selectedProfile: UUID?
  private var selectedModule: ToolModule?
  private var shellModel: Workspace?
  private var shellHost: NSHostingView<WorkspaceView>?
  private var fileView: TerminalWorkspace?
  private var sftpSheet: NSWindow?
  private var homeHost: NSHostingView<LauncherView>?
  private var connectionSheet: ConnectionSheet?
  private let root = WorkbenchSurface()
  private let body = NSView()
  private let dataContent = NSView()
  private let dataRoot = NSView()
  private var header: NSStackView!
  private var headerHeight: NSLayoutConstraint!
  private let title = Theme.label("", size: 11, muted: true)
  private let connectionList = TextTable(headers: ["连接"], widths: [205], header: false)
  private let objectList = TextTable(headers: ["对象"], widths: [205], header: false)
  private let footer = Theme.label("凭据仅在本次会话保留", size: 10, muted: true)
  var onCheckUpdates: (() -> Void)?
  init(engine: EngineClient) {
    self.engine = engine
    let window = WorkbenchWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820))
    window.title = "cs-tool-x"
    window.minSize = NSSize(width: 980, height: 680)
    window.center()
    window.appearance = NSAppearance(named: .aqua)
    super.init(window: window)
    root.wantsLayer = true
    root.layer?.backgroundColor = Theme.paper.cgColor
    window.contentView = root
    let back = Theme.button("‹", target: self, action: #selector(goHome))
    back.setAccessibilityLabel("返回首页")
    back.toolTip = "返回首页 ⌘1"
    let update = Theme.button("↻", target: self, action: #selector(checkUpdates))
    update.setAccessibilityLabel("检查更新")
    update.toolTip = "检查更新"
    header = Theme.stack([back, title, NSView(), update], vertical: false, spacing: 12)
    header.edgeInsets = NSEdgeInsets(top: 8, left: 20, bottom: 8, right: 20)
    headerHeight = header.heightAnchor.constraint(equalToConstant: 43)
    headerHeight.isActive = true
    for view in [header!, body] {
      view.translatesAutoresizingMaskIntoConstraints = false
      root.addSubview(view)
    }
    NSLayoutConstraint.activate([
      header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      header.topAnchor.constraint(equalTo: root.topAnchor),
      body.leadingAnchor.constraint(equalTo: root.leadingAnchor),
      body.trailingAnchor.constraint(equalTo: root.trailingAnchor),
      body.topAnchor.constraint(equalTo: header.bottomAnchor),
      body.bottomAnchor.constraint(equalTo: root.bottomAnchor),
    ])
    root.installDragRegion()
    prepareDataModule()
    connectionList.onSelect = { [weak self] row in self?.selectProfile(row) }
    objectList.onSelect = { [weak self] row in
      guard let self, let id = selectedProfile, let catalog = catalogs[id], row < catalog.rows.count
      else { return }
      dataViews[id]?.preview(catalog.rows[row])
    }
    goHome()
    Task { [weak self] in
      let result = await Task.detached { Result { try ProfileStore().load() } }.value
      guard let self else { return }
      switch result {
      case .success(let loaded):
        profiles = loaded
        refreshConnections()
      case .failure(let error): Theme.error(error, window: window)
      }
    }
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  private func prepareDataModule() {
    let context = NSView()
    context.wantsLayer = true
    context.layer?.backgroundColor = Theme.sidebar.cgColor
    let add = Theme.button("＋", target: self, action: #selector(newConnection))
    add.toolTip = "新建数据连接"
    let heading = Theme.stack(
      [Theme.label("数据", size: 17, weight: .medium), NSView(), add], vertical: false)
    let side = Theme.stack(
      [
        heading, Theme.label("连接", size: 10, muted: true), connectionList.scroll, Theme.separator(),
        Theme.label("表 / 索引 / Keys", size: 11, muted: true), objectList.scroll, footer,
      ], spacing: 14)
    Theme.pin(side, to: context, inset: 16)
    for view in [heading, connectionList.scroll, objectList.scroll, footer] {
      view.widthAnchor.constraint(equalTo: side.widthAnchor).isActive = true
    }
    context.widthAnchor.constraint(equalToConstant: 245).isActive = true
    connectionList.scroll.heightAnchor.constraint(equalToConstant: 200).isActive = true
    for view in [context, dataContent] {
      view.translatesAutoresizingMaskIntoConstraints = false
      dataRoot.addSubview(view)
    }
    NSLayoutConstraint.activate([
      context.leadingAnchor.constraint(equalTo: dataRoot.leadingAnchor),
      context.topAnchor.constraint(equalTo: dataRoot.topAnchor),
      context.bottomAnchor.constraint(equalTo: dataRoot.bottomAnchor),
      dataContent.leadingAnchor.constraint(equalTo: context.trailingAnchor, constant: 1),
      dataContent.trailingAnchor.constraint(equalTo: dataRoot.trailingAnchor),
      dataContent.topAnchor.constraint(equalTo: dataRoot.topAnchor),
      dataContent.bottomAnchor.constraint(equalTo: dataRoot.bottomAnchor),
    ])
  }

  private var listedProfiles: [ConnectionProfile] {
    profiles + temporary.filter { p in !profiles.contains(where: { $0.id == p.id }) }
  }
  private func display(_ view: NSView, in container: NSView) {
    container.subviews.forEach { $0.removeFromSuperview() }
    Theme.pin(view, to: container)
  }
  @objc func goHome() {
    selectedModule = nil
    header.isHidden = true
    headerHeight.constant = 0
    if homeHost == nil {
      homeHost = NSHostingView(rootView: LauncherView { [weak self] in self?.showModule($0) })
    }
    display(homeHost!, in: body)
  }
  private func showModule(_ module: ToolModule) {
    selectedModule = module
    header.isHidden = false
    headerHeight.constant = 43
    title.stringValue = module == .terminal ? "" : module.title
    switch module {
    case .data:
      display(dataRoot, in: body)
      refreshConnections()
      refreshObjects()
      if let id = selectedProfile, let view = dataViews[id] {
        display(view, in: dataContent)
      } else {
        dataWelcome()
      }
    case .terminal:
      if shellModel == nil { shellModel = Workspace() }
      if shellHost == nil {
        shellHost = NSHostingView(
          rootView: WorkspaceView(
            model: shellModel!, openFiles: { [weak self] in self?.showShellFiles() }))
      }
      display(shellHost!, in: body)
    case .files:
      if fileView == nil { fileView = TerminalWorkspace(sftp: true) }
      display(fileView!, in: body)
    default: break
    }
  }
  private func showShellFiles() {
    guard let window, window.attachedSheet == nil, let server = shellModel?.active?.server else {
      return
    }
    guard !server.local else {
      shellModel?.message("先在左侧选择远程服务器，再打开 SFTP。")
      return
    }
    let panel = WorkbenchWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 650))
    panel.title = "Shell 文件传输"
    panel.appearance = NSAppearance(named: .aqua)
    panel.isReleasedWhenClosed = false
    let workspace = TerminalWorkspace(sftp: true, server: server)
    fileView = workspace
    let close = Theme.button("返回 Shell", target: self, action: #selector(closeShellFiles))
    let layout = Theme.stack([workspace, close], spacing: 10)
    layout.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 16, right: 20)
    Theme.pin(layout, to: panel.contentView!)
    workspace.widthAnchor.constraint(equalTo: layout.widthAnchor).isActive = true
    sftpSheet = panel
    window.beginSheet(panel)
  }
  @objc private func closeShellFiles() {
    guard let panel = sftpSheet else { return }
    fileView?.stop()
    window?.endSheet(panel)
    panel.orderOut(nil)
    sftpSheet = nil
    fileView = nil
  }
  private func refreshConnections() {
    connectionList.update(
      listedProfiles.map { ["\(dataViews[$0.id] == nil ? "○" : "●") \($0.displayName)"] })
  }
  private func refreshObjects() {
    guard let id = selectedProfile, let catalog = catalogs[id] else {
      objectList.update([])
      return
    }
    let kind = dataViews[id]?.profile.kind
    objectList.update(
      catalog.rows.map { row in
        if kind == .mysql || kind == .pg, row.count >= 2 {
          return ["\(row[0].text).\(row[1].text)"]
        }
        return [row.first?.text ?? ""]
      })
  }
  private func selectProfile(_ row: Int) {
    guard row < listedProfiles.count else { return }
    let profile = listedProfiles[row]
    if let view = dataViews[profile.id] {
      selectedProfile = profile.id
      display(view, in: dataContent)
      refreshObjects()
    } else {
      showConnection(profile: profile)
    }
  }
  private func dataWelcome() {
    let view = NSView()
    let stack = Theme.stack(
      [
        Theme.label("数据", size: 26, weight: .medium),
        Theme.label("MySQL / PostgreSQL / Elasticsearch / Redis", size: 12, muted: true),
        Theme.button("新建连接 ↗", target: self, action: #selector(newConnection), primary: true),
      ], spacing: 24)
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])
    display(view, in: dataContent)
  }
  @objc private func newConnection() { showConnection(profile: nil) }
  private func showConnection(profile: ConnectionProfile?) {
    guard let window, window.attachedSheet == nil else { return }
    guard dataViews.count < 4 else {
      Theme.error(ToolError.message("最多同时保留 4 个数据会话，请先断开一个。"), window: window)
      return
    }
    let sheet = ConnectionSheet(engine: engine, profile: profile)
    connectionSheet = sheet
    sheet.onConnected = { [weak self] profile, id, elapsed, save, _ in
      guard let self else { return }
      let workspace = DataWorkspace(
        profile: profile, sessionID: id, elapsed: elapsed, engine: engine)
      dataViews[profile.id] = workspace
      selectedProfile = profile.id
      workspace.onCatalog = { [weak self] output in
        self?.catalogs[profile.id] = output
        self?.refreshObjects()
      }
      workspace.onDisconnect = { [weak self] in self?.closed(profile.id) }
      if save {
        profiles.removeAll { $0.id == profile.id }
        profiles.append(profile)
        let snapshot = profiles
        Task {
          do { try await Task.detached { try ProfileStore().save(snapshot) }.value } catch {
            Theme.error(
              ToolError.message("已连接，但配置保存失败：\(error.localizedDescription)"), window: window)
          }
        }
      } else {
        temporary.removeAll { $0.id == profile.id }
        temporary.append(profile)
      }
      refreshConnections()
      refreshObjects()
      display(workspace, in: dataContent)
      connectionSheet = nil
    }
    window.beginSheet(sheet.window!)
  }
  private func closed(_ id: UUID) {
    dataViews.removeValue(forKey: id)
    catalogs.removeValue(forKey: id)
    temporary.removeAll { $0.id == id }
    if selectedProfile == id { selectedProfile = nil }
    refreshConnections()
    refreshObjects()
    if let selectedProfile, let active = dataViews[selectedProfile] {
      display(active, in: dataContent)
    } else {
      dataWelcome()
    }
    if dataViews.isEmpty { Task { await engine.stop() } }
  }
  @objc private func checkUpdates() { onCheckUpdates?() }
  func newShellTab() {
    showModule(.terminal)
    shellModel?.newTab()
  }
  func closeShellTab() {
    if selectedModule == .terminal, let id = shellModel?.selected {
      shellModel?.close(id)
    } else {
      window?.performClose(nil)
    }
  }
  func splitShell(vertical: Bool) {
    guard selectedModule == .terminal else { return }
    shellModel?.active?.split(vertical: vertical)
  }
  func cycleShell(_ delta: Int) {
    guard selectedModule == .terminal else { return }
    shellModel?.cycle(delta)
  }
  func handleEscape() -> Bool {
    guard selectedModule == .terminal, let shellModel else { return false }
    if shellModel.sidebarPanel != nil {
      shellModel.sidebarPanel = nil
      return true
    }
    if shellModel.settings {
      shellModel.settings = false
      return true
    }
    return false
  }
  func stopAll() {
    shellModel?.stop()
    fileView?.stop()
    Task { await engine.stop() }
  }
}
