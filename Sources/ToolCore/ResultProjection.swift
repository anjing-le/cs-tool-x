import Foundation

/// Filtering only the loaded result, while preserving source row identity for details.
public struct ResultProjection: Sendable {
  public let rows: [[String]]
  private let search: [String]
  public init(_ output: QueryOutput) {
    let full = output.rows.map { $0.map(\.text) }
    rows = full.map { row in
      row.map { text in
        return text.count > 2048 ? String(text.prefix(2048)) + "…" : text
      }
    }
    search = full.map { $0.joined(separator: "\n").lowercased() }
  }
  public func indices(matching filter: String) -> [Int] {
    let text = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return text.isEmpty ? Array(rows.indices) : rows.indices.filter { search[$0].contains(text) }
  }
}
public enum DataObjectQuery {
  public static func select(kind: DatabaseKind, schema: String, table: String) -> String? {
    guard kind == .mysql || kind == .pg else { return nil }
    let quote = kind == .mysql ? "`" : "\""
    func identifier(_ value: String) -> String {
      quote + value.replacingOccurrences(of: quote, with: quote + quote) + quote
    }
    return "SELECT * FROM \(identifier(schema)).\(identifier(table)) LIMIT 100;"
  }
}
