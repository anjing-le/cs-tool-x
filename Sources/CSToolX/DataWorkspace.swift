import AppKit
import ToolCore

@MainActor
final class DataWorkspace: NSView, NSTextFieldDelegate, NSTextViewDelegate {
  let profile: ConnectionProfile
  let sessionID: String
  private let engine: EngineClient
  private var pendingPreview: [JSONValue]?
  private let editor: NSTextView
  private let editorScroll: NSScrollView
  private let resultFilter = Theme.field("筛选结果…")
  private let context = Theme.label("", size: 11, muted: true)
  private var projection: ResultProjection?
  private var shownIndices: [Int] = []
  private var browseButton: PaperButton!
  private var queryButton: PaperButton!
  private(set) var queryMode = true
  private var suggestedQuery: String
  private let targetField = Theme.field("ES 索引名称，例如 orders-*")
  private let status = Theme.label("", size: 11, muted: true)
  private let note = Theme.label("", size: 10, muted: true)
  private let errorLabel = Theme.label("", size: 11)
  private let results = TextTable()
  private var output: QueryOutput?
  private var runButton: NSButton!
  private var nextButton: NSButton!
  private var disconnectButton: NSButton!
  private var historyButton: NSButton!
  private var history: [String] = []
  private var historyMenu: PaperMenu?
  private(set) var busy = false
  var onInteraction: (() -> Void)?
  func textDidChange(_ notification: Notification) { onInteraction?() }
  var onDisconnect: (() -> Void)?

  init(profile: ConnectionProfile, sessionID: String, elapsed: Int, engine: EngineClient) {
    self.profile = profile
    self.sessionID = sessionID
    self.engine = engine
    let scroll = NSTextView.scrollableTextView()
    editorScroll = scroll
    suggestedQuery = profile.kind.initialQuery
    editor = scroll.documentView as! NSTextView
    super.init(frame: .zero)
    editor.textColor = Theme.ink
    editor.insertionPointColor = Theme.sage
    editor.selectedTextAttributes = [.backgroundColor: Theme.pale, .foregroundColor: Theme.ink]
    editor.isRichText = false
    editor.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
    editor.textContainerInset = NSSize(width: 13, height: 12)
    editor.backgroundColor = Theme.paper
    editor.isAutomaticQuoteSubstitutionEnabled = false
    editor.isAutomaticDashSubstitutionEnabled = false
    editor.isAutomaticSpellingCorrectionEnabled = false
    editor.isContinuousSpellCheckingEnabled = false
    editor.delegate = self
    editor.string = profile.kind.initialQuery
    editor.setAccessibilityLabel(profile.kind == .redis ? "Redis key 模式" : "查询编辑器")
    disconnectButton = Theme.button("断开", target: self, action: #selector(disconnect))
    toolTip = profile.displayName + " · " + profile.address + " · " + profile.environment
    historyButton = PaperIconButton(symbol: "clock", label: "本次查询历史", target: self, action: #selector(showHistory))
    runButton = Theme.button("执行", target: self, action: #selector(run), primary: true)
    runButton.keyEquivalent = "\r"
    runButton.keyEquivalentModifierMask = [.command]
    browseButton = Theme.button("数据", target: self, action: #selector(selectBrowse)) as? PaperButton
    queryButton = Theme.button("查询", target: self, action: #selector(selectQuery)) as? PaperButton
    context.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    context.stringValue = profile.kind == .es ? "选择索引" : profile.database
    let environment = Theme.label(profile.environment, size: 10, muted: true)
    environment.isHidden = profile.environment.isEmpty
    let toolbar = Theme.stack(
      [browseButton, queryButton, context, NSView(), environment, historyButton, runButton],
      vertical: false, spacing: 8)
    toolbar.detachesHiddenViews = true
    targetField.isHidden = profile.kind != .es
    nextButton = Theme.button("下一批 →", target: self, action: #selector(nextBatch))
    nextButton.isHidden = true
    runButton.toolTip = "执行 ⌘↵"
    note.isHidden = true
    results.scroll.toolTip = "双击单元格查看完整内容"
    resultFilter.delegate = self
    resultFilter.setAccessibilityLabel("筛选当前结果")
    let resultBar = Theme.stack([resultFilter, status, NSView(), nextButton], vertical: false)
    resultFilter.widthAnchor.constraint(equalToConstant: 220).isActive = true
    errorLabel.textColor = NSColor(srgbRed: 0.65, green: 0.39, blue: 0.30, alpha: 1)
    errorLabel.maximumNumberOfLines = 2
    errorLabel.isHidden = true
    let root = Theme.stack(
      [
        toolbar, targetField, scroll, errorLabel, resultBar,
        results.scroll, note,
      ], spacing: 12)
    root.alignment = .leading
    root.detachesHiddenViews = true
    Theme.pin(root, to: self, inset: 16)
    for view in [
      toolbar, targetField, scroll, errorLabel, resultBar, results.scroll, note,
    ] {
      view.translatesAutoresizingMaskIntoConstraints = false
      view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
    }
    scroll.heightAnchor.constraint(equalToConstant: profile.kind == .redis ? 100 : 170).isActive =
      true
    results.scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
    results.onActivate = { [weak self] row, col in self?.activate(row: row, column: col) }
    setQueryMode(true)
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
  @objc private func run() {
    let ns = editor.string as NSString
    let range = editor.selectedRange()
    let sql = profile.kind == .mysql || profile.kind == .pg
    let text =
      sql && range.length > 0 && NSMaxRange(range) <= ns.length
      ? ns.substring(with: range) : editor.string
    perform(action: "query", text: text)
  }
  @objc private func nextBatch() {
    guard let cursor = output?.nextCursor, cursor != "0" else { return }
    perform(action: "query", text: editor.string, cursor: cursor)
  }
  func preview(_ row: [JSONValue]) {
    guard !busy else {
      pendingPreview = row
      return
    }
    let target: String
    if profile.kind == .mysql || profile.kind == .pg {
      guard row.count >= 2, let encoded = try? JSONEncoder().encode([row[0].text, row[1].text]),
        let text = String(data: encoded, encoding: .utf8)
      else { return }
      target = text
    } else {
      guard let first = row.first else { return }
      target = first.text
    }
    setQueryMode(false)
    if profile.kind == .mysql || profile.kind == .pg {
      if let query = DataObjectQuery.select(
        kind: profile.kind, schema: row[0].text, table: row[1].text)
      {
        if editor.string == suggestedQuery { editor.string = query }
        suggestedQuery = query
      }
      context.stringValue = row[0].text + "." + row[1].text
    } else {
      context.stringValue = row.first?.text ?? profile.database
    }
    context.toolTip = context.stringValue
    if profile.kind == .es { targetField.stringValue = target }
    perform(action: "preview", text: editor.string, target: target)
  }
  private func setBusy(_ value: Bool) {
    busy = value
    for button in [
      runButton, nextButton, disconnectButton, historyButton, browseButton,
      queryButton,
    ] {
      button?.isEnabled = !value
    }
    status.stringValue = value ? "等待响应…" : ""
  }
  private func perform(action: String, text: String, target: String? = nil, cursor: String = "0") {
    guard !busy else { return }
    errorLabel.isHidden = true
    setBusy(true)
    let target = target ?? targetField.stringValue
    Task { [weak self] in
      guard let self else { return }
      defer {
        if let row = pendingPreview {
          pendingPreview = nil
          preview(row)
        }
      }
      do {
        let response = try await engine.run(
          id: sessionID, action: action, text: text, target: target, cursor: cursor)
        let rendered = await Task.detached { ResultProjection(response) }.value
        setBusy(false)
        if action == "catalog" {
          status.stringValue = "目录 \(response.rows.count) 项 · \(response.elapsedMs) ms"
        } else {
          output = response
          results.setColumns(response.columns)
          projection = rendered
          applyResultFilter()
          note.stringValue = response.truncated ? "结果已截断，请缩小查询范围" : ""
          note.toolTip = response.note
          note.isHidden = note.stringValue.isEmpty
          nextButton.isHidden =
            profile.kind != .redis || response.nextCursor == nil || response.nextCursor == "0"
          if action == "query" {
            history.removeAll { $0 == text }
            history.insert(text, at: 0)
            history = Array(history.prefix(30))
          }
        }
      } catch {
        setBusy(false)
        errorLabel.stringValue = error.localizedDescription
        errorLabel.isHidden = false
      }
    }
  }
  private func activate(row: Int, column: Int) {
    guard let output, shownIndices.indices.contains(row) else { return }
    let row = shownIndices[row]
    guard output.rows.indices.contains(row) else { return }
    if profile.kind == .redis && output.columns.count == 1 {
      preview(output.rows[row])
      return
    }
    guard column < output.rows[row].count else { return }
    let raw = output.rows[row][column]
    Task { [weak self] in
      guard let self else { return }
      let text = await Task.detached {
        var text = raw.text
        if case .object = raw {
          let encoder = JSONEncoder()
          encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
          text = (try? String(data: encoder.encode(raw), encoding: .utf8)) ?? text
        }
        return text
      }.value
      guard let window = self.window, window.attachedSheet == nil else { return }
      PaperDialog.show(title: output.columns[column], text: text, window: window, detail: true)
    }
  }
  func showQuery() { setQueryMode(true) }
  private func setQueryMode(_ query: Bool) {
    queryMode = query
    browseButton?.selected = !query
    queryButton?.selected = query
    editorScroll.isHidden = !query
    targetField.isHidden = !query || profile.kind != .es
    runButton?.isHidden = !query
    historyButton?.isHidden = !query
  }
  @objc private func selectBrowse() {
    onInteraction?()
    setQueryMode(false)
  }
  @objc private func selectQuery() {
    onInteraction?()
    setQueryMode(true)
  }
  func controlTextDidChange(_ obj: Notification) { applyResultFilter() }
  private func applyResultFilter() {
    guard let projection else { return }
    shownIndices = projection.indices(matching: resultFilter.stringValue)
    results.update(shownIndices.map { projection.rows[$0] })
    if !busy, let output {
      let amount =
        shownIndices.count == projection.rows.count
        ? "\(shownIndices.count) 行" : "\(shownIndices.count) / \(projection.rows.count) 行"
      status.stringValue = amount + " · \(output.elapsedMs) ms" + (output.truncated ? " · 已截断" : "")
    }
  }
  @objc private func showHistory() {
    historyMenu?.dismiss()
    let titles =
      history.isEmpty
      ? ["本次会话暂无历史"]
      : history.map {
        String($0.replacingOccurrences(of: "\n", with: " ").prefix(90))
      }
    historyMenu = PaperMenu(titles: titles, enabled: !history.isEmpty, anchor: historyButton) {
      [weak self] index in
      guard let self, history.indices.contains(index) else { return }
      editor.string = history[index]
    }
    historyMenu?.show()
  }
  func requestDisconnect() { disconnect() }
  @objc private func disconnect() {
    guard !busy else { return }
    setBusy(true)
    Task { [weak self] in
      guard let self else { return }
      do {
        try await engine.disconnect(id: sessionID)
        setBusy(false)
        onDisconnect?()
      } catch {
        setBusy(false)
        Theme.error(error, window: window)
      }
    }
  }
}
