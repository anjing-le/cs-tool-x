import Foundation

public struct TextStatistics: Codable, Equatable, Sendable {
  public var characters = 0
  public var nonWhitespace = 0
  public var han = 0
  public var englishWords = 0
  public var digits = 0
  public var punctuation = 0
  public var whitespace = 0
  public var lines = 0
  public var nonEmptyLines = 0
  public var paragraphs = 0
  public var utf8Bytes = 0
  public var utf16Units = 0
  public var emptyLines: Int { max(0, lines - nonEmptyLines) }
  public init() {}
  fileprivate mutating func add(_ other: Self) {
    characters += other.characters
    nonWhitespace += other.nonWhitespace
    han += other.han
    englishWords += other.englishWords
    digits += other.digits
    punctuation += other.punctuation
    whitespace += other.whitespace
    lines += other.lines
    nonEmptyLines += other.nonEmptyLines
    paragraphs += other.paragraphs
    utf8Bytes += other.utf8Bytes
    utf16Units += other.utf16Units
  }
}

/// Line-aligned blocks keep Unicode graphemes, CRLF and word boundaries intact.
/// Editing rescans the touched blocks plus one neighbor on either side, never the whole manuscript.
public final class TextStatisticsIndex {
  private struct Summary {
    var value = TextStatistics()
    var breaks = 0
    var firstNonEmpty = false
    var lastNonEmpty = false
    func joined(_ other: Self) -> Self {
      if value.utf16Units == 0 { return other }
      if other.value.utf16Units == 0 { return self }
      var result = self
      result.value.add(other.value)
      result.breaks += other.breaks
      result.value.lines = result.breaks + 1
      if lastNonEmpty && other.firstNonEmpty { result.value.paragraphs -= 1 }
      result.lastNonEmpty = other.lastNonEmpty
      return result
    }
  }
  private struct Block {
    let text: String
    let summary: Summary
  }
  private var blocks: [Block] = []
  private var starts: [Int] = []
  private var total = Summary()
  private static let hanPattern = try! NSRegularExpression(pattern: #"\p{Han}"#)
  private static let wordsPattern = try! NSRegularExpression(
    pattern: #"[A-Za-z]+(?:['’][A-Za-z]+)*"#)
  private static let digitsPattern = try! NSRegularExpression(pattern: #"\p{Nd}"#)
  private static let punctuationPattern = try! NSRegularExpression(pattern: #"\p{P}"#)
  internal private(set) var scannedUTF16Units = 0
  public var snapshot: TextStatistics { total.value }
  public init(_ text: String = "") throws {
    guard text.utf8.count <= TextWorkbench.editorBytes else { throw ToolboxError("统计文本超过 32 MiB") }
    blocks = try makeBlocks(text)
    rebuildMetadata()
  }
  private func scan(_ text: String) throws -> Summary {
    var result = Summary()
    var lineNonEmpty = false
    var previousNonEmpty = false
    var first: Bool?
    var endedWithBreak = false
    var checked = 0
    for character in text {
      checked += 1
      if checked & 1023 == 0 { try Task.checkCancellation() }
      result.value.characters += 1
      if character.isWhitespace {
        result.value.whitespace += 1
      } else {
        result.value.nonWhitespace += 1
        lineNonEmpty = true
      }
      if character.isNewline {
        result.breaks += 1
        if first == nil { first = lineNonEmpty }
        if lineNonEmpty {
          result.value.nonEmptyLines += 1
          if !previousNonEmpty { result.value.paragraphs += 1 }
        }
        previousNonEmpty = lineNonEmpty
        lineNonEmpty = false
        endedWithBreak = true
      } else {
        endedWithBreak = false
      }
    }
    if !endedWithBreak {
      if first == nil { first = lineNonEmpty }
      if lineNonEmpty {
        result.value.nonEmptyLines += 1
        if !previousNonEmpty { result.value.paragraphs += 1 }
      }
    }
    result.firstNonEmpty = first ?? false
    result.lastNonEmpty = endedWithBreak ? previousNonEmpty : lineNonEmpty
    let range = NSRange(location: 0, length: (text as NSString).length)
    result.value.utf16Units = range.length
    result.value.utf8Bytes = text.utf8.count
    result.value.lines = text.isEmpty ? 0 : result.breaks + 1
    result.value.han = Self.hanPattern.numberOfMatches(in: text, range: range)
    result.value.englishWords = Self.wordsPattern.numberOfMatches(in: text, range: range)
    result.value.digits = Self.digitsPattern.numberOfMatches(in: text, range: range)
    result.value.punctuation = Self.punctuationPattern.numberOfMatches(in: text, range: range)
    scannedUTF16Units += range.length
    return result
  }
  private func makeBlocks(_ text: String) throws -> [Block] {
    let source = text as NSString
    var result: [Block] = []
    var start = 0
    var cursor = 0
    while cursor < source.length {
      try Task.checkCancellation()
      cursor = NSMaxRange(source.lineRange(for: NSRange(location: cursor, length: 0)))
      if cursor - start >= 8192 || cursor == source.length {
        let part = source.substring(with: NSRange(location: start, length: cursor - start))
        result.append(Block(text: part, summary: try scan(part)))
        start = cursor
      }
    }
    return result
  }
  private func rebuildMetadata() {
    starts.removeAll(keepingCapacity: true)
    total = Summary()
    for block in blocks {
      starts.append(total.value.utf16Units)
      total = total.joined(block.summary)
    }
  }
  private func blockIndex(_ position: Int) -> Int {
    var lower = 0
    var upper = starts.count
    while lower < upper {
      let middle = (lower + upper) / 2
      if starts[middle] <= position { lower = middle + 1 } else { upper = middle }
    }
    return max(0, min(blocks.count - 1, lower - 1))
  }
  public func apply(range: NSRange, replacement: String) throws {
    guard range.location >= 0, range.length >= 0, range.location <= total.value.utf16Units,
      range.length <= total.value.utf16Units - range.location
    else { throw ToolboxError("统计版本或编辑范围不匹配") }
    if blocks.isEmpty {
      blocks = try makeBlocks(replacement)
      rebuildMetadata()
      return
    }
    let first = max(0, blockIndex(range.location) - 1)
    let last = min(blocks.count - 1, blockIndex(NSMaxRange(range)) + 1)
    let context = blocks[first...last].map(\.text).joined() as NSString
    let updated = context.replacingCharacters(
      in: NSRange(location: range.location - starts[first], length: range.length), with: replacement
    )
    guard
      total.value.utf8Bytes - (context as String).utf8.count + updated.utf8.count
        <= TextWorkbench.editorBytes
    else { throw ToolboxError("统计文本超过 32 MiB") }
    let rebuilt = try makeBlocks(updated)
    try Task.checkCancellation()
    blocks.replaceSubrange(first...last, with: rebuilt)
    rebuildMetadata()
  }
  public func selection(_ ranges: [NSRange]) throws -> TextStatistics {
    var normalized: [NSRange] = []
    for range in ranges.filter({ $0.length > 0 }).sorted(by: { $0.location < $1.location }) {
      guard range.location >= 0, range.location <= total.value.utf16Units,
        range.length <= total.value.utf16Units - range.location
      else { throw ToolboxError("选区已变化") }
      if let last = normalized.last, NSMaxRange(last) >= range.location {
        normalized[normalized.count - 1].length =
          max(NSMaxRange(last), NSMaxRange(range)) - last.location
      } else {
        normalized.append(range)
      }
    }
    var result = TextStatistics()
    for range in normalized {
      if range.location == 0, range.length == total.value.utf16Units {
        result.add(total.value)
        continue
      }
      let first = blockIndex(range.location)
      let last = blockIndex(NSMaxRange(range) - 1)
      var summary = Summary()
      for i in first...last {
        try Task.checkCancellation()
        let intersection = NSIntersectionRange(
          range, NSRange(location: starts[i], length: blocks[i].summary.value.utf16Units))
        if intersection.length == blocks[i].summary.value.utf16Units {
          summary = summary.joined(blocks[i].summary)
        } else {
          let text = (blocks[i].text as NSString).substring(
            with: NSRange(location: intersection.location - starts[i], length: intersection.length))
          summary = summary.joined(try scan(text))
        }
      }
      result.add(summary.value)
    }
    return result
  }
}

public actor TextStatisticsWorker {
  private var index: TextStatisticsIndex?
  private var revision = -1
  public init() {}
  public func reset(_ text: String, revision: Int) throws -> TextStatistics {
    let next = try TextStatisticsIndex(text)
    try Task.checkCancellation()
    index = next
    self.revision = revision
    return next.snapshot
  }
  public func edit(_ range: NSRange, replacement: String, before: Int, revision: Int) throws
    -> TextStatistics?
  {
    guard let index, self.revision == before else { return nil }
    try index.apply(range: range, replacement: replacement)
    self.revision = revision
    return index.snapshot
  }
  public func selection(_ ranges: [NSRange], revision: Int) throws -> TextStatistics? {
    guard let index, self.revision == revision else { return nil }
    return try index.selection(ranges)
  }
}
