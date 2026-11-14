import Foundation
import ImageIO
struct Pixels {
  let width: Int, height: Int, stride: Int
  let bytes: [UInt8]
  init(_ url: URL) {
    let image = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(url as CFURL, nil)!, 0, nil)!
    precondition(image.bitsPerComponent == 8 && image.bitsPerPixel == 32 && image.alphaInfo == .last,
      "RGBA image required: \(url.lastPathComponent)")
    width = image.width; height = image.height; stride = image.bytesPerRow
    bytes = Array(image.dataProvider!.data! as Data)
  }
  func alpha(_ x: Int, _ y: Int) -> UInt8 { bytes[y * stride + x * 4 + 3] }
  func transparentBorder() {
    for x in 0..<width { precondition(alpha(x, 0) == 0 && alpha(x, height - 1) == 0, "Top/bottom must be transparent") }
    if width >= 128 {
      for y in 0..<height { precondition(alpha(0, y) == 0 && alpha(width - 1, y) == 0, "Side borders must be transparent") }
    }
    // Downsampling a wide silhouette can antialias into the side edge at 16/32 px.
    precondition(alpha(0, 0) == 0 && alpha(width - 1, height - 1) == 0)
    var transparent = 0
    for y in 0..<height { for x in 0..<width { if alpha(x, y) == 0 { transparent += 1 } } }
    precondition(transparent > width * height / 5, "A solid icon plate must not be introduced")
    // At 16/32 px the small handle hole shares pixels with its antialiased outline.
    if width >= 128 {
      precondition(alpha(width / 2, height * 28 / 100) == 0, "Handle opening must stay transparent")
    }
    precondition(alpha(width / 2, height * 80 / 100) > 200, "Toolbox interior remains artwork")
  }
}
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let original = Pixels(root.appendingPathComponent("assets/AppIcon-original.png"))
let production = Pixels(root.appendingPathComponent("assets/AppIcon.png"))
precondition(original.width == production.width && original.height == production.height)
for y in 0..<original.height { for x in 0..<original.width {
  let a = y * original.stride + x * 4, b = y * production.stride + x * 4
  for channel in 0..<3 { precondition(original.bytes[a + channel] == production.bytes[b + channel], "Original RGB must be unchanged") }
  precondition(production.bytes[b + 3] == (original.bytes[a + 3] == 1 ? 0 : original.bytes[a + 3]), "Only near-transparent alpha residue may change")
}}
production.transparentBorder()
let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("icon-check-" + UUID().uuidString)
try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporary) }
let set = temporary.appendingPathComponent("AppIcon.iconset")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "iconset", root.appendingPathComponent("Resources/AppIcon.icns").path, "-o", set.path]
try process.run(); process.waitUntilExit(); precondition(process.terminationStatus == 0)
let files = try FileManager.default.contentsOfDirectory(at: set, includingPropertiesForKeys: nil).filter { $0.pathExtension == "png" }
precondition(files.count == 10)
for file in files { Pixels(file).transparentBorder() }
print("PASS: original artwork RGB retained, exterior and handle alpha zero, all 10 ICNS PNG representations retain transparency; system display still requires separate verification")
