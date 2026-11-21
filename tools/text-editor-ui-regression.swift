import AppKit
import ToolCore
import WebKit

@main struct TextEditorRegression {
  @MainActor static func main() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    let workspace = TransientTextWorkspace(frame: NSRect(x: 0, y: 0, width: 980, height: 637))
    workspace.workerURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let window = WorkbenchWindow(contentRect: workspace.frame)
    window.contentView = workspace
    workspace.layoutSubtreeIfNeeded()
    let writing = workspace.writing
    let text = workspace.writing.editor
    window.makeFirstResponder(text)
    writing.replace("", bytes: 0)
    text.undoManager?.beginUndoGrouping()
    text.insertText("你好🧰", replacementRange: NSRange(location: 0, length: 0))
    text.undoManager?.endUndoGrouping()
    precondition(writing.byteCount == "你好🧰".utf8.count, "Native edit tracks UTF-8 bytes")
    text.undoManager?.undo()
    precondition(text.string.isEmpty && writing.byteCount == 0, "Undo restores source AND budget")
    text.undoManager?.redo()
    precondition(
      text.string == "你好🧰" && writing.byteCount == "你好🧰".utf8.count,
      "Redo restores source AND budget")
    text.setMarkedText(
      "拼", selectedRange: NSRange(location: 1, length: 0),
      replacementRange: NSRange(location: NSNotFound, length: 0))
    workspace.togglePreview()
    precondition(!workspace.showingPreview && text.hasMarkedText(), "Preview cannot interrupt IME")
    text.unmarkText()
    let imeStatisticsDeadline = Date().addingTimeInterval(10)
    while !workspace.statistics.isCurrent {
      precondition(Date() < imeStatisticsDeadline)
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    let imeExpected = try TextStatisticsIndex(text.string).snapshot
    precondition(
      workspace.statistics.snapshot == imeExpected, "IME edits must reach the statistics index")
    let source = "# 标题\n\n**正文** 和 `code`\n\n- one\n- two\n"
    writing.replace(source, bytes: source.utf8.count)
    text.setSelectedRange(NSRange(location: 2, length: 2))
    let selection = text.selectedRange()
    workspace.togglePreview()
    let deadline = Date().addingTimeInterval(10)
    while workspace.hasPendingWork {
      precondition(Date() < deadline)
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    precondition(workspace.showingPreview && workspace.previewView != nil)
    precondition(
      !text.isEditable && window.firstResponder !== text,
      "Preview must not leave an invisible editable first responder")
    precondition(
      workspace.previewView!.configuration.defaultWebpagePreferences.allowsContentJavaScript
        == false)
    var rendered = false
    let renderDeadline = Date().addingTimeInterval(10)
    while Date() < renderDeadline {
      if let body = try? await workspace.previewView!.evaluateJavaScript(
        "document.body ? document.body.innerText : ''") as? String,
        body.contains("标题"), body.contains("正文")
      {
        rendered = true
        break
      }
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    precondition(
      rendered, "Actual WebKit document must render Markdown content, not just create a view")
    workspace.showEditor()
    precondition(text.string == source && text.selectedRange() == selection)
    func statsReady() async throws {
      let deadline = Date().addingTimeInterval(15)
      while !workspace.statistics.isCurrent {
        precondition(Date() < deadline, "Statistics must catch up")
        try await Task.sleep(nanoseconds: 10_000_000)
      }
    }
    try await statsReady()
    let expectedStatistics = try TextStatisticsIndex(source).snapshot
    precondition(workspace.statistics.snapshot == expectedStatistics)
    text.undoManager?.beginUndoGrouping()
    text.insertText("你好", replacementRange: NSRange(location: 0, length: 0))
    text.undoManager?.endUndoGrouping()
    try await statsReady()
    precondition(workspace.statistics.snapshot?.han == expectedStatistics.han + 2)
    text.undoManager?.undo()
    try await statsReady()
    precondition(workspace.statistics.snapshot == expectedStatistics)
    text.setSelectedRange(NSRange(location: 2, length: 2))
    let selectedDeadline = Date().addingTimeInterval(5)
    while workspace.statistics.selected == nil {
      precondition(Date() < selectedDeadline)
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    precondition(
      workspace.statistics.selected?.han == 2 && workspace.statistics.selected?.characters == 2)
    var times: [Double] = []
    // Two different stressors: many lines, and one very long line. No user text or clipboard.
    for (name, value) in [
      ("multiline-8MiB", String(repeating: "one line of text for writing\n", count: 300_000)),
      (
        "multiline-near-32MiB",
        String(repeating: String(repeating: "x", count: 63) + "\n", count: 524_272)
      ), ("single-line-96KiB", String(repeating: "x", count: 96 * 1024)),
    ] {
      writing.wraps = false
      let start = CFAbsoluteTimeGetCurrent()
      writing.replace(value, bytes: value.utf8.count, validated: true)
      writing.layoutSubtreeIfNeeded()
      let load = (CFAbsoluteTimeGetCurrent() - start) * 1000
      var localTimes: [Double] = []
      for _ in 0..<40 {
        text.setSelectedRange(NSRange(location: 0, length: 0))
        let now = CFAbsoluteTimeGetCurrent()
        text.insertText("a", replacementRange: NSRange(location: 0, length: 0))
        let ms = (CFAbsoluteTimeGetCurrent() - now) * 1000
        times.append(ms)
        localTimes.append(ms)
      }
      print(
        "MEASURE: \(name), bytes=\(value.utf8.count), native replacement/layout ms=\(String(format: "%.1f", load))"
      )
      print("MEASURE: \(name), insertion p95 ms=\(String(format: "%.2f", localTimes.sorted()[37]))")
      fflush(stdout)
      precondition(writing.byteCount == value.utf8.count + 40)
      if writing.byteCount > TextWorkbench.previewBytes {
        workspace.togglePreview()
        precondition(!workspace.showingPreview, "Oversized preview leaves full source editable")
      }
    }
    let sorted = times.sorted()
    print(
      "MEASURE: native insertion p95 ms=\(String(format: "%.2f", sorted[Int(Double(sorted.count - 1) * 0.95)])); local synthetic editing path, not end-to-end latency"
    )
    // Cross the actual editor limit with a single paste-sized insertion; it must leave the source intact.
    text.setSelectedRange(NSRange(location: 0, length: 0))
    let before = writing.byteCount
    text.insertText(
      String(repeating: "y", count: TextWorkbench.editorBytes),
      replacementRange: NSRange(location: 0, length: 0))
    precondition(writing.byteCount == before && (text.string as NSString).length == before)
    precondition(
      !writing.replace(String(repeating: "x", count: 8 * 1024 * 1024), bytes: 8 * 1024 * 1024),
      "Reject pathological long lines before replacing source")
    workspace.pause()
    writing.replace(source, bytes: source.utf8.count)
    precondition(text.string == source)
    workspace.activate()
    try await statsReady()
    if CommandLine.arguments.count > 2 {
      workspace.layoutSubtreeIfNeeded()
      let rep = workspace.bitmapImageRepForCachingDisplay(in: workspace.bounds)!
      workspace.cacheDisplay(in: workspace.bounds, to: rep)
      try rep.representation(using: .png, properties: [:])!.write(
        to: URL(fileURLWithPath: CommandLine.arguments[2]))
    }
    print(
      "PASS: native Unicode/undo/redo/IME, live statistics/selection, preview roundtrip, large line/multiline editing, source-preserving budgets and module pause; offscreen component checks"
    )
  }
}
