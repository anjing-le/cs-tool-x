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
  private var openGate = DataOpenGate()
  private var openTasks: [UUID: Task<Void, Never>] = [:]
  private var connectionMenu: PaperMenu?
  private var credentials: [String: ConnectionCredentials] = [:]
  private let navigator = DataNavigator()
  private let connectionPicker = PaperSelect()
  private var selectedConnectionID: String?
  private var connectionChoices: [ConnectionGroup] = []
  private var browser: DataBrowser?
  private var browserNodeID: String?
  private var discoveryProfiles: [String: ConnectionProfile] = [:]
  private var selectedProfile: UUID?
  private enum Page: Equatable {
    case home
    case module(ToolModule)
    case tool(String)
  }
  private var history = NavigationHistory<Page>(.home)
  private var toolboxPages: [String: ToolboxWorkspace] = [:]
  private var selectedModule: ToolModule?
  private var shellModel: Workspace?
  private var shellHost: NSHostingView<WorkspaceView>?
  private var gitView: GitWorkspace?
  private var toolboxView: ToolboxWorkspace?
  private var textWorkspace: TransientTextWorkspace?
  private var fileView: TerminalWorkspace?
  private var sftpSheet: NSWindow?
  private var homeHost: NSHostingView<LauncherView>?
  private var connectionSheet: ConnectionSheet?
  private let root = WorkbenchSurface()
  private let body = NSView()
  private let dataContent = DataContentHost()
  private let dataRoot = NSView()
  private var backButton: PaperIconButton!
  private var header: NSStackView!
  private var headerHeight: NSLayoutConstraint!
  private let title = Theme.label("", size: 11, muted: true)
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
    backButton = PaperIconButton(
      symbol: "chevron.left", label: "返回", target: self, action: #selector(goBack))
    backButton.toolTip = "返回上一页 ⌘["
    let update = PaperIconButton(
      symbol: "arrow.down.circle", label: "检查更新", target: self, action: #selector(checkUpdates))
    update.setAccessibilityLabel("检查更新")
    update.toolTip = "检查更新"
    header = Theme.stack(
      [backButton!, title, NSView(), update], vertical: false, spacing: 12)
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
    window.onNavigate = { [weak self] forward in
      guard let self, self.canNavigate else { return false }
      if forward { self.goForward() } else { self.goBack() }
      return true
    }
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
    let add = PaperIconButton(
      symbol: "plus", label: "新建数据连接", target: self, action: #selector(newConnection))
    add.toolTip = "新建数据连接"
    connectionPicker.setAccessibilityLabel("切换数据连接")
    connectionPicker.onChange(target: self, action: #selector(selectConnection))
    connectionPicker.widthAnchor.constraint(greaterThanOrEqualToConstant: 210).isActive = true
    let menu = PaperIconButton(
      symbol: "ellipsis", label: "连接设置与会话管理", target: self, action: #selector(connectionActions(_:))
    )
    menu.toolTip = "连接设置与会话管理"
    let heading = Theme.stack([connectionPicker, NSView(), add, menu], vertical: false, spacing: 6)
    let side = Theme.stack(
      [
        heading, navigator.scroll,
      ], spacing: 14)
    Theme.pin(side, to: context, inset: 16)
    for view in [heading, navigator.scroll] {
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
  var canGoBack: Bool { canNavigate && history.canGoBack }
  var canGoForward: Bool { canNavigate && history.canGoForward }
  private var canNavigate: Bool {
    guard window?.attachedSheet == nil, NSApp.modalWindow == nil else { return false }
    if let editor = window?.firstResponder as? NSTextView, editor.hasMarkedText() { return false }
    return true
  }
  @objc func goBack() {
    guard canNavigate, let page = history.back() else { return }
    render(page)
  }
  @objc func goForward() {
    guard canNavigate, let page = history.forward() else { return }
    render(page)
  }
  private func navigate(_ page: Page) {
    guard canNavigate else { return }
    guard history.visit(page) else { return }
    render(page)
  }
  private func render(_ page: Page) {
    window?.makeFirstResponder(nil)
    switch page {
    case .home: renderHome()
    case .module(let module): renderModule(module)
    case .tool(let id): renderModule(.utilities, toolID: id)
    }
    backButton.isEnabled = history.canGoBack
  }
  @objc func goHome() {
    if history.current == .home { render(.home) } else { navigate(.home) }
  }
  private func renderHome() {
    gitView?.pause()
    toolboxView?.pause()
    textWorkspace?.pause()
    openGate.navigate()
    selectedModule = nil
    header.isHidden = true
    headerHeight.constant = 0
    if homeHost == nil {
      homeHost = NSHostingView(rootView: LauncherView { [weak self] in self?.showModule($0) })
    }
    display(homeHost!, in: body)
  }
  private func showModule(_ module: ToolModule) { navigate(.module(module)) }
  private func renderModule(_ module: ToolModule, toolID: String? = nil) {
    if module != .git { gitView?.pause() }
    if module != .utilities { toolboxView?.pause() }
    if module != .text { textWorkspace?.pause() }
    openGate.navigate()
    selectedModule = module
    header.isHidden = false
    headerHeight.constant = 43
    title.stringValue = ""
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
    case .git:
      if gitView == nil { gitView = GitWorkspace(frame: .zero) }
      display(gitView!, in: body)
      gitView?.activate()
    case .text:
      if textWorkspace == nil { textWorkspace = TransientTextWorkspace(frame: .zero) }
      display(textWorkspace!, in: body)
      textWorkspace?.activate()
    case .utilities:
      toolboxView?.pause()
      let key = toolID ?? ""
      if toolboxPages[key] == nil {
        let view = ToolboxWorkspace(frame: .zero)
        view.onOpen = { [weak self] item in self?.navigate(.tool(item.id)) }
        view.onGrid = { [weak self] in self?.showModule(.utilities) }
        if let toolID, let item = Toolbox.items.first(where: { $0.id == toolID }) {
          view.open(item)
        }
        toolboxPages[key] = view
      }
      toolboxView = toolboxPages[key]
      display(toolboxView!, in: body)
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
    connectionPicker.toolTip = "\(groups.count) 个连接"
    if let browser, dataContent.subviews.contains(where: { $0 === browser }) {
      if let id = browserNodeID, let node = navigator.node(id) {
        showTreeOverview(node)
      } else if let id = selectedConnectionID, let root = navigator.root(id) {
        showTreeOverview(root)
      }
    }
  }
  @objc private func selectConnection() {
    let index = connectionPicker.indexOfSelectedItem
    guard connectionChoices.indices.contains(index) else { return }
    openGate.navigate()
    let id = connectionChoices[index].id
    selectedConnectionID = id
    selectedProfile =
      dataViews.values.first(where: { ConnectionIdentity($0.profile).id == id })?.profile.id
    navigator.filterConnection(id)
    if let root = navigator.root(id) {
      navigator.expand(root)
      openNode(root)
    }
  }
  private func dataWelcome() {
    let view = NSView()
    let stack = Theme.stack(
      [
        Theme.button("新建连接", target: self, action: #selector(newConnection), primary: true)
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
  private func showConnection(
    profile: ConnectionProfile?, browse: DataTreeNode? = nil, credentialsOnly: Bool = false
  ) {
    guard window?.attachedSheet == nil else { return }
    openGate.navigate()
    let navigation = openGate.navigationRevision
    Task { [weak self] in
      guard let self else { return }
      do {
        let authentication = try await Task.detached {
          try profile.flatMap { try DataCredentialStore().load(for: $0) }
        }.value
        guard openGate.navigationRevision == navigation, selectedModule == .data else { return }
        presentConnection(
          profile: profile, browse: browse, credentialsOnly: credentialsOnly,
          authentication: authentication)
      } catch { Theme.error(error, window: window) }
    }
  }
  private func presentConnection(
    profile: ConnectionProfile?, browse: DataTreeNode?, credentialsOnly: Bool,
    authentication: ConnectionCredentials?
  ) {
    guard let window, window.attachedSheet == nil else { return }
    if let profile, openGate.isPending(profile.id) { return }
    if let profile, dataViews[profile.id] != nil {
      Theme.error(ToolError.message("请先断开当前会话，再修改连接设置。"), window: window)
      return
    }
    guard dataViews.count + openGate.pendingCount < 4 else {
      Theme.error(ToolError.message("最多同时保留 4 个数据会话，请先断开一个。"), window: window)
      return
    }
    let sheet = ConnectionSheet(
      engine: engine, profile: profile,
      credentials: authentication ?? profile.flatMap { credentials[$0.credentialScope] },
      saveByDefault: profile == nil || profiles.contains(where: { $0.id == profile?.id }),
      credentialsOnly: credentialsOnly)
    connectionSheet = sheet
    sheet.onConnected = { [weak self] profile, id, elapsed, save, authentication in
      guard let self else { return }
      let workspace = installWorkspace(
        profile, id: id, elapsed: elapsed, save: save, authentication: authentication,
        presents: browse == nil)
      connectionSheet = nil
      if let browse, let current = navigator.node(browse.id) {
        presentNode(current, workspace: workspace, query: false, presents: true)
      }
    }
    window.beginSheet(sheet.window!)
  }
  @discardableResult
  private func installWorkspace(
    _ profile: ConnectionProfile, id: String, elapsed: Int, save: Bool,
    authentication: ConnectionCredentials, presents: Bool
  ) -> DataWorkspace {
    let workspace = DataWorkspace(
      profile: profile, sessionID: id, elapsed: elapsed, engine: engine)
    credentials[profile.credentialScope] = authentication
    dataViews[profile.id] = workspace
    if presents {
      selectedProfile = profile.id
      selectedConnectionID = ConnectionIdentity(profile).id
    }
    workspace.onInteraction = { [weak self] in self?.openGate.navigate() }
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
            ToolError.message("已连接，但配置保存失败：\(error.localizedDescription)"), window: self.window)
        }
        if self.profileSaveSerial == saveSerial { self.profileSaveTask = nil }
      }
    } else if !profiles.contains(where: { $0.id == profile.id }) {
      temporary.removeAll { $0.id == profile.id }
      temporary.append(profile)
    }
    refreshConnections()
    if presents { display(workspace, in: dataContent) }
    return workspace
  }
  @objc private func connectionActions(_ sender: NSButton) {
    connectionMenu?.dismiss()
    connectionMenu = PaperMenu(titles: ["新建连接", "新建查询", "刷新目录", "编辑连接", "断开当前连接"], anchor: sender) {
      [weak self] index in
      guard let self else { return }
      if index == 0 {
        newConnection()
        return
      }
      guard let id = selectedConnectionID,
        let group = connectionChoices.first(where: { $0.id == id })
      else { return }
      if index == 1 || index == 2 {
        guard var node = navigator.selectedNode ?? navigator.root(id) else { return }
        if index == 2, !node.expandable, let parentID = node.parentID,
          let parent = navigator.node(parentID)
        {
          node = parent
        }
        openNode(node, query: index == 1, presents: index == 1)
      }
      if index == 3, let profile = group.profiles.first { showConnection(profile: profile) }
      if index == 4 {
        for workspace in dataViews.values where ConnectionIdentity(workspace.profile).id == id {
          workspace.requestDisconnect()
        }
      }
    }
    connectionMenu?.show()
  }
  private func closed(_ id: UUID) {
    let groupID = dataViews[id].map { ConnectionIdentity($0.profile).id }
    dataViews.removeValue(forKey: id)
    if let groupID,
      !dataViews.values.contains(where: { ConnectionIdentity($0.profile).id == groupID }),
      !openGate.contains(groupID: groupID)
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
    if dataViews.isEmpty && openGate.pendingCount == 0 { Task { await engine.stop() } }
  }
  @objc private func checkUpdates() { onCheckUpdates?() }
  func newShellTab() {
    showModule(.terminal)
    shellModel?.newTab()
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
    gitView?.stop()
    toolboxView?.pause()
    textWorkspace?.pause()
    openTasks.values.forEach { $0.cancel() }
    openTasks.removeAll()
    openGate.clear()
    credentials.removeAll()
    shellModel?.stop()
    fileView?.stop()
    Task { await engine.stop() }
  }
}

extension WorkbenchController {
  private func selectedTreeNode(_ node: DataTreeNode) {
    // Selection does not connect or replace the current editor.
  }
  private func expandedTreeNode(_ node: DataTreeNode) {
    guard !node.loaded, !node.loading else { return }
    openNode(node, presents: false)
  }
  private func activateTreeNode(_ node: DataTreeNode) { openNode(node) }
  private func openNode(_ node: DataTreeNode, query: Bool = false, presents: Bool = true) {
    guard navigator.isCurrent(node), node.kind != .message, window?.attachedSheet == nil else {
      return
    }
    if node.kind == .more, let parentID = node.parentID, let parent = navigator.node(parentID),
      let profile = parent.profile, let workspace = dataViews[profile.id]
    {
      openGate.navigate()
      loadTree(parent, workspace: workspace, cursor: node.cursor, presents: presents)
      return
    }
    guard let profile = node.profile else { return }
    let workspace =
      node.kind == .connection
      ? dataViews.values.first(where: { ConnectionIdentity($0.profile).id == node.groupID })
      : dataViews[profile.id]
    if let workspace {
      guard node.kind == .connection || workspace.profile == profile else {
        node.openError = "连接设置已更改，请从左侧菜单断开旧会话后重试。"
        if presents { showTreeOverview(node) }
        return
      }
      if presents { openGate.navigate() }
      presentNode(node, workspace: workspace, query: query, presents: presents)
      return
    }
    do {
      let first = try openGate.begin(
        profile: profile, nodeID: node.id, query: query, presents: presents, active: dataViews.count
      )
      node.openError = "正在连接…"
      if presents { showTreeOverview(node) }
      guard first else { return }
      openTasks[profile.id] = Task { [weak self] in
        guard let self else { return }
        defer {
          openTasks.removeValue(forKey: profile.id)
          @MainActor func clearOpening(_ nodes: [DataTreeNode]) {
            for node in nodes {
              if node.profile?.id == profile.id && node.openError == "正在连接…" {
                node.openError = nil
                navigator.changed(node)
                refreshBrowser(node)
              }
              clearOpening(node.children)
            }
          }
          clearOpening(navigator.roots)
        }
        do {
          let cached = credentials[profile.credentialScope]
          let authentication = try await Task.detached {
            try cached ?? DataCredentialStore().load(for: profile)
          }.value
          try Task.checkCancellation()
          guard let authentication else {
            guard let request = openGate.finish(profile.id), openGate.isCurrent(request),
              selectedModule == .data, let current = navigator.node(request.nodeID)
            else { return }
            showConnection(profile: profile, browse: current, credentialsOnly: true)
            return
          }
          let (sessionID, elapsed) = try await engine.connect(
            profile: profile, password: authentication.password, apiKey: authentication.apiKey)
          guard !Task.isCancelled, let request = openGate.finish(profile.id),
            let current = navigator.node(request.nodeID), current.profile == profile
          else {
            try? await engine.disconnect(id: sessionID)
            return
          }
          let visible = request.presents && openGate.isCurrent(request) && selectedModule == .data
          let workspace = installWorkspace(
            profile, id: sessionID, elapsed: elapsed, save: false, authentication: authentication,
            presents: false)
          presentNode(current, workspace: workspace, query: request.query, presents: visible)
        } catch {
          guard let request = openGate.finish(profile.id),
            let current = navigator.node(request.nodeID)
          else { return }
          current.openError = "连接失败：" + error.localizedDescription
          navigator.changed(current)
          if request.presents && openGate.isCurrent(request) && selectedModule == .data {
            showTreeOverview(current)
          }
        }
      }
    } catch {
      node.openError = error.localizedDescription
      if presents { showTreeOverview(node) }
    }
  }
  private func presentNode(
    _ node: DataTreeNode, workspace: DataWorkspace, query: Bool, presents: Bool
  ) {
    node.openError = nil
    if presents {
      selectedConnectionID = node.groupID
      if query || [.table, .index, .key].contains(node.kind) {
        selectedProfile = workspace.profile.id
        if query { workspace.showQuery() }
        display(workspace, in: dataContent)
      } else {
        showTreeOverview(node)
      }
    }
    if !query {
      if node.expandable { navigator.expand(node, respectingUserCollapse: true) }
      loadTree(node, workspace: workspace, presents: presents)
    }
  }
  private func showTreeOverview(_ node: DataTreeNode) {
    if browserNodeID != node.id {
      browser = DataBrowser(frame: .zero)
      browserNodeID = node.id
    }
    guard let browser else { return }
    browser.onQuery = { [weak self, weak node] in
      guard let node else { return }
      self?.openNode(node, query: true)
    }
    var names = [node.title]
    var current = node
    for _ in 0..<8 {
      guard let id = current.parentID, let parent = navigator.node(id) else { break }
      names.insert(parent.title, at: 0)
      current = parent
    }
    browser.update(node, breadcrumb: names.joined(separator: " / "))
    dataContent.showDirectory(browser)
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
  private func loadTree(
    _ node: DataTreeNode, workspace: DataWorkspace, cursor: String = "0", presents: Bool = true
  ) {
    guard navigator.isCurrent(node) else { return }
    if node.loading {
      if presents { showTreeOverview(node) }
      return
    }
    if [.table, .index, .key].contains(node.kind) {
      if presents { workspace.preview(node.object) }
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
    node.loading = true
    navigator.changed(node)
    if presents { showTreeOverview(node) }
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
        node.openError = error.localizedDescription
        navigator.changed(node)
      }
    }
  }
}
