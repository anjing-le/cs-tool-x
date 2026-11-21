import AppKit
import ToolCore

@MainActor final class TextStatisticsModel {
  private enum Update {
    case reset(String, Int)
    case edit(NSRange, String, Int, Int)
  }
  private let worker = TextStatisticsWorker()
  private var pending: [Update] = []
  private var processing: Task<Void, Never>?, selectionTask: Task<Void, Never>?,
    badgeTask: Task<Void, Never>?
  private var generation = 0, selectionGeneration = 0, revision = 0, publishedRevision = -1
  private var suspended = false, needsReset = false
  var isCurrent: Bool { publishedRevision == revision && processing == nil }
  private(set) var snapshot: TextStatistics?
  private(set) var selected: TextStatistics?
  var source: (() -> (String, Int))?
  var selection: (() -> ([NSRange], Int))?
  var changed: ((TextStatistics?, TextStatistics?, Bool) -> Void)?
  init() { reset("", revision: 0) }
  func reset(_ text: String, revision: Int) {
    generation += 1
    processing?.cancel()
    processing = nil
    selectionTask?.cancel()
    badgeTask?.cancel()
    pending = [.reset(text, revision)]
    self.revision = revision
    publishedRevision = -1
    snapshot = text.isEmpty ? TextStatistics() : nil
    selected = nil
    needsReset = false
    changed?(snapshot, nil, !text.isEmpty)
    if !suspended { start() }
  }
  func edit(_ range: NSRange, replacement: String, before: Int, revision: Int) {
    self.revision = revision
    selected = nil
    if pending.count >= 256 {
      resync()
      return
    }
    pending.append(.edit(range, replacement, before, revision))
    guard !suspended else {
      needsReset = true
      return
    }
    if badgeTask == nil {
      let token = generation
      badgeTask = Task { [weak self] in
        try? await Task.sleep(nanoseconds: 200_000_000)
        guard let self, !Task.isCancelled, self.generation == token,
          self.publishedRevision != self.revision
        else { return }
        self.changed?(self.snapshot, nil, true)
      }
    }
    start()
  }
  private func resync() {
    guard let (text, revision) = source?() else { return }
    reset(text, revision: revision)
  }
  private func start() {
    guard processing == nil, !pending.isEmpty, !suspended else { return }
    let token = generation
    processing = Task { [weak self] in
      guard let self else { return }
      while self.generation == token, !Task.isCancelled, !self.pending.isEmpty {
        let update = self.pending.removeFirst()
        do {
          let result: TextStatistics?
          let appliedRevision: Int
          switch update {
          case .reset(let text, let revision):
            result = try await self.worker.reset(text, revision: revision)
            appliedRevision = revision
          case .edit(let range, let text, let before, let revision):
            result = try await self.worker.edit(
              range, replacement: text, before: before, revision: revision)
            appliedRevision = revision
          }
          guard !Task.isCancelled, self.generation == token else { return }
          guard let result else {
            self.resync()
            return
          }
          if appliedRevision == self.revision, self.pending.isEmpty {
            self.snapshot = result
            self.selected = nil
            self.publishedRevision = appliedRevision
            self.badgeTask?.cancel()
            self.badgeTask = nil
            self.changed?(result, nil, false)
          }
        } catch {
          guard !Task.isCancelled, self.generation == token else { return }
          self.resync()
          return
        }
      }
      guard self.generation == token else { return }
      self.processing = nil
      self.refreshSelection()
    }
  }
  func refreshSelection() {
    selectionGeneration += 1
    let token = selectionGeneration
    let documentToken = generation
    selectionTask?.cancel()
    guard !suspended, let (ranges, expected) = selection?(),
      ranges.contains(where: { $0.length > 0 })
    else {
      if selected != nil {
        selected = nil
        changed?(snapshot, nil, publishedRevision != revision)
      }
      return
    }
    selectionTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 120_000_000)
      guard let self, !Task.isCancelled, self.generation == documentToken else { return }
      let value = try? await self.worker.selection(ranges, revision: expected)
      guard !Task.isCancelled, self.selectionGeneration == token, self.generation == documentToken,
        let current = self.selection?(), current.1 == expected, current.0 == ranges, let value
      else { return }
      self.selected = value
      self.changed?(self.snapshot, value, self.publishedRevision != self.revision)
    }
  }
  func suspend() {
    needsReset = processing != nil || publishedRevision != revision
    suspended = true
    generation += 1
    selectionGeneration += 1
    processing?.cancel()
    processing = nil
    badgeTask?.cancel()
    badgeTask = nil
    selectionTask?.cancel()
    selected = nil
    pending.removeAll()
  }
  func resume() {
    guard suspended else {
      refreshSelection()
      return
    }
    suspended = false
    if needsReset {
      resync()
    } else {
      start()
      changed?(snapshot, nil, publishedRevision != revision)
      refreshSelection()
    }
  }
}

@MainActor final class TextStatisticsFooter: NSStackView {
  private let main = NSTextField(wrappingLabelWithString: "")
  private let detail = NSTextField(wrappingLabelWithString: "")
  private var lastWidth: CGFloat = 0
  private let number: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.locale = Locale(identifier: "zh_CN")
    return f
  }()
  override init(frame: NSRect) {
    super.init(frame: frame)
    orientation = .vertical
    alignment = .leading
    spacing = 3
    for label in [main, detail] {
      label.font = Theme.font(12)
      label.textColor = Theme.muted
      label.maximumNumberOfLines = 0
      label.setContentCompressionResistancePriority(.required, for: .vertical)
      label.setAccessibilityLabel("源文本统计")
      addArrangedSubview(label)
      label.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
    }
    render(TextStatistics(), selected: nil, updating: false)
  }
  required init?(coder: NSCoder) { nil }
  override func layout() {
    if abs(bounds.width - lastWidth) > 1 {
      lastWidth = bounds.width
      for label in [main, detail] {
        label.preferredMaxLayoutWidth = max(1, bounds.width)
        label.invalidateIntrinsicContentSize()
      }
    }
    super.layout()
  }
  private func n(_ value: Int) -> String {
    number.string(from: NSNumber(value: value)) ?? String(value)
  }
  func render(_ value: TextStatistics?, selected: TextStatistics?, updating: Bool) {
    guard let value else {
      main.stringValue = "字数统计中…"
      detail.stringValue = ""
      return
    }
    main.stringValue =
      "\(n(value.nonWhitespace)) 字 · \(n(value.characters)) 字符 · \(n(value.han)) 汉字 · \(n(value.englishWords)) 英文词 · \(n(value.digits)) 数字 · \(n(value.punctuation)) 标点"
      + (updating ? " · 更新中…" : "")
    let bytes = ByteCountFormatter()
    bytes.countStyle = .binary
    bytes.allowsNonnumericFormatting = false
    detail.stringValue =
      "\(n(value.lines)) 行 · \(n(value.emptyLines)) 空行 · \(n(value.paragraphs)) 段 · \(n(value.whitespace)) 空白 · \(bytes.string(fromByteCount: Int64(value.utf8Bytes)))"
    if let selected, selected.characters > 0 {
      detail.stringValue +=
        " · 已选 \(n(selected.nonWhitespace)) 字 / \(n(selected.characters)) 字符 / \(n(selected.lines)) 行"
    }
    let rules =
      "按源文本统计，包含 Markdown 标记。字数＝非空白字符，含标点；字符按 Unicode 组合字符计数（组合 emoji 算 1），含空白/换行，CRLF 算一个字符。汉字按 Unicode Han；英文词按连续 A–Z/a–z，可含词内撇号；数字为十进制数字字符。空行包括仅空白的行；段落按空白行分隔，空文为 0 行。选区统计仅编辑模式。"
    main.toolTip = rules
    detail.toolTip =
      rules
      + "\n精确大小：\(n(value.utf8Bytes)) UTF-8 字节；\(n(value.utf16Units)) UTF-16 单元；\(n(value.nonEmptyLines)) 非空行。"
  }
}
