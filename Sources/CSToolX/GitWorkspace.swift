import AppKit
import ToolCore

@MainActor final class GitWorkspace: NSView, NSTextFieldDelegate {
  private let sidebar = GitSidebar()
  private let history = GitLogList()
  private let repositorySearch = Theme.field("查找…")
  private let search = Theme.field("搜索…")
  private let author = Theme.field("作者")
  private let datePicker = PaperSelect()
  private let pathLabel = Theme.label("选择一个目录，查看其中的 Git 仓库", size: 12, muted: true)
  private let status = Theme.label("", size: 11, muted: true)
  private let detailTitle = Theme.label("", size: 13, weight: .medium)
  private let detailMeta = Theme.label("", size: 10, muted: true)
  private let message = NSTextView()
  private let files = TextTable(headers: ["状态", "变更文件"], widths: [50, 260])
  private var more: NSButton!
  private var scanTask: Task<Void, Never>?
  private var logTask: Task<Void, Never>?
  private var detailTask: Task<Void, Never>?
  private var searchTask: Task<Void, Never>?
  private var lastProgress = 0.0
  private var scanSerial = 0, logSerial = 0, detailSerial = 0
  private var locations: [GitLocation] = []
  private(set) var repositories: [GitRepository] = []
  private var selectedRepository: String?
  private var selectedReference = ""
  private var filterBar: NSStackView!
  private var filterDivider: NSBox!
  private var filterButton: PaperIconButton!
  private var detailPanel: NSView!
  private var detailDivider: NSBox!
  private var pages: [String: [GitCommit]] = [:]
  private var offsets: [String: Int] = [:]
  private var moreRoots = Set<String>()
  private var logErrors: [String: String] = [:]
  private var root = ""
  private var scanNote = ""
  private var needsScan = false, needsLog = false
  private var selectedCommit: GitCommit?
  var hasPendingWork: Bool { scanTask != nil || logTask != nil || detailTask != nil }
  private var active = false
  private var currentFilter = GitLogFilter()

  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.backgroundColor = Theme.paper.cgColor
    let choose = PaperIconButton(
      symbol: "folder", label: "打开目录", target: self, action: #selector(chooseDirectory))
    let refresh = PaperIconButton(
      symbol: "arrow.clockwise", label: "刷新", target: self, action: #selector(refreshDirectory))
    filterButton = PaperIconButton(
      symbol: "line.3.horizontal.decrease", label: "筛选", target: self,
      action: #selector(toggleFilters))
    more = PaperIconButton(
      symbol: "arrow.down", label: "加载更多", target: self, action: #selector(loadMore))
    more.isEnabled = false
    more.isHidden = true
    pathLabel.stringValue = "选择目录"
    pathLabel.lineBreakMode = .byTruncatingMiddle
    pathLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 280).isActive = true
    search.widthAnchor.constraint(equalToConstant: 240).isActive = true
    let directoryBar = Theme.stack(
      [choose, pathLabel, NSView(), search, filterButton, refresh], vertical: false, spacing: 10)
    directoryBar.edgeInsets = NSEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
    directoryBar.heightAnchor.constraint(equalToConstant: 46).isActive = true
    datePicker.addItems(withTitles: ["所有日期", "最近 7 天", "最近 30 天", "最近 90 天", "最近一年"])
    datePicker.onChange(target: self, action: #selector(filterChanged))
    author.widthAnchor.constraint(equalToConstant: 160).isActive = true
    datePicker.widthAnchor.constraint(equalToConstant: 130).isActive = true
    let reset = PaperIconButton(
      symbol: "xmark", label: "清除作者与日期筛选", target: self, action: #selector(clearFilters))
    filterBar = Theme.stack([NSView(), author, datePicker, reset], vertical: false, spacing: 8)
    filterBar.edgeInsets = NSEdgeInsets(top: 4, left: 12, bottom: 4, right: 12)
    filterBar.heightAnchor.constraint(equalToConstant: 42).isActive = true
    filterBar.isHidden = true
    filterDivider = Theme.separator()
    filterDivider.isHidden = true
    for (field, label) in [
      (repositorySearch, "筛选仓库和分支"), (search, "搜索 Git 提交信息或哈希"), (author, "按作者筛选提交"),
    ] {
      field.delegate = self
      field.setAccessibilityLabel(label)
      field.target = self
      field.action = #selector(filterChanged)
    }
    datePicker.setAccessibilityLabel("按日期筛选历史")
    let left = Theme.stack(
      [repositorySearch, sidebar.scroll],
      spacing: 10)
    left.edgeInsets = NSEdgeInsets(top: 14, left: 12, bottom: 12, right: 12)
    left.wantsLayer = true
    left.layer?.backgroundColor = Theme.sidebar.cgColor
    left.widthAnchor.constraint(equalToConstant: 280).isActive = true
    for view in [repositorySearch, sidebar.scroll] {
      view.widthAnchor.constraint(equalTo: left.widthAnchor, constant: -24).isActive = true
    }
    let right = makeDetailPanel()
    detailPanel = right
    right.widthAnchor.constraint(equalToConstant: 285).isActive = true
    let dividers = [Theme.separator(vertical: true), Theme.separator(vertical: true)]
    detailDivider = dividers[1]
    let content = Theme.stack(
      [left, dividers[0], history.scroll, dividers[1], right], vertical: false, spacing: 0)
    for divider in dividers {
      divider.heightAnchor.constraint(equalTo: content.heightAnchor).isActive = true
    }
    content.alignment = .top
    content.detachesHiddenViews = true
    right.isHidden = true
    detailDivider.isHidden = true
    for view in [left, history.scroll, right] {
      view.heightAnchor.constraint(equalTo: content.heightAnchor).isActive = true
    }
    history.scroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 350).isActive = true
    let footer = Theme.stack([status, NSView(), more], vertical: false, spacing: 12)
    footer.edgeInsets = NSEdgeInsets(top: 6, left: 16, bottom: 6, right: 16)
    footer.heightAnchor.constraint(equalToConstant: 32).isActive = true
    let layout = Theme.stack(
      [
        directoryBar, Theme.separator(), filterBar, filterDivider, content, Theme.separator(),
        footer,
      ], spacing: 0)
    layout.detachesHiddenViews = true
    Theme.pin(layout, to: self)
    for view in [directoryBar, filterBar!, content, footer] {
      view.widthAnchor.constraint(equalTo: layout.widthAnchor).isActive = true
    }
    sidebar.onSelect = { [weak self] repo, reference in
      guard let self else { return }
      selectedRepository = repo?.id
      selectedReference = reference?.fullName ?? ""
      validateReference()
      reloadLog()
    }
    history.onSelect = { [weak self] in self?.showCommit($0) }
    root = UserDefaults.standard.string(forKey: "git.browser.directory") ?? ""
    needsScan = !root.isEmpty
  }
  required init?(coder: NSCoder) { nil }
  private func makeDetailPanel() -> NSView {
    detailMeta.maximumNumberOfLines = 4
    detailMeta.lineBreakMode = .byTruncatingMiddle
    detailMeta.heightAnchor.constraint(equalToConstant: 62).isActive = true
    message.isEditable = false
    message.isSelectable = true
    message.isRichText = false
    message.font = .systemFont(ofSize: 12)
    message.textColor = Theme.ink
    message.backgroundColor = Theme.paper
    message.textContainerInset = NSSize(width: 5, height: 8)
    message.isHorizontallyResizable = false
    message.isVerticallyResizable = true
    message.textContainer?.widthTracksTextView = true
    message.autoresizingMask = [.width]
    message.minSize = NSSize(width: 0, height: 165)
    message.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    message.frame = NSRect(x: 0, y: 0, width: 250, height: 165)
    let messageScroll = NSScrollView()
    messageScroll.documentView = message
    messageScroll.hasVerticalScroller = true
    messageScroll.drawsBackground = false
    messageScroll.autohidesScrollers = true
    messageScroll.heightAnchor.constraint(equalToConstant: 165).isActive = true
    let close = PaperIconButton(
      symbol: "xmark", label: "收起详情", target: self, action: #selector(closeDetail))
    let heading = Theme.stack([detailTitle, NSView(), close], vertical: false, spacing: 4)
    let stack = Theme.stack(
      [heading, detailMeta, messageScroll, Theme.separator(), files.scroll], spacing: 10)
    heading.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28).isActive = true
    files.table.headerView = nil
    stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 12, right: 14)
    for view in [detailMeta, messageScroll, files.scroll] {
      view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28).isActive = true
    }
    files.scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
    files.table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
    files.colorForCell = { [weak self] row, _ in
      guard let self, files.rows.indices.contains(row) else { return nil }
      switch files.rows[row].first {
      case "A": return Theme.sage
      case "D": return NSColor(srgbRed: 0.73, green: 0.32, blue: 0.31, alpha: 1)
      case "M", "T": return GitPalette.lines[0]
      default: return Theme.ink
      }
    }
    return stack
  }
  func activate() {
    active = true
    if needsScan {
      scanDirectory(root)
    } else if needsLog {
      reloadLog()
    } else if let selectedCommit, detailTask == nil {
      showCommit(selectedCommit)
    }
  }
  func pause() {
    active = false
    if scanTask != nil { needsScan = true }
    if logTask != nil { needsLog = true }
    scanTask?.cancel()
    scanTask = nil
    scanSerial += 1
    logTask?.cancel()
    logTask = nil
    logSerial += 1
    detailTask?.cancel()
    detailTask = nil
    detailSerial += 1
    searchTask?.cancel()
    searchTask = nil
    datePicker.dismissMenu()
  }
  func stop() { pause() }
  @objc private func chooseDirectory() {
    guard let window, window.attachedSheet == nil else { return }
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = false
    panel.prompt = "打开"
    panel.beginSheetModal(for: window) { [weak self] result in
      guard result == .OK, let url = panel.url else { return }
      self?.scanDirectory(url.path)
    }
  }
  @objc private func refreshDirectory() {
    if !root.isEmpty { scanDirectory(root) } else { chooseDirectory() }
  }
  func scanDirectory(_ path: String) {
    scanTask?.cancel()
    logTask?.cancel()
    detailTask?.cancel()
    searchTask?.cancel()
    scanTask = nil
    logTask = nil
    detailTask = nil
    searchTask = nil
    scanSerial += 1
    logSerial += 1
    detailSerial += 1
    let serial = scanSerial
    root = path
    needsScan = false
    needsLog = false
    status.stringValue = "正在发现 Git 仓库…"
    more.isEnabled = false
    pathLabel.stringValue = URL(fileURLWithPath: path).lastPathComponent
    pathLabel.toolTip = path
    repositories = []
    locations = []
    pages = [:]
    selectedRepository = nil
    selectedReference = ""
    sidebar.update([])
    history.update([], repositories: [])
    clearDetail()
    scanTask = Task { [weak self] in
      guard let self else { return }
      do {
        let scan = try await GitBrowser.scan(directory: path)
        guard !Task.isCancelled, scanSerial == serial else { return }
        root = scan.root
        locations = scan.repositories
        UserDefaults.standard.set(scan.root, forKey: "git.browser.directory")
        scanNote = scan.limited ? "目录扫描已达上限，请选择更小目录" : ""
        if !scan.warnings.isEmpty { scanNote += (scanNote.isEmpty ? "" : "；") + "部分目录无法读取" }
        status.toolTip = scan.warnings.joined(separator: "\n")
        status.stringValue = "发现 \(locations.count) 个仓库，正在读取分支…"
        let loaded = try await GitBrowser.repositories(locations) { [weak self] repository in
          await self?.didRead(repository, serial: serial)
        }
        guard !Task.isCancelled, scanSerial == serial else { return }
        repositories = loaded
        sidebar.update(loaded)
        scanTask = nil
        selectedRepository = loaded.first?.id
        if let selectedRepository { sidebar.expand(selectedRepository) }
        sidebar.select(repository: selectedRepository)
        validateReference()
        reloadLog()
      } catch is CancellationError {} catch {
        guard scanSerial == serial else { return }
        scanTask = nil
        status.stringValue = "读取失败：" + error.localizedDescription
      }
    }
  }
  private func didRead(_ repository: GitRepository, serial: Int) {
    guard scanSerial == serial else { return }
    repositories.append(repository)
    let now = ProcessInfo.processInfo.systemUptime
    guard now - lastProgress >= 0.08 else { return }
    lastProgress = now
    repositories.sort { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    sidebar.update(repositories)
    status.stringValue = "正在读取分支 \(repositories.count) / \(locations.count)"
  }
  private func validateReference() {
    if !selectedReference.isEmpty,
      !repositories.contains(where: {
        $0.id == selectedRepository
          && $0.references.contains(where: { $0.fullName == selectedReference })
      })
    {
      selectedReference = ""
    }
  }
  @objc private func toggleFilters() {
    filterBar.isHidden.toggle()
    filterDivider.isHidden = filterBar.isHidden
    filterButton.selected = !filterBar.isHidden
    if !filterBar.isHidden { window?.makeFirstResponder(author) } else { datePicker.dismissMenu() }
  }
  @objc private func clearFilters() {
    author.stringValue = ""
    datePicker.selectItem(at: 0)
    reloadLog()
  }
  @objc private func closeDetail() {
    detailTask?.cancel()
    detailTask = nil
    detailSerial += 1
    clearDetail()
    history.table.deselectAll(nil)
  }
  func controlTextDidChange(_ notification: Notification) {
    if notification.object as? NSTextField === repositorySearch {
      sidebar.query = repositorySearch.stringValue
      return
    }
    searchTask?.cancel()
    searchTask = Task { [weak self] in
      do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }
      self?.reloadLog()
    }
  }
  @objc private func filterChanged() {
    searchTask?.cancel()
    reloadLog()
  }
  private func reloadLog() {
    guard scanTask == nil else {
      needsLog = true
      return
    }
    logTask?.cancel()
    logTask = nil
    logSerial += 1
    detailTask?.cancel()
    detailTask = nil
    detailSerial += 1
    pages = [:]
    offsets = [:]
    moreRoots = Set(targetRepositories.map(\.id))
    logErrors = [:]
    currentFilter = GitLogFilter()
    currentFilter.reference = selectedReference
    currentFilter.text = search.stringValue
    currentFilter.author = author.stringValue
    currentFilter.days = [0, 7, 30, 90, 365][datePicker.indexOfSelectedItem]
    filterButton.badge = !currentFilter.author.isEmpty || currentFilter.days != 0
    history.update([], repositories: repositories)
    clearDetail()
    needsLog = false
    loadPage()
  }
  private var targetRepositories: [GitRepository] {
    selectedRepository.map { id in repositories.filter { $0.id == id } } ?? repositories
  }
  @objc private func loadMore() { loadPage() }
  private func loadPage() {
    let targets = targetRepositories.filter { moreRoots.contains($0.id) }
    let loadedCount = pages.values.reduce(0) { $0 + $1.count }
    let room = GitBrowser.maxLoadedCommits - loadedCount
    guard !targets.isEmpty, room >= targets.count else {
      updateStatus()
      return
    }
    let limit = min(GitBrowser.pageSize, room / targets.count)
    let serial = logSerial
    let filter = currentFilter
    let requestOffsets = offsets
    more.isEnabled = false
    status.stringValue = "正在读取提交历史…"
    logTask = Task { [weak self] in
      guard let self else { return }
      do {
        let result = try await GitBrowser.logs(
          targets, filter: filter, offsets: requestOffsets, limit: limit)
        guard !Task.isCancelled, logSerial == serial else { return }
        for rootPage in result {
          if let page = rootPage.page {
            pages[rootPage.repository, default: []] += page.commits
            offsets[rootPage.repository] = page.nextOffset
            if !page.hasMore { moreRoots.remove(rootPage.repository) }
          } else {
            logErrors[rootPage.repository] = rootPage.error
            moreRoots.remove(rootPage.repository)
          }
        }
        let lists = pages.keys.sorted().compactMap { self.pages[$0] }
        let repositories = self.repositories
        let presentation = await Task.detached {
          GitLogList.prepare(GitBrowser.merge(lists), repositories: repositories)
        }.value
        guard !Task.isCancelled, logSerial == serial else { return }
        history.apply(presentation)
        logTask = nil
        updateStatus()
      } catch is CancellationError {} catch {
        guard logSerial == serial else { return }
        logTask = nil
        status.stringValue = "读取失败：" + error.localizedDescription
      }
    }
  }
  private func updateStatus() {
    let count = pages.values.reduce(0) { $0 + $1.count }
    let remaining = GitBrowser.maxLoadedCommits - count
    more.isEnabled = !moreRoots.isEmpty && remaining >= moreRoots.count && logTask == nil
    more.isHidden = !more.isEnabled
    var parts = ["\(repositories.count) 个仓库", "\(count) 条提交"]
    if !moreRoots.isEmpty { parts.append(more.isEnabled ? "可继续加载" : "已达 2000 条展示上限，可按仓库或分支缩小范围") }
    if history.graphLimited { parts.append("部分分支图线超出展示预算") }
    if !logErrors.isEmpty { parts.append("\(logErrors.count) 个仓库读取失败") }
    if repositories.contains(where: \.limited) { parts.append("部分分支超出上限") }
    if !scanNote.isEmpty { parts.append(scanNote) }
    status.stringValue = parts.joined(separator: " · ")
    status.toolTip =
      (Array(logErrors.values) + [scanNote, "远程分支来自本地最近一次 fetch；本工具不联网刷新。图线按已读取父关系绘制，不补造省略历史。"])
      .joined(separator: "\n")
  }
  private func clearDetail() {
    selectedCommit = nil
    detailTitle.stringValue = ""
    detailMeta.stringValue = ""
    detailPanel?.isHidden = true
    detailDivider?.isHidden = true
    message.string = ""
    files.update([])
  }
  private func showCommit(_ commit: GitCommit) {
    guard let repository = repositories.first(where: { $0.id == commit.repository }) else { return }
    detailTask?.cancel()
    detailSerial += 1
    let serial = detailSerial
    selectedCommit = commit
    detailPanel.isHidden = false
    detailDivider.isHidden = false
    detailTitle.stringValue = String(commit.oid.prefix(10))
    detailMeta.stringValue =
      repository.location.name + "\n" + commit.author + " <" + commit.email + ">\n"
      + Date(timeIntervalSince1970: Double(commit.timestamp)).formatted()
    detailMeta.toolTip = commit.oid + "\n父提交：" + commit.parents.joined(separator: ", ")
    message.string = "正在读取…"
    files.update([])
    detailTask = Task { [weak self] in
      guard let self else { return }
      do {
        let detail = try await GitBrowser.detail(repository: repository, oid: commit.oid)
        guard !Task.isCancelled, detailSerial == serial else { return }
        message.string = detail.message
        files.update(
          detail.files.map { [$0.status, $0.path.replacingOccurrences(of: "\n", with: "↵")] })
        if detail.limited { detailTitle.stringValue += " · 内容已截断" }
        detailTask = nil
      } catch is CancellationError {} catch {
        guard detailSerial == serial else { return }
        message.string = "读取失败：" + error.localizedDescription
        detailTask = nil
      }
    }
  }
}
