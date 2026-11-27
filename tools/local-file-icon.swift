import AppKit
import ImageIO
import UniformTypeIdentifiers

// Local Finder appearance only. Never call this while packaging or signing a release.
let app = URL(fileURLWithPath: "/Applications/cs-tool-x.app")
let args = CommandLine.arguments
guard args.count >= 2 else { fatalError("Expected apply, clear, inspect, or trash") }
switch args[1] {
case "apply":
  let source = app.appendingPathComponent("Contents/Resources/DockIcon.png")
  guard let image = NSImage(contentsOf: source),
    NSWorkspace.shared.setIcon(image, forFile: app.path, options: [])
  else { fatalError("Unable to apply local custom icon") }
case "clear":
  guard NSWorkspace.shared.setIcon(nil, forFile: app.path, options: []) else {
    fatalError("Unable to clear local custom icon")
  }
case "trash":
  let icon = app.appendingPathComponent("Icon\r")
  if FileManager.default.fileExists(atPath: icon.path) {
    try FileManager.default.trashItem(at: icon, resultingItemURL: nil)
  }
case "inspect":
  guard args.count == 3 else { fatalError("Expected output PNG") }
  let image = NSWorkspace.shared.icon(forFile: app.path)
  var rect = CGRect(x: 0, y: 0, width: 512, height: 512)
  guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
    let destination = CGImageDestinationCreateWithURL(
      URL(fileURLWithPath: args[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)
  else { fatalError("Unable to read system icon") }
  CGImageDestinationAddImage(destination, cg, nil)
  guard CGImageDestinationFinalize(destination) else { fatalError("Unable to write inspection PNG") }
default: fatalError("Unknown operation")
}
