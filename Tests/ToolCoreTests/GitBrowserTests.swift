import Foundation
import XCTest

@testable import ToolCore

private final class ScanProgressProbe: @unchecked Sendable {
  private let lock = NSLock()
  private var counts: [Int] = []
  func record(_ locations: [GitLocation]) { lock.lock(); counts.append(locations.count); lock.unlock() }
  func values() -> [Int] { lock.lock(); defer { lock.unlock() }; return counts }
}
private actor PageProgressProbe {
  var pages: [GitRootPage] = []
  func record(_ page: GitRootPage) { pages.append(page) }
}
final class GitBrowserTests: XCTestCase {
  func git(_ path: URL, _ args: [String]) throws -> String {
    let process = Process()
    let out = Pipe()
    let err = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["-C", path.path] + args
    var environment = ProcessInfo.processInfo.environment
    environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
    environment["GIT_CONFIG_NOSYSTEM"] = "1"
    environment["GIT_AUTHOR_NAME"] = "Fixture Author"
    environment["GIT_AUTHOR_EMAIL"] = "fixture@example.invalid"
    environment["GIT_COMMITTER_NAME"] = "Fixture Author"
    environment["GIT_COMMITTER_EMAIL"] = "fixture@example.invalid"
    process.environment = environment
    process.standardOutput = out
    process.standardError = err
    try process.run()
    process.waitUntilExit()
    let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    guard process.terminationStatus == 0 else {
      throw ToolError.message(
        String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }
  func testDiscoveryRefsGraphQueriesDetailsAndNoWrites() async throws {
    let initial = FileManager.default.temporaryDirectory.appendingPathComponent(
      "git browser " + UUID().uuidString)
    try FileManager.default.createDirectory(at: initial, withIntermediateDirectories: true)
    let root = URL(fileURLWithPath: try GitBrowser.canonicalPath(initial.path))
    let repo = root.appendingPathComponent("one")
    try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    _ = try git(repo, ["init", "-b", "main"])
    try Data("base".utf8).write(to: repo.appendingPathComponent("a.txt"))
    _ = try git(repo, ["add", "."])
    _ = try git(repo, ["commit", "-m", "initial commit"])
    _ = try git(repo, ["tag", "-a", "v1", "-m", "annotated tag"])
    _ = try git(repo, ["checkout", "-b", "feature/颜色"])
    try Data("feature".utf8).write(to: repo.appendingPathComponent("feature\nname.txt"))
    _ = try git(repo, ["add", "."])
    _ = try git(repo, ["commit", "-m", "feature search needle", "-m", "body needle"])
    let feature = try git(repo, ["rev-parse", "HEAD"])
    _ = try git(repo, ["checkout", "main"])
    try Data("main".utf8).write(to: repo.appendingPathComponent("main.txt"))
    _ = try git(repo, ["add", "."])
    _ = try git(repo, ["commit", "-m", "main work"])
    _ = try git(repo, ["merge", "--no-ff", "feature/颜色", "-m", "merge feature"])
    _ = try git(repo, ["update-ref", "refs/remotes/origin/main", "HEAD"])
    let linked = root.appendingPathComponent("linked")
    _ = try git(repo, ["worktree", "add", "--detach", linked.path, "HEAD~1"])
    _ = try git(root, ["init", "--bare", root.appendingPathComponent("bare.git").path])
    let nested = repo.appendingPathComponent("nested")
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    _ = try git(nested, ["init", "-b", "empty"])
    try FileManager.default.createSymbolicLink(
      at: root.appendingPathComponent("loop"), withDestinationURL: root)
    let progress = ScanProgressProbe()
    let scan = try await GitBrowser.scan(directory: root.path, progress: { progress.record($0) })
    XCTAssertEqual(progress.values().first, 1, "First discovery is delivered before traversal completes")
    XCTAssertEqual(scan.repositories.count, 4)
    XCTAssertFalse(scan.limited)
    let snapshots = try await GitBrowser.repositories(scan.repositories)
    let snapshot = try XCTUnwrap(
      snapshots.first { $0.id == repo.path }, "Expected \(repo.path); actual \(snapshots.map(\.id))"
    )
    XCTAssertEqual(snapshot.branch, "main")
    XCTAssertTrue(snapshot.references.contains { $0.name == "origin/main" && $0.kind == .remote })
    let streamed = PageProgressProbe()
    let batch = try await GitBrowser.logs(snapshots, filter: GitLogFilter(), offsets: [:], limit: 2,
      progress: { await streamed.record($0) })
    let delivered = await streamed.pages
    XCTAssertEqual(Set(delivered.map(\.repository)), Set(batch.map(\.repository)))
    XCTAssertEqual(delivered.count, snapshots.count, "Each repository page is delivered exactly once")
    XCTAssertEqual(snapshot.clippedReferences(to: 1).references.count, 1)
    XCTAssertTrue(snapshot.clippedReferences(to: 1).limited)
    let index = try Data(contentsOf: repo.appendingPathComponent(".git/index"))
    let head = try Data(contentsOf: repo.appendingPathComponent(".git/HEAD"))
    let first = try await GitBrowser.log(snapshot, limit: 2)
    XCTAssertTrue(first.hasMore)
    let second = try await GitBrowser.log(snapshot, offset: first.nextOffset, limit: 2)
    XCTAssertEqual(Set((first.commits + second.commits).map(\.oid)).count, 4)
    let all = try await GitBrowser.log(snapshot)
    XCTAssertEqual(all.commits.count, 4)
    XCTAssertEqual(all.commits.first?.parents.count, 2)
    let tag = try XCTUnwrap(snapshot.references.first { $0.kind == .tag })
    XCTAssertEqual(tag.oid, all.commits.last?.oid, "Annotated tag resolves to commit")
    let graph = GitGraph.rows(all.commits)
    XCTAssertEqual(graph.count, 4)
    XCTAssertEqual(graph[0].segments.filter { $0.part == .outgoing }.count, 2)
    var filter = GitLogFilter()
    filter.text = "body needle"
    let found = try await GitBrowser.log(snapshot, filter: filter)
    XCTAssertEqual(found.commits.map(\.oid), [feature])
    filter.author = "Fixture Author"
    let combined = try await GitBrowser.log(snapshot, filter: filter)
    XCTAssertEqual(combined.commits.map(\.oid), [feature])
    filter.text = String(feature.prefix(10))
    let hash = try await GitBrowser.log(snapshot, filter: filter)
    XCTAssertEqual(hash.commits.map(\.oid), [feature])
    filter.text = ""
    filter.reference = "--all"
    do {
      _ = try await GitBrowser.log(snapshot, filter: filter)
      XCTFail("Must reject non-ref revision")
    } catch {}
    let detail = try await GitBrowser.detail(repository: snapshot, oid: feature)
    XCTAssertTrue(detail.message.contains("body needle"))
    XCTAssertEqual(detail.files.first?.path, "feature\nname.txt")
    let merge = try await GitBrowser.detail(repository: snapshot, oid: snapshot.head)
    XCTAssertTrue(merge.files.contains { $0.path == "feature\nname.txt" })
    let empty = try XCTUnwrap(snapshots.first { $0.id == nested.path })
    let emptyLog = try await GitBrowser.log(empty)
    XCTAssertTrue(emptyLog.commits.isEmpty)
    XCTAssertEqual(empty.branch, "empty")
    let detached = try XCTUnwrap(snapshots.first { $0.id == linked.path })
    XCTAssertTrue(detached.branch.isEmpty)
    XCTAssertTrue(detached.branchLabel.hasPrefix("Detached"))
    XCTAssertEqual(try Data(contentsOf: repo.appendingPathComponent(".git/index")), index)
    XCTAssertEqual(try Data(contentsOf: repo.appendingPathComponent(".git/HEAD")), head)
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: repo.appendingPathComponent(".git/index.lock").path))
  }
  func testGraphKeepsIdenticalHashesInDifferentRepositoriesSeparate() {
    let parent = String(repeating: "a", count: 40)
    let child = String(repeating: "b", count: 40)
    func commit(_ repo: String, _ oid: String, _ parents: [String]) -> GitCommit {
      GitCommit(
        repository: repo, oid: oid, parents: parents, author: "fixture",
        email: "fixture@example.invalid", timestamp: 1, subject: "fixture")
    }
    let rows = GitGraph.rows([
      commit("one", child, [parent]), commit("two", child, [parent]), commit("one", parent, []),
      commit("two", parent, []),
    ])
    XCTAssertEqual(rows[0].column, 0)
    XCTAssertEqual(rows[1].column, 1)
    XCTAssertEqual(rows[2].column, 0)
    XCTAssertEqual(rows[3].column, 0)
    XCTAssertTrue(rows[1].segments.contains { $0.part == .through })
  }
  func testCancellingReaderStopsProcessPromptly() async throws {
    let start = Date()
    let task = Task {
      try await BoundedProcess.run(
        executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], timeout: 12)
    }
    try await Task.sleep(nanoseconds: 100_000_000)
    task.cancel()
    do {
      _ = try await task.value
      XCTFail("Expected cancellation")
    } catch is CancellationError {} catch { XCTFail("Unexpected error") }
    XCTAssertLessThan(Date().timeIntervalSince(start), 3)
  }
}
