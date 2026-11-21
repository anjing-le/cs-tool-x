import AppKit
import QuartzCore
import ToolCore

/// Native editing owns its storage, selection, undo and IME; no per-keystroke document binding.
@MainActor final class TransientTextEditor: NSScrollView, NSTextViewDelegate {
  let editor: InkTextView
  private(set) var byteCount = 0
  private(set) var revision = 0
  var changed: (() -> Void)?
  var statisticsReset: ((String, Int) -> Void)?
  var statisticsEdited: ((NSRange, String, Int, Int) -> Void)?
  var selectionChanged: (() -> Void)?
  private var pendingStatisticsEdit: (NSRange, String, Int)?
  var rejected: ((String) -> Void)?
  var largeModeActivated: (() -> Void)?
  var paper = true { didSet { applyTypography() } }
  var wraps = true { didSet { applyWrapping() } }
  private var lastInset: CGFloat = -1
  init() {
    let storage = NSTextStorage()
    let layout = WetInkLayout()
    layout.allowsNonContiguousLayout = true
    let container = NSTextContainer(
      size: NSSize(width: 800, height: CGFloat.greatestFiniteMagnitude))
    storage.addLayoutManager(layout)
    layout.addTextContainer(container)
    editor = InkTextView(
      frame: NSRect(x: 0, y: 0, width: 800, height: 300), textContainer: container)
    super.init(frame: .zero)
    drawsBackground = false
    hasVerticalScroller = true
    autohidesScrollers = true
    scrollerStyle = .overlay
    documentView = editor
    editor.delegate = self
    editor.isRichText = false
    editor.allowsUndo = true
    editor.drawsBackground = false
    editor.textColor = Theme.ink
    editor.insertionPointColor = Theme.sage
    editor.isVerticallyResizable = true
    editor.minSize = .zero
    editor.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    editor.isAutomaticQuoteSubstitutionEnabled = false
    editor.isAutomaticDashSubstitutionEnabled = false
    editor.isAutomaticTextReplacementEnabled = false
    editor.isAutomaticSpellingCorrectionEnabled = false
    editor.selectedTextAttributes = [
      .backgroundColor: Theme.line.withAlphaComponent(0.4), .foregroundColor: Theme.ink,
    ]
    editor.setAccessibilityLabel("临时文本正文")
    editor.setAccessibilityHelp("本次运行内保留，退出后清空；Command+/ 切换 Markdown 预览")
    applyTypography()
    applyWrapping()
  }
  required init?(coder: NSCoder) { nil }
  override func layout() {
    super.layout()
    let inset: CGFloat = paper ? max(24, contentSize.width * 0.075) : 24
    if abs(inset - lastInset) > 0.5 {
      lastInset = inset
      editor.textContainerInset = NSSize(width: inset, height: 24)
    }
  }
  private func applyTypography() {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineHeightMultiple = paper ? 1.45 : 1.3
    paragraph.lineBreakMode = .byCharWrapping
    paragraph.hyphenationFactor = 0
    let font = paper ? Theme.font(19) : NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    editor.font = font
    editor.defaultParagraphStyle = paragraph
    editor.typingAttributes = [
      .font: font, .foregroundColor: Theme.ink, .paragraphStyle: paragraph,
    ]
    // Explicit style changes only. Ordinary typing never reapplies attributes to the manuscript.
    if let storage = editor.textStorage, storage.length > 0 {
      storage.addAttributes(
        editor.typingAttributes, range: NSRange(location: 0, length: storage.length))
    }
    lastInset = -1
    needsLayout = true
  }
  private func applyWrapping() {
    editor.isHorizontallyResizable = !wraps
    editor.autoresizingMask = wraps ? [.width] : []
    editor.textContainer?.widthTracksTextView = wraps
    editor.textContainer?.containerSize = NSSize(
      width: wraps ? max(1, contentSize.width) : 4_000_000, height: CGFloat.greatestFiniteMagnitude)
    hasHorizontalScroller = !wraps
    if wraps {
      editor.setFrameSize(
        NSSize(
          width: max(1, contentSize.width), height: max(contentSize.height, editor.frame.height)))
    }
  }
  @discardableResult func replace(_ text: String, bytes: Int, validated: Bool = false) -> Bool {
    guard bytes <= TextWorkbench.editorBytes, validated || TextWorkbench.acceptsLines(text) else {
      rejected?("文本超过 32 MiB 或单行超过 128 KiB，当前正文保留")
      return false
    }
    editor.unmarkText()
    editor.ink.clear()
    pendingStatisticsEdit = nil
    byteCount = bytes
    revision += 1
    editor.undoManager?.levelsOfUndo = bytes > 2 * 1024 * 1024 ? 20 : 100
    editor.string = text
    editor.undoManager?.removeAllActions()
    editor.setSelectedRange(NSRange(location: 0, length: 0))
    editor.scrollToBeginningOfDocument(nil)
    statisticsReset?(text, revision)
    changed?()
    return true
  }
  func textView(
    _ textView: NSTextView, shouldChangeTextIn range: NSRange, replacementString: String?
  ) -> Bool {
    guard let replacementString, range.location != NSNotFound, let storage = textView.textStorage,
      NSMaxRange(range) <= storage.length
    else { return true }
    let string = storage.mutableString
    var lineStart = 0
    var lineEnd = 0
    var contentsEnd = 0
    string.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: range)
    let prefix = string.substring(
      with: NSRange(location: lineStart, length: range.location - lineStart)
    ).utf8.count
    let suffix = string.substring(
      with: NSRange(location: NSMaxRange(range), length: max(0, contentsEnd - NSMaxRange(range)))
    ).utf8.count
    guard TextWorkbench.acceptsLines(replacementString, prefix: prefix, suffix: suffix) else {
      rejected?("单行上限 128 KiB，本次输入未写入")
      return false
    }
    let removed = storage.mutableString.substring(with: range).utf8.count
    let next = byteCount - removed + replacementString.utf8.count
    guard next <= TextWorkbench.editorBytes else {
      rejected?("临时文本上限为 32 MiB，本次输入未写入")
      return false
    }
    if next > 2 * 1024 * 1024, byteCount <= 2 * 1024 * 1024 {
      editor.undoManager?.levelsOfUndo = 20
      if wraps {
        wraps = false
        largeModeActivated?()
      }
    }
    byteCount = max(0, next)
    pendingStatisticsEdit = (range, replacementString, revision)
    editor.ink.followEdit(range, length: (replacementString as NSString).length)
    return true
  }
  func textDidChange(_ notification: Notification) {
    let before = revision
    revision += 1
    if let edit = pendingStatisticsEdit, edit.2 == before {
      statisticsEdited?(edit.0, edit.1, before, revision)
    } else {
      statisticsReset?(editor.string, revision)
    }
    pendingStatisticsEdit = nil
    changed?()
  }
  func textViewDidChangeSelection(_ notification: Notification) { selectionChanged?() }
  func pause() { editor.ink.clear() }
}

@MainActor final class InkTextView: NSTextView {
  private let localUndo = UndoManager()
  override var undoManager: UndoManager? { localUndo }
  var togglePreview: (() -> Void)?
  var ink: WetInkLayout { layoutManager as! WetInkLayout }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
      event.charactersIgnoringModifiers == "/", !hasMarkedText()
    {
      togglePreview?()
      return true
    }
    return super.performKeyEquivalent(with: event)
  }
  override func insertText(_ insertString: Any, replacementRange: NSRange) {
    let insertion = (insertString as? String) ?? (insertString as? NSAttributedString)?.string ?? ""
    let range = replacementRange.location == NSNotFound ? selectedRange() : replacementRange
    let oldLength = textStorage?.length ?? 0
    super.insertText(insertString, replacementRange: replacementRange)
    let count = (insertion as NSString).length
    guard count > 0, count <= 16, !hasMarkedText(), undoManager?.isUndoing != true,
      undoManager?.isRedoing != true,
      (textStorage?.length ?? 0) == oldLength - range.length + count,
      !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    else { return }
    ink.land(NSRange(location: range.location, length: count), view: self)
  }
}

/// Steep-style wet ink: bounded glyph records, identical metrics, no text/selection mutations.
@MainActor final class WetInkLayout: NSLayoutManager {
  private struct Mark {
    var range: NSRange
    let started: CFTimeInterval
  }
  private var marks: [Mark] = []
  private weak var view: NSTextView?
  private var timer: Timer?
  private var stroke: CGFloat = 0
  deinit { timer?.invalidate() }
  func land(_ range: NSRange, view: NSTextView) {
    self.view = view
    marks.removeAll { NSIntersectionRange($0.range, range).length > 0 }
    marks.append(Mark(range: range, started: CACurrentMediaTime()))
    if marks.count > 24 { marks.removeFirst(marks.count - 24) }
    if timer == nil {
      let timer = Timer(
        timeInterval: 1.0 / 30, target: self, selector: #selector(tick), userInfo: nil,
        repeats: true)
      self.timer = timer
      RunLoop.main.add(timer, forMode: .common)
    }
    tick()
  }
  func followEdit(_ range: NSRange, length: Int) {
    marks = marks.compactMap { mark in
      var mark = mark
      if NSMaxRange(range) <= mark.range.location {
        mark.range.location += length - range.length
      } else if range.location < NSMaxRange(mark.range) {
        return nil
      }
      return mark
    }
  }
  func clear() {
    marks.removeAll()
    timer?.invalidate()
    timer = nil
    if let view { view.setNeedsDisplay(view.visibleRect) }
  }
  @objc private func tick() {
    marks.removeAll { CACurrentMediaTime() - $0.started > 0.48 }
    guard let view, view.window != nil, !marks.isEmpty else {
      clear()
      return
    }
    if !view.hasMarkedText() { view.setNeedsDisplay(view.visibleRect) }
  }
  override func drawGlyphs(forGlyphRange range: NSRange, at origin: NSPoint) {
    super.drawGlyphs(forGlyphRange: range, at: origin)
    guard let view, !view.hasMarkedText(),
      !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
      let context = NSGraphicsContext.current?.cgContext
    else { return }
    let visible = characterRange(forGlyphRange: range, actualGlyphRange: nil)
    for mark in marks {
      let overlap = NSIntersectionRange(mark.range, visible)
      guard overlap.length > 0,
        !view.selectedRanges.contains(where: {
          NSIntersectionRange($0.rangeValue, overlap).length > 0
        })
      else { continue }
      let progress = min(1, max(0, (CACurrentMediaTime() - mark.started - 0.06) / 0.42))
      let amount = CGFloat(1 - progress * progress * (3 - 2 * progress))
      context.saveGState()
      context.setBlendMode(.multiply)
      context.setAlpha(amount * 0.65)
      stroke = amount * 0.65
      super.drawGlyphs(
        forGlyphRange: glyphRange(forCharacterRange: overlap, actualCharacterRange: nil), at: origin
      )
      stroke = 0
      context.restoreGState()
    }
  }
  override func showCGGlyphs(
    _ glyphs: UnsafePointer<CGGlyph>, positions: UnsafePointer<CGPoint>, count: Int, font: NSFont,
    textMatrix: CGAffineTransform, attributes: [NSAttributedString.Key: Any], in context: CGContext
  ) {
    context.saveGState()
    if stroke > 0 {
      context.setTextDrawingMode(.fillStroke)
      context.setLineWidth(stroke)
      context.setLineJoin(.round)
      context.setStrokeColor(Theme.ink.cgColor)
    }
    super.showCGGlyphs(
      glyphs, positions: positions, count: count, font: font, textMatrix: textMatrix,
      attributes: attributes, in: context)
    context.restoreGState()
  }
}
