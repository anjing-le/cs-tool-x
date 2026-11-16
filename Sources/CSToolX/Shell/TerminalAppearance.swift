import AppKit
import SwiftTerm

@MainActor enum TerminalAppearance {
  // ANSI meanings remain unchanged; darker inks keep colored text readable on paper.
  static let palette: [SwiftTerm.Color] = [
    (0x36,0x3d,0x36),(0xb0,0x48,0x45),(0x48,0x75,0x4c),(0x91,0x69,0x26),
    (0x42,0x6d,0xa0),(0x8a,0x58,0x96),(0x31,0x78,0x7d),(0xc8,0xca,0xbf),
    (0x6f,0x76,0x69),(0xc5,0x56,0x4c),(0x56,0x83,0x53),(0xa6,0x79,0x2d),
    (0x50,0x7d,0xb1),(0x9b,0x68,0xa2),(0x3c,0x8c,0x91),(0xe9,0xe9,0xdc),
  ].map { SwiftTerm.Color(red8: UInt16($0.0), green8: UInt16($0.1), blue8: UInt16($0.2)) }

  static func apply(to terminal: TerminalView) {
    terminal.nativeBackgroundColor = Theme.paper
    terminal.nativeForegroundColor = Theme.ink
    terminal.installColors(palette)
  }
  static func environment(base: [String: String], local: Bool) -> [String: String] {
    var result = base
    for item in Terminal.getEnvironmentVariables(termName: "xterm-256color") {
      let pair = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      if pair.count == 2 { result[String(pair[0])] = String(pair[1]) }
    }
    if local, result["NO_COLOR"] == nil, result["CLICOLOR"] == nil {
      result["CLICOLOR"] = "1"
    }
    return result
  }
}
