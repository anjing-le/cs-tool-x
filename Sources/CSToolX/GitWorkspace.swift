import AppKit
import ToolCore

@MainActor final class GitWorkspace: NSView, NSTextFieldDelegate {
  private let sidebar = GitSidebar()
  private let history = GitLogList()
  private let repositorySearch = Theme.field("筛选仓库 / 分支")
  private let search = Theme.field("搜索提交信息 / 哈希")
  private let author = Theme.field("作者")
  private let repositoryPicker = PaperSelect()
  private let branchPicker = PaperSelect()
  private let datePicker = PaperSelect()
  private let pathLabel = Theme.label("选择一个目录，查看其中的 Git 仓库", size: 12, muted: true)
  private let status = Theme.label("", size: 11, muted: true)
  private let detailTitle = Theme.label("提交详情", size: 13, weight: .medium)
  private let detailMeta = Theme.label("选择一条提交", size: 10, muted: true)
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
  private var branchChoices: [GitReference] = []
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
    let choose = Theme.button("打开目录", target: self, action: #selector(chooseDirectory))
    let refresh = Theme.button("刷新", target: self, action: #selector(refreshDirectory))
    more = Theme.button("加载更多", target: self, action: #selector(loadMore))
    more.isEnabled = false
    pathLabel.lineBreakMode = .byTruncatingMiddle
    let directoryBar = Theme.stack(
      [choose, pathLabel, NSView(), refresh], vertical: false, spacing: 12)
    directoryBar.edgeInsets = NSEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
    directoryBar.heightAnchor.constraint(equalToConstant: 54).isActive = true
    repositoryPicker.addItems(withTitles: ["所有仓库"])
    repositoryPicker.onChange(target: self, action: #selector(selectRepository))
    branchPicker.addItems(withTitles: ["所有分支"])
    branchPicker.onChange(target: self, action: #selector(selectBranch))
    datePicker.addItems(withTitles: ["所有日期", "最近 7 天", "最近 30 天", "最近 90 天", "最近一年"])
    datePicker.onChange(target: self, action: #selector(filterChanged))
    repositoryPicker.widthAnchor.constraint(equalToConstant: 150).isActive = true
    branchPicker.widthAnchor.constraint(equalToConstant: 155).isActive = true
    author.widthAnchor.constraint(equalToConstant: 100).isActive = true
    datePicker.widthAnchor.constraint(equalToConstant: 110).isActive = true
    search.widthAnchor.constraint(greaterThanOrEqualToConstant: 140).isActive = true
    let filters = Theme.stack(
      [search, repositoryPicker, branchPicker, author, datePicker], vertical: false, spacing: 8)
    filters.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
    filters.heightAnchor.constraint(equalToConstant: 50).isActive = true
    for (field, label) in [
      (repositorySearch, "筛选仓库和分支"), (search, "搜索 Git 提交信息或哈希"), (author, "按作者筛选提交"),
    ] {
      field.delegate = self
      field.setAccessibilityLabel(label)
      field.target = self
      field.action = #selector(filterChanged)
    }
    repositoryPicker.setAccessibilityLabel("按仓库筛选历史")
    branchPicker.setAccessibilityLabel("按分支筛选历史")
    datePicker.setAccessibilityLabel("按日期筛选历史")
    let legend = Theme.label("● HEAD    ● 本地    ● 远程", size: 10, muted: true)
    let legendText = NSMutableAttributedString(
      string: "● HEAD    ● 本地    ● 远程",
      attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: Theme.muted])
    for (range, color) in [
      (NSRange(location: 0, length: 1), GitPalette.head),
      (NSRange(location: 10, length: 1), GitPalette.local),
      (NSRange(location: 18, length: 1), GitPalette.remote),
    ] where NSMaxRange(range) <= legendText.length {
      legendText.addAttribute(.foregroundColor, value: color, range: range)
    }
    legend.attributedStringValue = legendText
    let left = Theme.stack(
      [Theme.label("仓库与分支", size: 13, weight: .medium), repositorySearch, legend, sidebar.scroll],
      spacing: 10)
    left.edgeInsets = NSEdgeInsets(top: 14, left: 12, bottom: 12, right: 12)
    left.wantsLayer = true
    left.layer?.backgroundColor = Theme.sidebar.cgColor
    left.widthAnchor.constraint(equalToConstant: 280).isActive = true
    for view in [repositorySearch, sidebar.scroll] {
      view.widthAnchor.constraint(equalTo: left.widthAnchor, constant: -24).isActive = true
    }
    let right = makeDetailPanel()
    right.widthAnchor.constraint(equalToConstant: 285).isActive = true
    let dividers = [Theme.separator(vertical: true), Theme.separator(vertical: true)]
    let content = Theme.stack(
      [left, dividers[0], history.scroll, dividers[1], right], vertical: false, spacing: 0)
    for divider in dividers {
      divider.heightAnchor.constraint(equalTo: content.heightAnchor).isActive = true
    }
    content.alignment = .top
    for view in [left, history.scroll, right] {
      view.heightAnchor.constraint(equalTo: content.heightAnchor).isActive = true
    }
    history.scroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 350).isActive = true
    let footer = Theme.stack([status, NSView(), more], vertical: false, spacing: 12)
    footer.edgeInsets = NSEdgeInsets(top: 6, left: 16, bottom: 6, right: 16)
    footer.heightAnchor.constraint(equalToConstant: 44).isActive = true
    let layout = Theme.stack(
      [
        directoryBar, Theme.separator(), filters, Theme.separator(), content, Theme.separator(),
        footer,
      ], spacing: 0)
    Theme.pin(layout, to: self)
    for view in [directoryBar, filters, content, footer] {
      view.widthAnchor.constraint(equalTo: layout.widthAnchor).isActive = true
    }
    sidebar.onSelect = { [weak self] repo, reference in
      guard let self else { return }
      selectedRepository = repo?.id
      selectedReference = reference?.fullName ?? ""
      syncPickers()
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
    let stack = Theme.stack(
      [
        detailTitle, detailMeta, messageScroll, Theme.separator(),
        Theme.label("变更文件", size: 12, weight: .medium), files.scroll,
      ], spacing: 10)
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
    repositoryPicker.dismissMenu()
    branchPicker.dismissMenu()
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
    pathLabel.stringValue = path
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
        syncPickers()
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
  private func syncPickers() {
    let nameCounts = Dictionary(grouping: repositories, by: { $0.location.name }).mapValues(\.count)
    repositoryPicker.addItems(
      withTitles: ["所有仓库"]
        + repositories.map { repo in
          if nameCounts[repo.location.name, default: 0] > 1, repo.id.hasPrefix(root + "/") {
            return String(repo.id.dropFirst(root.count + 1))
          }
          return repo.location.name
        })
    if let index = repositories.firstIndex(where: { $0.id == selectedRepository }) {
      repositoryPicker.selectItem(at: index + 1)
    }
    let allReferences = repositories.first(where: { $0.id == selectedRepository })?.references ?? []
    branchChoices = Array(allReferences.prefix(200))
    if !selectedReference.isEmpty,
      !branchChoices.contains(where: { $0.fullName == selectedReference }),
      let chosen = allReferences.first(where: { $0.fullName == selectedReference })
    {
      branchChoices.append(chosen)
    }
    branchPicker.toolTip = allReferences.count > 200 ? "下拉显示前 200 项；完整分支请在左侧搜索" : "仅筛选历史，不切换工作分支"
    branchPicker.addItems(
      withTitles: ["所有分支"]
        + branchChoices.map {
          ($0.kind == .remote ? "远程 · " : $0.kind == .tag ? "标签 · " : "") + $0.name
        })
    if let index = branchChoices.firstIndex(where: { $0.fullName == selectedReference }) {
      branchPicker.selectItem(at: index + 1)
    } else {
      selectedReference = ""
    }
    branchPicker.isEnabled = selectedRepository != nil
  }
  @objc private func selectRepository() {
    let index = repositoryPicker.indexOfSelectedItem - 1
    selectedRepository = repositories.indices.contains(index) ? repositories[index].id : nil
    selectedReference = ""
    sidebar.select(repository: selectedRepository)
    syncPickers()
    reloadLog()
  }
  @objc private func selectBranch() {
    let index = branchPicker.indexOfSelectedItem - 1
    selectedReference = branchChoices.indices.contains(index) ? branchChoices[index].fullName : ""
    sidebar.select(repository: selectedRepository, reference: selectedReference)
    reloadLog()
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
    detailTitle.stringValue = "提交详情"
    detailMeta.stringValue = "选择一条提交"
    message.string = ""
    files.update([])
  }
  private func showCommit(_ commit: GitCommit) {
    guard let repository = repositories.first(where: { $0.id == commit.repository }) else { return }
    detailTask?.cancel()
    detailSerial += 1
    let serial = detailSerial
    selectedCommit = commit
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
