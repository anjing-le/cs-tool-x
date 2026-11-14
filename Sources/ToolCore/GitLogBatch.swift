import Foundation

public struct GitRootPage: Sendable {
  public let repository: String
  public let page: GitLogPage?
  public let error: String?
}
extension GitBrowser {
  public static func logs(
    _ repositories: [GitRepository], filter: GitLogFilter, offsets: [String: Int], limit: Int,
    progress: (@Sendable (GitRootPage) async -> Void)? = nil
  ) async throws -> [GitRootPage] {
    guard repositories.count <= maxRepositories else { throw ConfigurationError.invalid }
    var output: [GitRootPage] = []
    let deadline = ProcessInfo.processInfo.systemUptime + 30
    try await withThrowingTaskGroup(of: GitRootPage.self) { group in
      var iterator = repositories.makeIterator()
      func submit(_ repository: GitRepository) {
        group.addTask {
          do {
            return GitRootPage(
              repository: repository.id,
              page: try await log(
                repository, filter: filter, offset: offsets[repository.id] ?? 0, limit: limit,
                deadline: deadline), error: nil)
          } catch is CancellationError { throw CancellationError() } catch {
            return GitRootPage(
              repository: repository.id, page: nil, error: error.localizedDescription)
          }
        }
      }
      for _ in 0..<min(4, repositories.count) {
        if let repository = iterator.next() { submit(repository) }
      }
      while let result = try await group.next() {
        output.append(result)
        await progress?(result)
        try Task.checkCancellation()
        if let repository = iterator.next() { submit(repository) }
      }
    }
    return output
  }
}
