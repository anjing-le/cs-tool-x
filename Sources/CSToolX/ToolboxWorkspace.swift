import AppKit
import SwiftUI
import ToolCore

@MainActor final class ToolboxWorkspace: NSView {
  private var task: Task<Void, Never>?
  private var generation = 0
  private var item: ToolboxItem?
  private var mode = PaperSelect(frame: .zero)
  private var source = ToolboxText(), second = ToolboxText(), output = ToolboxText()
  private var other = Theme.field(""), replacement = Theme.field("替换为…，支持 $1")
  private var length = Theme.field("长度"), count = Theme.field("数量")
  private var status = Theme.label("", muted: true)
  private var runButton = PaperButton(frame: .zero)
  private var file: String?
  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
    layer?.backgroundColor = Theme.paper.cgColor
    showGrid()
  }
  required init?(coder: NSCoder) { nil }
  func pause() {
    generation += 1
    task?.cancel()
    task = nil
    runButton.isEnabled = true
    if item?.id == "random" { output.text.string = "" }
    status.stringValue = ""
  }
  private func showGrid() {
    pause()
    item = nil
    subviews.forEach { $0.removeFromSuperview() }
    let grid = NSHostingView(rootView: ToolboxGrid { [weak self] in self?.open($0) })
    Theme.pin(grid, to: self)
  }
  func open(_ item: ToolboxItem) {
    pause()
    self.item = item
    file = nil
    subviews.forEach { $0.removeFromSuperview() }
    source = ToolboxText()
    second = ToolboxText()
    output = ToolboxText(editable: false)
    other = Theme.field(item.id == "regex" ? "正则表达式 · ICU" : "校验值，可选")
    replacement = Theme.field("替换为…，支持 $1")
    mode = PaperSelect(frame: .zero)
    mode.addItems(withTitles: item.modes.map { Self.modeNames[$0] ?? $0 })
    mode.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
    mode.onChange(target: self, action: #selector(modeChanged))
    let back = PaperIconButton(
      symbol: "square.grid.2x2", label: "百宝箱", target: self, action: #selector(back))
    runButton = PaperButton(frame: .zero)
    runButton.title = "运行"
    runButton.primary = true
    runButton.target = self
    runButton.action = #selector(run)
    runButton.keyEquivalent = "\r"
    runButton.keyEquivalentModifierMask = [.command]
    let cancel = PaperIconButton(
      symbol: "stop", label: "取消计算", target: self, action: #selector(cancel))
    let copy = PaperIconButton(
      symbol: "doc.on.doc", label: "复制结果", target: self, action: #selector(copyResult))
    let spacer = NSView()
    spacer.setContentHuggingPriority(.init(1), for: .horizontal)
    let toolbar = Theme.stack(
      [back, Theme.label(item.name, size: 16), mode, spacer, runButton, cancel, copy],
      vertical: false, spacing: 14)
    let column = NSStackView()
    column.orientation = .vertical
    column.alignment = .leading
    column.spacing = 14
    column.addArrangedSubview(toolbar)
    var inputArea: NSView?
    if item.id == "random" {
      length = Theme.field("长度")
      length.stringValue = "24"
      length.widthAnchor.constraint(equalToConstant: 90).isActive = true
      count = Theme.field("数量")
      count.stringValue = "1"
      count.widthAnchor.constraint(equalToConstant: 90).isActive = true
      column.addArrangedSubview(
        Theme.stack(
          [Theme.label("长度", muted: true), length, Theme.label("数量", muted: true), count],
          vertical: false))
    } else {
      if item.id == "regex" {
        column.addArrangedSubview(other)
        column.addArrangedSubview(replacement)
      }
      if item.id == "hash" {
        let choose = Theme.button("选择文件", target: self, action: #selector(chooseFile))
        let clear = Theme.button("使用文本", target: self, action: #selector(clearFile))
        column.addArrangedSubview(Theme.stack([choose, clear, other], vertical: false))
      }
      if item.id == "diff" {
        let pair = Theme.stack([source, second], vertical: false, spacing: 14)
        pair.distribution = .fillEqually
        column.addArrangedSubview(pair)
        inputArea = pair
        source.setAccessibilityLabel("原文本")
        second.setAccessibilityLabel("新文本")
      } else {
        column.addArrangedSubview(source)
        inputArea = source
        source.setAccessibilityLabel("输入")
      }
    }
    status = Theme.label("", muted: true)
    status.lineBreakMode = .byTruncatingMiddle
    status.setContentHuggingPriority(.required, for: .vertical)
    column.addArrangedSubview(status)
    column.addArrangedSubview(output)
    inputArea?.heightAnchor.constraint(equalTo: output.heightAnchor).isActive = true
    output.setAccessibilityLabel("结果")
    for view in column.arrangedSubviews {
      view.translatesAutoresizingMaskIntoConstraints = false
      view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
    }
    output.heightAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
    Theme.pin(column, to: self, inset: 26)
    modeChanged()
    window?.makeFirstResponder(item.id == "random" ? length : source.text)
  }
  private var selectedMode: String {
    guard let item else { return "" }
    return item.modes[mode.indexOfSelectedItem]
  }
  @objc private func modeChanged() {
    if task != nil {
      pause()
      output.text.string = ""
    }
    replacement.isHidden = item?.id != "regex" || selectedMode != "replace"
    if item?.id == "timestamp" {
      source.text.toolTip =
        selectedMode.hasSuffix("to-date")
        ? "数字时间戳，单位见所选模式" : "ISO 8601，必须包含时区，例如 2026-11-21T08:00:00+08:00"
    }
  }
  @objc private func back() { showGrid() }
  @objc private func cancel() {
    pause()
    status.stringValue = "已取消本地计算"
  }
  @objc private func copyResult() {
    guard !output.text.string.isEmpty else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(output.text.string, forType: .string)
  }
  @objc private func chooseFile() {
    guard let window else { return }
    pause()
    let token = generation
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.beginSheetModal(for: window) { [weak self] response in
      guard response == .OK, let self, self.generation == token, self.item?.id == "hash",
        let url = panel.url
      else { return }
      self.file = url.path
      self.source.text.string = ""
      self.source.text.isEditable = false
      self.status.stringValue = url.lastPathComponent
      self.status.toolTip = url.path
    }
  }
  @objc private func clearFile() {
    pause()
    output.text.string = ""
    file = nil
    source.text.isEditable = true
    status.stringValue = ""
    status.toolTip = nil
  }
  @objc private func run() {
    guard let item, task == nil else { return }
    if item.id == "random", Int(length.stringValue) == nil || Int(count.stringValue) == nil {
      status.stringValue = "请输入整数长度和数量"
      return
    }
    let request = ToolboxRequest(
      tool: item.id, mode: selectedMode, text: source.text.string,
      other: item.id == "diff" ? second.text.string : other.stringValue,
      length: Int(length.stringValue) ?? 24, count: Int(count.stringValue) ?? 1, file: file,
      replacement: replacement.stringValue)
    guard
      let executable = Bundle.main.executableURL?.deletingLastPathComponent()
        .appendingPathComponent("cs-tool-x")
    else { return }
    generation += 1
    let token = generation
    runButton.isEnabled = false
    status.stringValue = "计算中…"
    output.text.string = ""
    task = Task { [weak self] in
      do {
        let result = try await ToolboxWorker.run(request, executable: executable)
        guard let self, self.generation == token, !Task.isCancelled else { return }
        self.output.text.string = result.output
        self.status.stringValue = result.detail
      } catch {
        guard let self, self.generation == token, !Task.isCancelled else { return }
        self.status.stringValue = error.localizedDescription
        self.status.toolTip = error.localizedDescription
      }
      guard let self, self.generation == token else { return }
      self.task = nil
      self.runButton.isEnabled = true
    }
  }
  private static let modeNames: [String: String] = [
    "upper": "大写", "lower": "小写", "title": "词首大写", "camel": "camelCase", "snake": "snake_case",
    "kebab": "kebab-case", "deduplicate": "去重", "count": "统计次数", "extract": "提取文字", "lines": "逐行对比",
    "seconds-to-date": "秒 → 日期", "milliseconds-to-date": "毫秒 → 日期", "date-to-seconds": "日期 → 秒",
    "date-to-milliseconds": "日期 → 毫秒", "base64-encode": "Base64 编码", "base64-decode": "Base64 解码",
    "url-encode": "URL 编码", "url-decode": "URL 解码", "hex-encode": "UTF-8 → Hex",
    "hex-decode": "Hex → UTF-8", "json-escape": "JSON 转义", "json-unescape": "JSON 反转义",
    "pretty": "格式化", "compact": "压缩", "sorted": "排序并格式化", "match": "匹配", "replace": "替换",
    "password": "安全密码", "alphanumeric": "字母和数字", "digits": "纯数字", "uuid": "UUID",
  ]
}

@MainActor private final class ToolboxText: NSScrollView, NSTextViewDelegate {
  let text = NSTextView()
  init(editable: Bool = true) {
    super.init(frame: .zero)
    drawsBackground = false
    borderType = .noBorder
    hasVerticalScroller = true
    hasHorizontalScroller = false
    autohidesScrollers = true
    wantsLayer = true
    layer?.cornerRadius = 14
    layer?.borderWidth = 0.7
    layer?.borderColor = Theme.line.withAlphaComponent(0.6).cgColor
    text.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
    text.textColor = Theme.ink
    text.backgroundColor = Theme.paper
    text.isRichText = false
    text.isEditable = editable
    text.isSelectable = true
    text.delegate = self
    text.isAutomaticQuoteSubstitutionEnabled = false
    text.isAutomaticDashSubstitutionEnabled = false
    text.isAutomaticTextReplacementEnabled = false
    text.isAutomaticSpellingCorrectionEnabled = false
    text.textContainerInset = NSSize(width: 12, height: 12)
    text.isVerticallyResizable = true
    text.isHorizontallyResizable = false
    text.autoresizingMask = [.width]
    text.textContainer?.widthTracksTextView = true
    text.frame = NSRect(x: 0, y: 0, width: 400, height: 100)
    documentView = text
  }
  required init?(coder: NSCoder) { nil }
  func textView(
    _ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
    replacementString: String?
  ) -> Bool {
    guard let replacementString else { return true }
    let old = textView.string as NSString
    guard affectedCharRange.location <= old.length, NSMaxRange(affectedCharRange) <= old.length
    else { return false }
    return old.replacingCharacters(in: affectedCharRange, with: replacementString).utf8.count
      <= Toolbox.inputLimit
  }
}

@MainActor private struct ToolboxGrid: View {
  private let entries = Toolbox.items
  let open: (ToolboxItem) -> Void
  var body: some View {
    GeometryReader { geometry in
      let columns = max(1, min(5, Int((geometry.size.width - 44) / 200)))
      let width = max(
        140, (geometry.size.width - 64 - CGFloat(columns - 1) * 20) / CGFloat(columns))
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          ForEach(0..<((entries.count + columns - 1) / columns), id: \.self) { row in
            HStack(spacing: 20) {
              ForEach(0..<columns, id: \.self) { column in
                let index = row * columns + column
                if index < entries.count {
                  ToolboxCard(item: entries[index]) { open(entries[index]) }.frame(
                    width: width)
                }
              }
            }
          }
        }.padding(32).frame(maxWidth: .infinity, alignment: .topLeading)
      }
    }.background(Color(nsColor: Theme.paper)).preferredColorScheme(.light)
  }
}
@MainActor private struct ToolboxCard: View {
  let item: ToolboxItem, action: () -> Void
  @State private var hovered = false
  @FocusState private var focused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private var active: Bool { hovered || focused }
  var body: some View {
    Button {
      hovered = false
      action()
    } label: {
      ZStack {
        ToolboxPictogram(item: item).opacity(active ? 0 : 1).offset(
          y: active && !reduceMotion ? -4 : 0
        ).scaleEffect(active && !reduceMotion ? 0.97 : 1)
        Text(item.name).font(Font(Theme.font(14, weight: .medium))).foregroundStyle(
          Color(nsColor: Theme.ink)
        ).lineLimit(1).fixedSize(horizontal: true, vertical: false)
          .opacity(active ? 1 : 0).offset(y: active || reduceMotion ? 0 : 5)
      }.frame(maxWidth: .infinity).frame(height: 96)
        .background(Color.white.opacity(active ? 0.5 : 0.3), in: RoundedRectangle(cornerRadius: 24))
        .overlay(
          RoundedRectangle(cornerRadius: 24).stroke(
            Color(nsColor: Theme.muted).opacity(focused ? 0.35 : 0.12), lineWidth: 0.7)
        )
        .shadow(color: Color(nsColor: Theme.ink).opacity(active ? 0.07 : 0), radius: 18, y: 7)
        .offset(y: active && !reduceMotion ? -3 : 0).contentShape(
          RoundedRectangle(cornerRadius: 24))
    }.buttonStyle(.plain).writingCursor(.clickable).focused($focused).onHover { hovered = $0 }
      .onDisappear { hovered = false }
      .animation(reduceMotion ? nil : .timingCurve(0.4, 0, 0.2, 1, duration: 0.28), value: active)
      .accessibilityLabel(item.name).help(item.name)
  }
}

/// Static native pictograms: layered paper objects, pigment strokes and one concise mark.
@MainActor private struct ToolboxPictogram: View {
  let item: ToolboxItem
  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 7).fill(Color(red: 0.80, green: 0.85, blue: 0.74).opacity(0.5))
        .frame(width: 57, height: 46).rotationEffect(.degrees(-8)).offset(x: -9, y: 3)
      RoundedRectangle(cornerRadius: 7).fill(Color(red: 0.96, green: 0.88, blue: 0.67).opacity(0.8))
        .frame(width: 54, height: 51).rotationEffect(.degrees(7)).offset(x: 6)
      RoundedRectangle(cornerRadius: 7).stroke(
        Color(nsColor: Theme.sage).opacity(0.55),
        style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [7, 1.5])
      ).frame(width: 54, height: 51).rotationEffect(.degrees(7)).offset(x: 6)
      Text(item.glyph).font(Font(Theme.font(29, weight: .medium))).foregroundStyle(
        Color(nsColor: Theme.sage)
      ).offset(x: 4)
      Path { p in
        p.move(to: CGPoint(x: 22, y: 59))
        p.addLine(to: CGPoint(x: 70, y: 55))
      }.stroke(
        Color(red: 0.61, green: 0.72, blue: 0.77).opacity(0.6),
        style: StrokeStyle(lineWidth: 3, lineCap: .round))
    }.frame(width: 90, height: 70).accessibilityHidden(true)
  }
}
