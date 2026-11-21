import AppKit
import ToolCore

@main struct ToolboxUIRegression {
  @MainActor static func main() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    let workspace = ToolboxWorkspace(frame: NSRect(x: 0, y: 0, width: 980, height: 637))
    let window = WorkbenchWindow(contentRect: workspace.frame)
    window.contentView = workspace
    func snapshot(_ key: String) throws {
      workspace.layoutSubtreeIfNeeded()
      if CommandLine.arguments.count > 1 {
        let target = key == "grid" ? workspace.subviews[0] : workspace
        let rep = target.bitmapImageRepForCachingDisplay(in: target.bounds)!
        target.cacheDisplay(in: target.bounds, to: rep)
        try rep.representation(using: .png, properties: [:])!.write(
          to: URL(fileURLWithPath: CommandLine.arguments[1] + "-" + key + ".png"))
      }
    }
    workspace.layoutSubtreeIfNeeded()
    try await Task.sleep(nanoseconds: 100_000_000)
    try snapshot("grid")
    for id in ["diff", "regex", "hash", "random", "timestamp"] {
      workspace.open(Toolbox.items.first { $0.id == id }!)
      workspace.layoutSubtreeIfNeeded()
      try await Task.sleep(nanoseconds: 50_000_000)
      precondition(!workspace.hasAmbiguousLayout)
      try snapshot(id)
      workspace.pause()
    }
    print(
      "PASS: toolbox grid and five editor layouts render at 980pt; offscreen only, not installed UI interaction"
    )
  }
}
