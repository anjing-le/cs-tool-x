import AppKit
import SwiftTerm
@main struct TerminalColors {
  @MainActor static func main() throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    let environment = TerminalAppearance.environment(base: ["PATH":"/usr/bin:/bin"], local: true)
    precondition(environment["TERM"] == "xterm-256color" && environment["COLORTERM"] == "truecolor")
    precondition(environment["CLICOLOR"] == "1")
    precondition(TerminalAppearance.environment(base: ["NO_COLOR":"1"], local: true)["CLICOLOR"] == nil)
    precondition(TerminalAppearance.environment(base: ["CLICOLOR":"0", "LSCOLORS":"custom"], local: true)["CLICOLOR"] == "0")
    precondition(TerminalAppearance.environment(base: ["LSCOLORS":"custom"], local: true)["LSCOLORS"] == "custom")
    precondition(TerminalAppearance.environment(base: [:], local: false)["CLICOLOR"] == nil)
    let view = TerminalView(frame: NSRect(x: 0, y: 0, width: 720, height: 240))
    TerminalAppearance.apply(to: view)
    precondition(TerminalAppearance.palette.count == 16 && Set(TerminalAppearance.palette).count == 16)
    view.feed(text: "\u{1b}[31mR\u{1b}[32mG\u{1b}[34mB\u{1b}[38;5;123mX\u{1b}[38;2;12;34;56mT\u{1b}[0mN")
    let terminal = view.getTerminal()
    for (col, expected): (Int, Attribute.Color) in [
      (0,.ansi256(code:1)), (1,.ansi256(code:2)), (2,.ansi256(code:4)),
      (3,.ansi256(code:123)), (4,.trueColor(red:12,green:34,blue:56)), (5,.defaultColor)
    ] {
      precondition(terminal.getCharData(col: col, row: 0)?.attribute.fg == expected,
        "ANSI indexed/true color and reset must survive rendering")
    }
    if CommandLine.arguments.count > 1 {
      try JSONSerialization.data(withJSONObject: environment).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
    print("PASS: ANSI/256/true-color parsing, light palette, local color defaults, explicit user overrides and remote isolation")
  }
}
