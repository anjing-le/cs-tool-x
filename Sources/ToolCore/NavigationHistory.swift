/// Bounded page identities only; never stores manuscript or connection snapshots.
public struct NavigationHistory<Page: Equatable> {
  public private(set) var pages: [Page]
  public private(set) var index = 0
  private let limit: Int
  public init(_ initial: Page, limit: Int = 100) {
    pages = [initial]
    self.limit = max(2, limit)
  }
  public var current: Page { pages[index] }
  public var canGoBack: Bool { index > 0 }
  public var canGoForward: Bool { index + 1 < pages.count }
  @discardableResult public mutating func visit(_ page: Page) -> Bool {
    guard page != current else { return false }
    pages.removeSubrange((index + 1)..<pages.count)
    pages.append(page)
    if pages.count > limit { pages.removeFirst(pages.count - limit) }
    index = pages.count - 1
    return true
  }
  public mutating func back() -> Page? {
    guard canGoBack else { return nil }
    index -= 1
    return current
  }
  public mutating func forward() -> Page? {
    guard canGoForward else { return nil }
    index += 1
    return current
  }
}
