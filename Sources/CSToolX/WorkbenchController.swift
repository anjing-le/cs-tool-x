import AppKit
import SwiftUI
import ToolCore

@MainActor
final class WorkbenchController: NSWindowController {
  private let engine: EngineClient
  private var profiles: [ConnectionProfile] = []
  private var profileRevision = ConfigurationFile.missingRevision
  private var profileSaveTask: Task<Void, Never>?
  private var profileSaveSerial = 0
  private var reloadSerial = 0
  private var temporary: [ConnectionProfile] = []
  private var dataViews: [UUID: DataWorkspace] = [:]
  private var credentials: [String: ConnectionCredentials] = [:]
  private let navigator = DataNavigator()
  private let connectionPicker = PaperSelect()
  private var selectedConnectionID: String?
  private var connectionChoices: [ConnectionGroup] = []
  private var browser: DataBrowser?
  private var browserNodeID: String?
  private var browseContexts: [UUID: String] = [:]
  private var discoveryProfiles: [String: ConnectionProfile] = [:]
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
    navigator.onSelect = { [weak self] node in self?.selectedTreeNode(node) }
    navigator.onExpand = { [weak self] node in self?.expandedTreeNode(node) }
    navigator.onActivate = { [weak self] node in self?.activateTreeNode(node) }
    goHome()
    reloadConfiguration()
  }
  func reloadConfiguration() {
    guard window?.attachedSheet == nil, profileSaveTask == nil else { return }
    shellModel?.reloadConfiguration()
    reloadSerial += 1
    let generation = reloadSerial
    let current = profileSaveSerial
    Task { [weak self] in
      let result = await Task.detached { Result { try ProfileStore().snapshot() } }.value
      guard let self, window?.attachedSheet == nil, profileSaveTask == nil,
        profileSaveSerial == current, reloadSerial == generation
      else { return }
      switch result {
      case .success(let loaded):
        profiles = loaded.value
        profileRevision = loaded.revision
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
    connectionPicker.setAccessibilityLabel("切换数据连接")
    connectionPicker.onChange(target: self, action: #selector(selectConnection))
    connectionPicker.widthAnchor.constraint(greaterThanOrEqualToConstant: 210).isActive = true
    let heading = Theme.stack([connectionPicker, NSView(), add], vertical: false)
    let side = Theme.stack(
      [
        heading, Theme.label("连接 / 库 / Schema / 对象", size: 10, muted: true), navigator.scroll,
        footer,
      ], spacing: 14)
    Theme.pin(side, to: context, inset: 16)
    for view in [heading, navigator.scroll, footer] {
      view.widthAnchor.constraint(equalTo: side.widthAnchor).isActive = true
    }
    context.widthAnchor.constraint(equalToConstant: 330).isActive = true
    navigator.scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
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
      if dataContent.subviews.isEmpty {
        if let id = selectedConnectionID, let root = navigator.root(id) {
          showTreeOverview(root)
        } else {
          dataWelcome()
        }
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
    let groups = ConnectionGroup.build(listedProfiles)
    navigator.update(groups)
    connectionChoices = groups
    connectionPicker.dismissMenu()
    connectionPicker.addItems(
      withTitles: groups.map { group in
        group.profiles.first?.name.isEmpty == false
          ? group.profiles[0].name : group.identity.kind.title
      })
    if !groups.contains(where: { $0.id == selectedConnectionID }) {
      selectedConnectionID = groups.first?.id
    }
    if let index = groups.firstIndex(where: { $0.id == selectedConnectionID }) {
      connectionPicker.selectItem(at: index)
    }
    navigator.filterConnection(selectedConnectionID)
    footer.stringValue = "\(groups.count) 个连接"
    if let browser, dataContent.subviews.contains(where: { $0 === browser }) {
      if let id = browserNodeID, let node = navigator.node(id) { showTreeOverview(node) }
      else if let id = selectedConnectionID, let root = navigator.root(id) { showTreeOverview(root) }
    }
  }
  @objc private func selectConnection() {
    let index = connectionPicker.indexOfSelectedItem
    guard connectionChoices.indices.contains(index) else { return }
    let id = connectionChoices[index].id
    selectedConnectionID = id
    selectedProfile =
      dataViews.values.first(where: { ConnectionIdentity($0.profile).id == id })?.profile.id
    navigator.filterConnection(id)
    if let root = navigator.root(id) {
      navigator.expand(root)
      showTreeOverview(root)
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
  private func showConnection(profile: ConnectionProfile?, browse: DataTreeNode? = nil) {
    guard let window, window.attachedSheet == nil else { return }
    if let profile, dataViews[profile.id] != nil {
      Theme.error(ToolError.message("请先断开当前会话，再修改连接设置。"), window: window)
      return
    }
    guard dataViews.count < 4 else {
      Theme.error(ToolError.message("最多同时保留 4 个数据会话，请先断开一个。"), window: window)
      return
    }
    let sheet = ConnectionSheet(
      engine: engine, profile: profile,
      credentials: profile.flatMap { credentials[$0.credentialScope] },
      saveByDefault: profile == nil || profiles.contains(where: { $0.id == profile?.id }))
    connectionSheet = sheet
    sheet.onConnected = { [weak self] profile, id, elapsed, save, authentication in
      guard let self else { return }
      let workspace = DataWorkspace(
        profile: profile, sessionID: id, elapsed: elapsed, engine: engine)
      credentials[profile.credentialScope] = authentication
      dataViews[profile.id] = workspace
      selectedProfile = profile.id
      selectedConnectionID = ConnectionIdentity(profile).id
      workspace.onBrowse = { [weak self] in self?.browseWorkspace(profile) }
      workspace.onDisconnect = { [weak self] in self?.closed(profile.id) }
      if save {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
          profiles[index] = profile
        } else {
          profiles.append(profile)
        }
        let snapshot = profiles
        profileSaveSerial += 1
        let saveSerial = profileSaveSerial
        let previous = profileSaveTask
        profileSaveTask = Task {
          await previous?.value
          let expected = self.profileRevision
          do {
            self.profileRevision = try await Task.detached {
              try ProfileStore().save(snapshot, expectedRevision: expected)
            }.value
          } catch {
            Theme.error(
              ToolError.message("已连接，但配置保存失败：\(error.localizedDescription)"), window: window)
          }
          if self.profileSaveSerial == saveSerial { self.profileSaveTask = nil }
        }
      } else {
        temporary.removeAll { $0.id == profile.id }
        temporary.append(profile)
      }
      refreshConnections()
      display(workspace, in: dataContent)
      connectionSheet = nil
      if let browse, let current = navigator.node(browse.id) {
        navigator.expand(current)
        loadTree(current, workspace: workspace)
      }
    }
    window.beginSheet(sheet.window!)
  }
  private func closed(_ id: UUID) {
    browseContexts.removeValue(forKey: id)
    let groupID = dataViews[id].map { ConnectionIdentity($0.profile).id }
    dataViews.removeValue(forKey: id)
    if let groupID,
      !dataViews.values.contains(where: { ConnectionIdentity($0.profile).id == groupID })
    {
      credentials = credentials.filter { !$0.key.hasPrefix(groupID + ":") }
      navigator.invalidateGroup(groupID)
      discoveryProfiles = discoveryProfiles.filter { !$0.key.hasPrefix(groupID + ":") }
    }
    temporary.removeAll { $0.id == id }
    if selectedProfile == id { selectedProfile = nil }
    refreshConnections()
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
    credentials.removeAll()
    shellModel?.stop()
    fileView?.stop()
    Task { await engine.stop() }
  }
}

extension WorkbenchController {
  private func selectedTreeNode(_ node: DataTreeNode) {
    if [.table, .index, .key, .more].contains(node.kind) {
      activateTreeNode(node)
      return
    }
    showTreeOverview(node)
  }
  private func expandedTreeNode(_ node: DataTreeNode) {
    guard !node.loaded, !node.loading else { return }
    if node.kind == .connection, node.profile?.kind != .es { return }
    activateTreeNode(node)
  }
  private func activateTreeNode(_ node: DataTreeNode) {
    if node.kind == .message { return }
    if node.kind == .more, let parentID = node.parentID, let parent = navigator.node(parentID) {
      if let profile = parent.profile, let workspace = dataViews[profile.id] {
        loadTree(parent, workspace: workspace, cursor: node.cursor)
      }
      return
    }
    guard let profile = node.profile else { return }
    let workspace =
      node.kind == .connection
      ? dataViews.values.first(where: { ConnectionIdentity($0.profile).id == node.groupID })
      : dataViews[profile.id]
    if let workspace {
      guard node.kind == .connection || workspace.profile == profile else {
        Theme.error(ToolError.message("该配置已修改，请先断开旧会话后重新连接。"), window: window)
        return
      }
      selectedProfile = workspace.profile.id
      display(workspace, in: dataContent)
      if node.expandable { navigator.expand(node) }
      loadTree(node, workspace: workspace)
    } else {
      showConnection(profile: profile, browse: node)
    }
  }
  private func browseWorkspace(_ profile: ConnectionProfile) {
    if let id = browseContexts[profile.id], let node = navigator.node(id) {
      navigator.expand(node)
      showTreeOverview(node)
      return
    }
    let rootID = ConnectionIdentity(profile).id
    guard let root = navigator.root(rootID) else { return }
    if profile.kind == .es {
      activateTreeNode(root)
      return
    }
    if let node = root.children.first(where: { $0.profile?.database == profile.database }) {
      activateTreeNode(node)
    }
  }
  private func showTreeOverview(_ node: DataTreeNode) {
    if browserNodeID != node.id {
      browser = DataBrowser(frame: .zero)
      browserNodeID = node.id
    }
    guard let browser else { return }
    browser.onOpen = { [weak self] child in self?.activateTreeNode(child) }
    browser.onRefresh = { [weak self, weak node] in
      guard let node else { return }
      self?.activateTreeNode(node)
    }
    browser.onBack = { [weak self, weak node] in
      guard let self, let id = node?.parentID, let parent = navigator.node(id) else { return }
      showTreeOverview(parent)
    }
    browser.onQuery = { [weak self, weak node] in
      guard let self, let node, let profile = node.profile else { return }
      let active = dataViews[profile.id]
      if let active {
        selectedProfile = active.profile.id
        active.showQuery()
        display(active, in: dataContent)
      } else {
        showConnection(profile: profile)
      }
    }
    browser.onEdit = { [weak self, weak node] in
      guard let profile = node?.profile else { return }
      self?.showConnection(profile: profile)
    }
    var names = [node.title]
    var current = node
    for _ in 0..<8 {
      guard let id = current.parentID, let parent = navigator.node(id) else { break }
      names.insert(parent.title, at: 0)
      current = parent
    }
    browser.update(node, breadcrumb: names.joined(separator: " / "))
    display(browser, in: dataContent)
  }
  private func refreshBrowser(_ node: DataTreeNode) {
    if browserNodeID == node.id, let browser,
      dataContent.subviews.contains(where: { $0 === browser })
    {
      showTreeOverview(node)
    }
  }
  private func discoveredProfile(_ database: String, from template: ConnectionProfile)
    -> ConnectionProfile
  {
    let groupID = ConnectionIdentity(template).id
    if let existing = listedProfiles.first(where: {
      ConnectionIdentity($0).id == groupID && $0.database == database
    }) {
      return existing
    }
    let key = groupID + ":" + ConnectionIdentity.token(database)
    if let existing = discoveryProfiles[key] { return existing }
    var profile = template
    profile.id = UUID()
    profile.database = database
    profile.name = database
    if discoveryProfiles.count < 5000 { discoveryProfiles[key] = profile }
    return profile
  }
  private func treeMessage(_ title: String, in node: DataTreeNode) -> DataTreeNode {
    DataTreeNode(id: node.id + "/message", kind: .message, title: title, groupID: node.groupID)
  }
  private func loadTree(_ node: DataTreeNode, workspace: DataWorkspace, cursor: String = "0") {
    guard navigator.isCurrent(node), !node.loading else { return }
    if [.table, .index, .key].contains(node.kind) {
      workspace.preview(node.object)
      return
    }
    guard !workspace.busy else {
      Theme.error(ToolError.message("该会话正在执行查询，请稍后读取目录。"), window: window)
      return
    }
    let profile = workspace.profile
    guard ConnectionIdentity(profile).id == node.groupID else { return }
    let action: String
    let target: String
    switch (node.kind, profile.kind) {
    case (.connection, .mysql), (.connection, .pg), (.connection, .redis):
      action = "databases"
      target = ""
    case (.connection, .es):
      action = "catalog"
      target = ""
    case (.database, .pg):
      action = "schemas"
      target = ""
    case (.database, .mysql):
      action = "tables"
      target = node.profile?.database ?? profile.database
    case (.schema, .pg):
      action = "tables"
      target = node.schema
    case (.database, .redis):
      action = "query"
      target = ""
    default: return
    }
    guard navigator.nodeCount < 5000 else {
      Theme.error(ToolError.message("目录缓存已达 5000 项，请断开不用的连接后重试。"), window: window)
      return
    }
    browseContexts[profile.id] = node.id
    node.loading = true
    navigator.changed(node)
    showTreeOverview(node)
    Task { [weak self, weak node, weak workspace] in
      guard let self, let node, let workspace else { return }
      defer {
        if navigator.isCurrent(node) {
          node.loading = false
          navigator.changed(node)
          refreshBrowser(node)
        }
      }
      do {
        let response = try await engine.run(
          id: workspace.sessionID, action: action, text: "*", target: target, cursor: cursor)
        guard navigator.isCurrent(node), dataViews[profile.id] === workspace else { return }
        var children: [DataTreeNode] = []
        if action == "databases" {
          children = node.children.filter { $0.kind == .database }
          let known = Set(children.compactMap { $0.profile?.database })
          for row in response.rows where row.first != nil && !known.contains(row[0].text) {
            let child = navigator.databaseNode(
              profile: discoveredProfile(row[0].text, from: profile), groupID: node.groupID)
            child.detail = "从服务器读取；非原配置，业务环境与使用范围尚未核对"
            children.append(child)
          }
        } else if action == "schemas" {
          children = response.rows.compactMap { row in
            guard let name = row.first?.text else { return nil }
            let child = DataTreeNode(
              id: node.id + "/schema/" + ConnectionIdentity.token(name), kind: .schema,
              title: name, groupID: node.groupID, profile: profile, expandable: true)
            child.schema = name
            child.parentID = node.id
            return child
          }
        } else {
          if cursor != "0" { children = node.children.filter { $0.kind == .key } }
          var known = Set(children.map(\.id))
          var skippedLongNames = false
          for row in response.rows {
            let kind: DataTreeNode.Kind =
              profile.kind == .redis ? .key : profile.kind == .es ? .index : .table
            guard row.count >= (kind == .table ? 2 : 1) else { continue }
            let name = row[kind == .table ? 1 : 0].text
            guard name.utf8.count <= 4096 else {
              skippedLongNames = true
              continue
            }
            let id = node.id + "/object/" + ConnectionIdentity.token(name)
            guard known.insert(id).inserted else { continue }
            let child = DataTreeNode(
              id: id, kind: kind, title: name, detail: row.map(\.text).joined(separator: " · "),
              groupID: node.groupID, profile: profile)
            child.object = row
            child.parentID = node.id
            children.append(child)
          }
          if children.count > 500 { children = Array(children.prefix(500)) }
          if skippedLongNames { children.append(treeMessage("部分名称超过 4 KiB，未加入目录", in: node)) }
          if profile.kind == .redis, let next = response.nextCursor, next != "0",
            children.count < 500
          {
            let more = DataTreeNode(
              id: node.id + "/more", kind: .more, title: "下一批 Keys →", groupID: node.groupID,
              profile: profile)
            more.cursor = next
            more.parentID = node.id
            children.append(more)
          }
        }
        if children.isEmpty { children = [treeMessage("当前范围无可见对象", in: node)] }
        if response.truncated { children.append(treeMessage("目录已截断（最多 500 项）", in: node)) }
        guard navigator.nodeCount - node.children.count + children.count <= 5000 else {
          throw ToolError.message("目录缓存已达 5000 项，请断开不用的连接后重试。")
        }
        node.children = children
        node.loaded = true
        node.loading = false
        navigator.changed(node)
      } catch {
        guard navigator.isCurrent(node) else { return }
        node.loading = false
        Theme.error(error, window: window)
        navigator.changed(node)
      }
    }
  }
}
