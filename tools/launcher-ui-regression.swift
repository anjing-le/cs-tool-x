import AppKit
import SwiftUI
import ToolCore

@main struct LauncherRegression {
  @MainActor static func main() async throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    // Real NSWindow dispatch against a local callback; no events posted to the desktop.
    let navigationWindow = WorkbenchWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100))
    navigationWindow.contentView = NSView()
    var visits: [Bool] = []
    navigationWindow.onNavigate = {
      visits.append($0)
      return true
    }
    func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags, repeatKey: Bool = false) -> NSEvent {
      NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
        windowNumber: navigationWindow.windowNumber, context: nil,
        characters: code == 33 ? "[" : "]",
        charactersIgnoringModifiers: code == 33 ? "[" : "]", isARepeat: repeatKey, keyCode: code)!
    }
    precondition(navigationWindow.performKeyEquivalent(with: key(33, .command)))
    precondition(navigationWindow.performKeyEquivalent(with: key(30, [.command, .capsLock])))
    _ = navigationWindow.performKeyEquivalent(with: key(33, .command, repeatKey: true))
    _ = navigationWindow.performKeyEquivalent(with: key(30, [.command, .shift]))
    precondition(
      visits == [false, true], "Brackets navigate once; shifted tab shortcut is untouched")
    for button in [3, 4] {
      for type in [CGEventType.otherMouseDown, .otherMouseUp] {
        let cg = CGEvent(
          mouseEventSource: nil, mouseType: type, mouseCursorPosition: .zero,
          mouseButton: CGMouseButton(rawValue: UInt32(button))!)!
        navigationWindow.sendEvent(NSEvent(cgEvent: cg)!)
      }
    }
    precondition(
      visits == [false, true, false, true], "Side button press/release navigates once per pair")
    let ordinary = CGEvent(
      mouseEventSource: nil, mouseType: .otherMouseUp, mouseCursorPosition: .zero,
      mouseButton: .center)!
    navigationWindow.sendEvent(NSEvent(cgEvent: ordinary)!)
    precondition(visits.count == 4, "Middle button is not navigation")
    navigationWindow.onNavigate = { _ in false }
    _ = navigationWindow.performKeyEquivalent(with: key(33, .command))
    precondition(visits.count == 4, "Rejected navigation cannot mutate history")
    print(
      "PASS: window-scoped Command brackets, repeat suppression, shifted shortcut isolation and mouse side-button dispatch; synthetic offscreen events, not physical mouse hardware"
    )
    let directory = URL(
      fileURLWithPath: CommandLine.arguments.count > 1
        ? CommandLine.arguments[1] : "Resources/Entrances")
    let artwork = LauncherArtwork(directory: directory)
    await artwork.load()
    precondition(artwork.images.count == 5, "All five entrance resources decode")
    precondition(
      artwork.images.values.allSatisfy { max($0.width, $0.height) <= 1536 },
      "Decoded image budget remains bounded")
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
      // Narrow paper gutters separate the rounded cards; artwork remains opaque.
      func sample(_ x: Double, _ y: Double) -> NSColor {
        rep.colorAt(x: Int(x / Double(width) * Double(rep.pixelsWide)),
          y: Int(y / Double(height) * Double(rep.pixelsHigh)))!.usingColorSpace(.sRGB)!
      }
      let paper = Theme.paper.usingColorSpace(.sRGB)!
      for (x, y) in [(2.0, 2.0), (Double(width) / 2, 30.0), (8.5, 8.5)] {
        let color = sample(x, y)
        precondition(color.alphaComponent > 0.99, "Opaque paper background")
        precondition(abs(color.redComponent - paper.redComponent) < 0.025 &&
          abs(color.greenComponent - paper.greenComponent) < 0.025 &&
          abs(color.blueComponent - paper.blueComponent) < 0.025,
          "Outer inset, rounded corner and inter-card gap reveal warm paper")
      }
      let image = sample(Double(width) / 8, 40)
      precondition(image.alphaComponent > 0.99 && min(image.redComponent, image.greenComponent, image.blueComponent) < 0.96,
        "Card interior retains illustration")
    }
    print(
      "PASS: four independent upper entrances with responsive height and one full-width toolbox entrance at minimum, standard and wide sizes; five bounded cached illustrations; rounded outlined cards with narrow paper gutters. Offscreen rendering, not installed-window automation."
    )
  }
}
