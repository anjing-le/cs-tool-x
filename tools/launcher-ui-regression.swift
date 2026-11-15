import AppKit
import SwiftUI
import ToolCore

@main struct LauncherRegression {
  @MainActor static func main() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    let directory = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Resources/Entrances")
    let artwork = LauncherArtwork(directory: directory)
    await artwork.load()
    precondition(artwork.images.count == 3, "All three entrance resources decode")
    precondition(artwork.images.values.allSatisfy { max($0.width, $0.height) <= 1536 }, "Decoded image budget remains bounded")
    let cache = artwork.images["shell"]!
    await artwork.load()
    precondition(artwork.images["shell"] === cache, "Returning home reuses decoded artwork")
    let host = NSHostingView(rootView: LauncherView(artwork: artwork) { _ in })
    let window = WorkbenchWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 850))
    window.contentView = host
    for (width, height) in [(1440, 850), (980, 680), (1920, 900)] {
      window.setContentSize(NSSize(width: width, height: height))
      host.layoutSubtreeIfNeeded()
      try await Task.sleep(nanoseconds: 80_000_000)
      let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
      host.cacheDisplay(in: host.bounds, to: rep)
      if CommandLine.arguments.count > 2 {
        let path = URL(fileURLWithPath: CommandLine.arguments[2] + "-\(width).png")
        try rep.representation(using: .png, properties: [:])!.write(to: path)
      }
      // The top/bottom, both joins and outer edges must all contain scene pixels, not a card gutter.
      for fx in [0.002, 0.332, 0.334, 0.665, 0.668, 0.998] {
        for fy in [0.002, 0.5, 0.998] {
          let color = rep.colorAt(x: Int(Double(rep.pixelsWide - 1) * fx), y: Int(Double(rep.pixelsHigh - 1) * fy))!.usingColorSpace(.sRGB)!
          precondition(color.alphaComponent > 0.99, "No transparent panel gap")
          precondition(min(color.redComponent, color.greenComponent, color.blueComponent) < 0.96, "No white card gutter or margin")
        }
      }
    }
    print("PASS: edge-to-edge colored entrance regions with contained artwork at minimum, standard and wide sizes; three bounded cached illustrations; no white gutters. Offscreen rendering, not installed-window automation.")
  }
}
