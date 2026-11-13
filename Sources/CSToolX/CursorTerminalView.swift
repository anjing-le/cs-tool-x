import AppKit
import SwiftTerm

/// Window-level final cursor ownership overrides SwiftTerm’s non-open cursor handlers.
final class CursorTerminalView: LocalProcessTerminalView, WritingCursorProviding {
  var writingCursorRole: WritingCursorRole { .text }
}
