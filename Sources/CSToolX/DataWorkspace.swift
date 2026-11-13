import AppKit
import ToolCore

@MainActor
final class DataWorkspace: NSView {
  let profile: ConnectionProfile
  let sessionID: String
  private let engine: EngineClient
  private let editor: NSTextView
  private let targetField = Theme.field("ES 索引名称，例如 orders-*")
  private let status = Theme.label("按需读取 · 不自动扫描", size: 11, muted: true)
  private let note = Theme.label("结果最多 500 行 · 双击单元格展开", size: 10, muted: true)
  private let errorLabel = Theme.label("", size: 11)
  private let results = TextTable()
  private var output: QueryOutput?
  private var runButton: NSButton!
  private var catalogButton: NSButton!
  private var nextButton: NSButton!
  private var disconnectButton: NSButton!
  private var historyButton: NSButton!
  private var history: [String] = []
  private var historyMenu: PaperMenu?
  private(set) var busy = false
  var onCatalog: ((QueryOutput) -> Void)?
  var onDisconnect: (() -> Void)?

  init(profile: ConnectionProfile, sessionID: String, elapsed: Int, engine: EngineClient) {
    self.profile = profile
    self.sessionID = sessionID
    self.engine = engine
    let scroll = NSTextView.scrollableTextView()
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
    editor.string = profile.kind.initialQuery
    editor.setAccessibilityLabel(profile.kind == .redis ? "Redis key 模式" : "查询编辑器")
    let title = Theme.label(profile.displayName, size: 21, weight: .medium)
    let badge = Theme.label("\(profile.environment) · 查询模式", size: 10, muted: true)
    disconnectButton = Theme.button("断开", target: self, action: #selector(disconnect))
    let heading = Theme.stack([title, badge, NSView(), disconnectButton], vertical: false)
    let sub = Theme.label(
      "\(profile.kind.title) · \(profile.address) · 连接 \(elapsed) ms", size: 11, muted: true)
    catalogButton = Theme.button(
      profile.kind == .redis ? "读取 Keys" : "读取目录", target: self, action: #selector(catalog))
    historyButton = Theme.button("本次历史", target: self, action: #selector(showHistory))
    runButton = Theme.button("执行  ⌘↵", target: self, action: #selector(run), primary: true)
    runButton.keyEquivalent = "\r"
    runButton.keyEquivalentModifierMask = [.command]
    let toolbar = Theme.stack([catalogButton, historyButton, NSView(), runButton], vertical: false)
    targetField.isHidden = profile.kind != .es
    nextButton = Theme.button("下一批 →", target: self, action: #selector(nextBatch))
    nextButton.isHidden = true
    let resultBar = Theme.stack(
      [Theme.label("结果", size: 12, weight: .medium), status, NSView(), nextButton], vertical: false)
    errorLabel.textColor = NSColor(srgbRed: 0.65, green: 0.39, blue: 0.30, alpha: 1)
    errorLabel.maximumNumberOfLines = 2
    errorLabel.isHidden = true
    let root = Theme.stack(
      [
        heading, sub, Theme.separator(), toolbar, targetField, scroll, errorLabel, resultBar,
        results.scroll, note,
      ], spacing: 12)
    root.alignment = .leading
    Theme.pin(root, to: self, inset: 26)
    for view in [
      heading, sub, toolbar, targetField, scroll, errorLabel, resultBar, results.scroll, note,
    ] {
      view.translatesAutoresizingMaskIntoConstraints = false
      view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
    }
    scroll.heightAnchor.constraint(equalToConstant: profile.kind == .redis ? 100 : 170).isActive =
      true
    results.scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
    results.onActivate = { [weak self] row, col in self?.activate(row: row, column: col) }
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
  @objc private func catalog() { perform(action: "catalog", text: "*") }
  @objc private func nextBatch() {
    guard let cursor = output?.nextCursor, cursor != "0" else { return }
    perform(action: "query", text: editor.string, cursor: cursor)
  }
  func preview(_ row: [JSONValue]) {
    guard !busy else { return }
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
    if profile.kind == .es { targetField.stringValue = target }
    perform(action: "preview", text: editor.string, target: target)
  }
  private func setBusy(_ value: Bool) {
    busy = value
    for button in [runButton, catalogButton, nextButton, disconnectButton, historyButton] {
      button?.isEnabled = !value
    }
    status.stringValue = value ? "等待响应…" : "按需读取"
  }
  private func perform(action: String, text: String, target: String? = nil, cursor: String = "0") {
    guard !busy else { return }
    errorLabel.isHidden = true
    setBusy(true)
    let target = target ?? targetField.stringValue
    Task { [weak self] in
      guard let self else { return }
      do {
        let response = try await engine.run(
          id: sessionID, action: action, text: text, target: target, cursor: cursor)
        let displayRows = await Task.detached {
          response.rows.map { row in
            row.map { value in
              let text = value.text
              return text.count > 2048 ? String(text.prefix(2048)) + "…" : text
            }
          }
        }.value
        setBusy(false)
        if action == "catalog" {
          onCatalog?(response)
          status.stringValue = "目录 \(response.rows.count) 项 · \(response.elapsedMs) ms"
        } else {
          output = response
          results.setColumns(response.columns)
          results.update(displayRows)
          status.stringValue =
            "\(response.rows.count) 行 · \(response.elapsedMs) ms\(response.truncated ? " · 展示已截断" : "")"
          note.stringValue = response.note
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
    guard let output, row < output.rows.count else { return }
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
