import AppKit
import ToolCore
import WebKit

@MainActor final class TransientTextWorkspace: NSView, WKNavigationDelegate {
  let writing = TransientTextEditor()
  let statistics = TextStatisticsModel()
  private let statisticsFooter = TextStatisticsFooter(frame: .zero)
  var workerURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/cs-tool-markdown")
  var hasPendingWork: Bool { work != nil }
  var previewView: WKWebView? { web }
  private let content = NSView()
  private let status = Theme.label("临时 · 退出后清空", muted: true)
  private let editButton = PaperButton(frame: .zero), previewButton = PaperButton(frame: .zero)
  private let fontChoice = PaperSelect(frame: .zero)
  private let wrapButton = PaperButton(frame: .zero)
  private let cancelButton = PaperIconButton(
    symbol: "stop", label: "取消读取或预览", target: nil,
    action: #selector(TransientTextWorkspace.cancelWork))
  private let confirmation = NSStackView()
  private var replacementAction: (() -> Void)?
  private var work: Task<Void, Never>?
  private var generation = 0
  private var web: WKWebView?
  private var cachedHTML: String?
  private var cachedRevision = -1
  private(set) var showingPreview = false
  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.backgroundColor = Theme.paper.cgColor
    let fresh = PaperIconButton(
      symbol: "square.and.pencil", label: "清空临时文本", target: self, action: #selector(newText))
    let read = PaperIconButton(
      symbol: "folder", label: "导入 UTF-8 文本，不修改原文件", target: self, action: #selector(importText))
    editButton.title = "编辑"
    editButton.primary = true
    editButton.target = self
    editButton.action = #selector(showEditor)
    previewButton.title = "预览"
    previewButton.target = self
    previewButton.action = #selector(togglePreview)
    previewButton.keyEquivalent = "/"
    previewButton.keyEquivalentModifierMask = [.command]
    previewButton.toolTip = "Markdown 预览 ⌘/"
    fontChoice.addItems(withTitles: ["纸面", "等宽"])
    fontChoice.onChange(target: self, action: #selector(fontChanged))
    fontChoice.widthAnchor.constraint(equalToConstant: 100).isActive = true
    wrapButton.title = "折行"
    wrapButton.checkbox = true
    wrapButton.state = .on
    wrapButton.target = self
    wrapButton.action = #selector(wrapChanged)
    cancelButton.target = self
    cancelButton.action = #selector(cancelWork)
    cancelButton.isHidden = true
    let spacer = NSView()
    spacer.setContentHuggingPriority(.init(1), for: .horizontal)
    let toolbar = Theme.stack(
      [
        fresh, read, NSView(), editButton, previewButton, spacer, fontChoice, wrapButton,
        cancelButton,
      ], vertical: false, spacing: 14)
    let yes = Theme.button("替换", target: self, action: #selector(confirmReplace), primary: true)
    let no = Theme.button("保留", target: self, action: #selector(keepText))
    confirmation.orientation = .horizontal
    confirmation.spacing = 10
    confirmation.addArrangedSubview(yes)
    confirmation.addArrangedSubview(no)
    confirmation.isHidden = true
    let footer = Theme.stack([status, confirmation], vertical: false, spacing: 12)
    status.setContentHuggingPriority(.init(1), for: .horizontal)
    status.toolTip = "仅在本次运行内保留，不保存、不自动恢复；纯文本 32 MiB、单行 128 KiB，Markdown 完整预览 4 MiB"
    let root = Theme.stack([toolbar, content, statisticsFooter, footer], spacing: 8)
    Theme.pin(root, to: self, inset: 16)
    for view in root.arrangedSubviews {
      view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
    }
    Theme.pin(writing, to: content)
    statistics.source = { [weak self] in
      guard let self else { return ("", 0) }
      return (self.writing.editor.string, self.writing.revision)
    }
    statistics.selection = { [weak self] in
      guard let self, !self.showingPreview, !self.writing.editor.hasMarkedText() else {
        return ([], -1)
      }
      return (self.writing.editor.selectedRanges.map(\.rangeValue), self.writing.revision)
    }
    statistics.changed = { [weak self] value, selected, updating in
      self?.statisticsFooter.render(value, selected: selected, updating: updating)
    }
    writing.statisticsReset = { [weak self] text, revision in
      self?.statistics.reset(text, revision: revision)
    }
    writing.statisticsEdited = { [weak self] range, text, before, revision in
      self?.statistics.edit(range, replacement: text, before: before, revision: revision)
    }
    writing.selectionChanged = { [weak self] in self?.statistics.refreshSelection() }
    writing.editor.togglePreview = { [weak self] in self?.togglePreview() }
    writing.changed = { [weak self] in
      guard let self else { return }
      self.cachedHTML = nil
      self.cachedRevision = -1
      self.clearConfirmation()
      self.updateStatus()
    }
    writing.largeModeActivated = { [weak self] in self?.wrapButton.state = .off }
    writing.rejected = { [weak self] in self?.message($0) }
  }
  required init?(coder: NSCoder) { nil }
  func activate() {
    statistics.resume()
    writing.editor.isEditable = !showingPreview
    if showingPreview {
      window?.makeFirstResponder(web)
    } else {
      window?.makeFirstResponder(writing.editor)
    }
  }
  func pause() {
    statistics.suspend()
    if let responder = window?.firstResponder as? NSView, responder.isDescendant(of: self) {
      window?.makeFirstResponder(nil)
    }
    generation += 1
    work?.cancel()
    work = nil
    writing.editor.isEditable = !showingPreview
    writing.pause()
    cancelButton.isHidden = true
    if showingPreview, cachedHTML == nil { showEditor() }
    clearConfirmation()
  }
  private func message(_ text: String) {
    status.stringValue = text
    status.toolTip = text
  }
  private func updateStatus() {
    message("临时" + (showingPreview ? " · 图片不加载" : " · 退出后清空"))
  }
  @objc func showEditor() {
    generation += 1
    work?.cancel()
    work = nil
    cancelButton.isHidden = true
    showingPreview = false
    statistics.refreshSelection()
    writing.isHidden = false
    writing.editor.isEditable = true
    web?.isHidden = true
    web?.stopLoading()
    // Release the rendered DOM while retaining a small, bounded HTML cache for an unchanged revision.
    web?.loadHTMLString("", baseURL: nil)
    editButton.primary = true
    previewButton.primary = false
    fontChoice.isEnabled = true
    wrapButton.isEnabled = true
    updateStatus()
    window?.makeFirstResponder(writing.editor)
  }
  @objc func togglePreview() {
    if showingPreview {
      showEditor()
      return
    }
    guard !writing.editor.hasMarkedText() else {
      message("请先完成输入法候选，再切换预览")
      return
    }
    guard writing.byteCount <= TextWorkbench.previewBytes else {
      message("Markdown 完整预览上限 4 MiB；32 MiB 以内正文仍可编辑，不截断")
      return
    }
    work?.cancel()
    work = nil
    clearConfirmation()
    generation += 1
    let token = generation
    let revision = writing.revision
    showingPreview = true
    statistics.refreshSelection()
    editButton.primary = false
    previewButton.primary = true
    fontChoice.isEnabled = false
    wrapButton.isEnabled = false
    writing.isHidden = true
    writing.editor.isEditable = false
    window?.makeFirstResponder(nil)
    writing.pause()
    if let cachedHTML, cachedRevision == revision {
      display(cachedHTML)
      return
    }
    message("解析 Markdown…")
    cancelButton.isHidden = false
    let snapshot = writing.editor.string
    let executable = workerURL
    work = Task { [weak self] in
      do {
        let html = try await TextWorkbench.preview(snapshot, executable: executable)
        guard let self, self.generation == token, self.writing.revision == revision,
          !Task.isCancelled
        else { return }
        self.cachedHTML = html
        self.cachedRevision = revision
        self.work = nil
        self.cancelButton.isHidden = true
        self.display(html)
      } catch {
        guard let self, self.generation == token, !Task.isCancelled else { return }
        self.showEditor()
        self.message(error.localizedDescription)
      }
    }
  }
  private func display(_ body: String) {
    if web == nil {
      let configuration = WKWebViewConfiguration()
      configuration.websiteDataStore = .nonPersistent()
      configuration.defaultWebpagePreferences.allowsContentJavaScript = false
      let view = WKWebView(frame: .zero, configuration: configuration)
      view.navigationDelegate = self
      view.setAccessibilityLabel("Markdown 预览")
      web = view
      Theme.pin(view, to: content)
    }
    web?.isHidden = false
    web?.loadHTMLString(TextWorkbench.page(body), baseURL: nil)
    window?.makeFirstResponder(web)
    updateStatus()
  }
  func webView(
    _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url,
      ["https", "http"].contains(url.scheme?.lowercased() ?? "")
    {
      NSWorkspace.shared.open(url)
    }
    decisionHandler(
      navigationAction.navigationType == .other && navigationAction.request.url?.scheme == "about"
        ? .allow : .cancel)
  }
  @objc private func cancelWork() {
    showEditor()
    message("已取消，正文保留")
  }
  @objc private func fontChanged() { writing.paper = fontChoice.indexOfSelectedItem == 0 }
  @objc private func wrapChanged() { writing.wraps = wrapButton.state == .on }
  @objc private func newText() {
    replaceAfterConfirmation { [weak self] in
      self?.showEditor()
      self?.writing.replace("", bytes: 0)
    }
  }
  private func replaceAfterConfirmation(_ action: @escaping () -> Void) {
    if writing.byteCount == 0 {
      action()
      return
    }
    replacementAction = action
    confirmation.isHidden = false
    message("替换当前临时文本？无法恢复原文")
  }
  private func clearConfirmation() {
    replacementAction = nil
    confirmation.isHidden = true
  }
  @objc private func confirmReplace() {
    let action = replacementAction
    clearConfirmation()
    action?()
  }
  @objc private func keepText() {
    clearConfirmation()
    updateStatus()
  }
  @objc private func importText() { replaceAfterConfirmation { [weak self] in self?.chooseText() } }
  private func chooseText() {
    guard let window else { return }
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.message = "导入 UTF-8 文本到临时编辑区，不修改原文件；最多 32 MiB"
    panel.beginSheetModal(for: window) { [weak self] response in
      guard let self, response == .OK, let url = panel.url else { return }
      self.importFile(url)
    }
  }
  func importFile(_ url: URL) {
    showEditor()
    generation += 1
    let token = generation
    writing.editor.isEditable = false
    cancelButton.isHidden = false
    message("读取文本…")
    work = Task { [weak self] in
      do {
        guard let executable = self?.workerURL else { return }
        let text = try await TextWorkbench.importText(url, executable: executable)
        let bytes = text.utf8.count
        guard let self, self.generation == token, !Task.isCancelled else { return }
        // Very long source lines start unwrapped; the user can opt back into wrapping.
        if bytes > 2 * 1024 * 1024 {
          self.writing.wraps = false
          self.wrapButton.state = .off
        }
        self.writing.replace(text, bytes: bytes, validated: true)
        self.writing.editor.isEditable = true
        self.work = nil
        self.cancelButton.isHidden = true
        self.activate()
      } catch {
        guard let self, self.generation == token, !Task.isCancelled else { return }
        self.work = nil
        self.cancelButton.isHidden = true
        self.writing.editor.isEditable = true
        self.message(error.localizedDescription)
      }
    }
  }
}
