import CryptoKit
import Darwin
import Foundation

public struct GitLocation: Codable, Sendable, Equatable, Identifiable {
  public var id: String { path }
  public let path: String
  public let name: String
  public let bare: Bool
  public init(path: String, name: String, bare: Bool = false) {
    self.path = path
    self.name = name
    self.bare = bare
  }
}
public struct GitScan: Codable, Sendable {
  public let root: String
  public let repositories: [GitLocation]
  public let visited: Int
  public let elapsedMs: Int
  public let limited: Bool
  public let warnings: [String]
}
public struct GitReference: Codable, Sendable, Equatable, Identifiable {
  public enum Kind: String, Codable, Sendable { case local, remote, tag }
  public var id: String { fullName }
  public let fullName: String
  public let name: String
  public let oid: String
  public let kind: Kind
  public let current: Bool
  public let upstream: String
}
public struct GitRepository: Codable, Sendable, Identifiable {
  public var id: String { location.id }
  public let location: GitLocation
  public let branch: String
  public let head: String
  public let references: [GitReference]
  public let limited: Bool
  public let error: String?
  public static func unloaded(_ location: GitLocation) -> GitRepository {
    GitRepository(location: location, branch: "", head: "", references: [], limited: false, error: nil)
  }
  public func clippedReferences(to count: Int) -> GitRepository {
    GitRepository(location: location, branch: branch, head: head,
      references: Array(references.prefix(max(0, count))),
      limited: limited || references.count > count, error: error)
  }
  public var branchLabel: String {
    branch.isEmpty ? (head.isEmpty ? "空仓库" : "Detached " + head.prefix(8)) : branch
  }
}
public struct GitCommit: Codable, Sendable, Identifiable, Equatable {
  public var id: String { repository + ":" + oid }
  public let repository: String
  public let oid: String
  public let parents: [String]
  public let author: String
  public let email: String
  public let timestamp: Int64
  public let subject: String
}
public struct GitLogFilter: Codable, Sendable, Equatable {
  public var reference: String = ""
  public var text: String = ""
  public var author: String = ""
  public var days: Int = 0
  public init() {}
  public func validate() throws {
    guard reference.utf8.count <= 4096, text.utf8.count <= 1024, author.utf8.count <= 256,
      [0, 7, 30, 90, 365].contains(days),
      ![reference, text, author].contains(where: { $0.contains("\0") })
    else { throw ToolError.message("Git 筛选条件无效或超过长度上限。") }
  }
}
public struct GitLogPage: Codable, Sendable {
  public let commits: [GitCommit]
  public let hasMore: Bool
  public let nextOffset: Int
}
public struct GitFileChange: Codable, Sendable, Equatable {
  public let status: String
  public let path: String
  public let additions: Int?
  public let deletions: Int?
  public let binary: Bool?
  public init(status: String, path: String, additions: Int? = nil, deletions: Int? = nil, binary: Bool? = nil) {
    self.status = status; self.path = path
    self.additions = additions; self.deletions = deletions; self.binary = binary
  }
}
public struct GitCommitDetail: Codable, Sendable {
  public let oid: String
  public let message: String
  public let files: [GitFileChange]
  public let limited: Bool
  public let filesLimited: Bool
  public let statisticsError: String?
}

/// Local read-only plumbing. No shell interpolation, network, status/index refresh or Git write commands.
public enum GitBrowser {
  // Skip only known generated/dependency directory names below the selected root.
  // Opening one explicitly still scans it, and ordinary nested/worktree repos remain visible.
  public static let excludedDirectoryNames: Set<String> = [
    ".git", ".build", ".swiftpm", "node_modules", "Pods", "Carthage",
    ".gradle", ".venv", "__pycache__", ".cache", ".local", "dist", "target",
  ]
  public static let maxRepositories = 500
  public static let maxScanEntries = 250_000
  public static let maxTotalReferences = 20_000
  public static let maxReferences = 5000
  public static let pageSize = 200
  public static let maxLoadedCommits = 2000
  public static func canonicalPath(_ path: String) throws -> String {
    guard path.utf8.count <= 16_384, !path.contains("\0"), let resolved = realpath(path, nil) else {
      throw ToolError.message("目录不存在或无法读取。")
    }
    defer { free(resolved) }
    return String(cString: resolved)
  }
  public static func colorIndex(_ key: String) -> Int {
    Int(Array(SHA256.hash(data: Data(key.utf8)))[0]) % 8
  }
  public static func scan(
    directory: String, progress: (@Sendable ([GitLocation]) -> Void)? = nil
  ) async throws -> GitScan {
    let task = Task.detached(priority: .userInitiated) { try discover(directory, progress: progress) }
    return try await withTaskCancellationHandler(
      operation: { try await task.value }, onCancel: { task.cancel() })
  }
  private static func discover(_ directory: String, progress: (@Sendable ([GitLocation]) -> Void)?) throws -> GitScan {
    guard directory.utf8.count <= 16_384, !directory.contains("\0") else {
      throw ConfigurationError.invalid
    }
    let root = URL(fileURLWithPath: try canonicalPath(directory))
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else {
      throw ToolError.message("请选择存在且可读取的目录。")
    }
    let fm = FileManager.default
    var locations: [GitLocation] = []
    var warnings: [String] = []
    var seen = Set<String>()
    var visited = 0
    var limited = false
    let started = ProcessInfo.processInfo.systemUptime
    var lastProgress = -Double.infinity
    var lastPublishedCount = 0
    func publishProgress() {
      guard progress != nil, locations.count != lastPublishedCount else { return }
      let now = ProcessInfo.processInfo.systemUptime
      if now - lastProgress >= 0.1 {
        lastProgress = now
        lastPublishedCount = locations.count
        progress?(locations)
      }
    }
    func add(_ url: URL, bare: Bool) {
      guard let path = try? canonicalPath(url.path), seen.insert(path).inserted else { return }
      locations.append(GitLocation(path: path, name: url.lastPathComponent, bare: bare))
      publishProgress()
    }
    func inspect(_ url: URL) {
      let dot = url.appendingPathComponent(".git")
      if fm.fileExists(atPath: dot.path) {
        add(url, bare: false)
      } else if fm.fileExists(atPath: url.appendingPathComponent("HEAD").path),
        fm.fileExists(atPath: url.appendingPathComponent("objects").path),
        fm.fileExists(atPath: url.appendingPathComponent("refs").path)
      {
        add(url, bare: true)
      }
    }
    inspect(root)
    // Breadth-first discovery finds sibling projects before descending into a project's large dependency tree.
    var queue = locations.first?.bare == true ? [] : [root]
    var next = 0
    scan: while next < queue.count {
      try Task.checkCancellation()
      let directory = queue[next]
      next += 1
      guard
        let enumerator = fm.enumerator(
          at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
          options: [.skipsSubdirectoryDescendants],
          errorHandler: { url, _ in
            if warnings.count < 20 { warnings.append("无法读取：" + url.path) }
            return true
          })
      else {
        if warnings.count < 20 { warnings.append("无法读取：" + directory.path) }
        continue
      }
      while let url = enumerator.nextObject() as? URL {
        visited += 1
        if visited % 128 == 0 {
          try Task.checkCancellation()
          publishProgress()
        }
        if visited >= maxScanEntries || locations.count >= maxRepositories
          || ProcessInfo.processInfo.systemUptime - started >= 20
        {
          limited = true
          break scan
        }
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values?.isSymbolicLink != true, values?.isDirectory == true,
          !excludedDirectoryNames.contains(url.lastPathComponent)
        else { continue }
        let count = locations.count
        inspect(url)
        if locations.count > count && locations.last?.bare == true { continue }
        if queue.count - next >= 20_000 {
          limited = true
          break scan
        }
        queue.append(url)
      }
      publishProgress()
      if next >= 4096 {
        queue.removeFirst(next)
        next = 0
      }
    }
    try Task.checkCancellation()
    return GitScan(
      root: root.path,
      repositories: locations.sorted {
        $0.path.localizedStandardCompare($1.path) == .orderedAscending
      }, visited: visited, elapsedMs: Int((ProcessInfo.processInfo.systemUptime - started) * 1000),
      limited: limited, warnings: warnings)
  }
  private static func run(
    _ path: String, _ args: [String], bytes: Int = 4 * 1024 * 1024, allowFailure: Bool = false,
    deadline: Double? = nil
  ) async throws -> CommandResult {
    try Task.checkCancellation()
    guard path.utf8.count <= 16_384, !path.contains("\0") else { throw ConfigurationError.invalid }
    var environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
    environment["GIT_NO_LAZY_FETCH"] = "1"
    environment["GIT_ALLOW_PROTOCOL"] = ""
    environment["GIT_OPTIONAL_LOCKS"] = "0"
    environment["GIT_TERMINAL_PROMPT"] = "0"
    environment["GIT_CONFIG_NOSYSTEM"] = "1"
    environment["GIT_CONFIG_GLOBAL"] = "/dev/null"
    environment["LC_ALL"] = "C"
    let prefix = [
      "--no-pager", "--no-optional-locks", "-c", "core.fsmonitor=false", "-c",
      "core.hooksPath=/dev/null", "-c", "log.showSignature=false", "-c", "core.quotePath=false",
      "-C", path,
    ]
    let remaining = deadline.map { $0 - ProcessInfo.processInfo.systemUptime } ?? 12
    guard remaining > 0 else { throw ToolError.message("批量读取达到 30 秒预算，请缩小仓库范围后刷新。") }
    let result = try await BoundedProcess.run(
      executable: URL(fileURLWithPath: "/usr/bin/git"), arguments: prefix + args,
      environment: environment, timeout: min(12, remaining), maxOutputBytes: bytes)
    try Task.checkCancellation()
    guard !result.timedOut else { throw ToolError.message("Git 读取超时，请缩小范围后重试。") }
    guard !result.truncated else { throw ToolError.message("Git 输出超过读取预算，请缩小范围。") }
    guard allowFailure || result.exitCode == 0 else {
      throw ToolError.message(
        String(result.stderr.prefix(1500)).trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return result
  }
  public static func repository(_ location: GitLocation, deadline: Double? = nil) async throws
    -> GitRepository
  {
    let refsResult = try await run(
      location.path,
      [
        "for-each-ref", "--count=5001", "--sort=refname",
        "--format=%(refname)%00%(objectname)%00%(HEAD)%00%(upstream)%00%(symref)%00%(*objectname)",
        "refs/heads", "refs/remotes", "refs/tags",
      ], bytes: 8 * 1024 * 1024, deadline: deadline)
    let references = refsResult.stdout.split(separator: "\n").compactMap { line -> GitReference? in
      let fields = line.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
      guard fields.count == 6, fields[4].isEmpty else { return nil }
      let kind: GitReference.Kind =
        fields[0].hasPrefix("refs/heads/")
        ? .local : fields[0].hasPrefix("refs/remotes/") ? .remote : .tag
      let prefix = kind == .local ? "refs/heads/" : kind == .remote ? "refs/remotes/" : "refs/tags/"
      return GitReference(
        fullName: fields[0], name: String(fields[0].dropFirst(prefix.count)),
        oid: fields[5].isEmpty ? fields[1] : fields[5], kind: kind, current: fields[2] == "*",
        upstream: fields[3])
    }
    let current = references.first(where: \.current)
    var head = current?.oid ?? ""
    var branch = current?.name ?? ""
    if current == nil {
      let branchResult = try await run(
        location.path, ["symbolic-ref", "--quiet", "--short", "HEAD"], bytes: 64 * 1024,
        allowFailure: true, deadline: deadline)
      branch =
        branchResult.exitCode == 0
        ? branchResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : ""
      let headResult = try await run(
        location.path, ["rev-parse", "--verify", "HEAD^{commit}"], bytes: 64 * 1024,
        allowFailure: true, deadline: deadline)
      head =
        headResult.exitCode == 0
        ? headResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }
    return GitRepository(
      location: location, branch: branch, head: head,
      references: Array(references.prefix(maxReferences)),
      limited: references.count > maxReferences, error: nil)
  }
  public static func repositories(
    _ locations: [GitLocation], progress: (@Sendable (GitRepository) async -> Void)? = nil
  ) async throws -> [GitRepository] {
    guard locations.count <= maxRepositories else { throw ConfigurationError.invalid }
    var output: [GitRepository] = []
    var referenceCount = 0
    let deadline = ProcessInfo.processInfo.systemUptime + 30
    try await withThrowingTaskGroup(of: GitRepository.self) { group in
      var iterator = locations.makeIterator()
      func submit(_ location: GitLocation) {
        group.addTask {
          do {
            return try await repository(location, deadline: deadline)
          } catch is CancellationError { throw CancellationError() } catch {
            return GitRepository(
              location: location, branch: "", head: "", references: [], limited: false,
              error: error.localizedDescription)
          }
        }
      }
      for _ in 0..<min(4, locations.count) {
        if let location = iterator.next() { submit(location) }
      }
      while let read = try await group.next() {
        let room = max(0, maxTotalReferences - referenceCount)
        let result = GitRepository(
          location: read.location, branch: read.branch, head: read.head,
          references: Array(read.references.prefix(room)),
          limited: read.limited || read.references.count > room, error: read.error)
        referenceCount += result.references.count
        output.append(result)
        await progress?(result)
        try Task.checkCancellation()
        if let location = iterator.next() { submit(location) }
      }
    }
    return output.sorted {
      $0.location.path.localizedStandardCompare($1.location.path) == .orderedAscending
    }
  }
  public static func log(
    _ repository: GitRepository, filter: GitLogFilter = GitLogFilter(), offset: Int = 0,
    limit: Int = pageSize, deadline: Double? = nil
  ) async throws -> GitLogPage {
    try filter.validate()
    guard offset >= 0, offset < maxLoadedCommits, limit > 0, limit <= pageSize else {
      throw ConfigurationError.invalid
    }
    guard repository.error == nil else { throw ToolError.message(repository.error!) }
    if repository.head.isEmpty && repository.references.isEmpty {
      return GitLogPage(commits: [], hasMore: false, nextOffset: offset)
    }
    var args = [
      "log", "--topo-order", "--no-show-signature", "--no-decorate", "--fixed-strings",
      "--regexp-ignore-case", "--format=%H%x00%P%x00%an%x00%ae%x00%at%x00%s", "-z",
      "--max-count=\(limit + 1)", "--skip=\(offset)",
    ]
    if filter.days > 0 {
      args.append("--since=@\(Int(Date().timeIntervalSince1970) - filter.days * 86400)")
    }
    if !filter.author.isEmpty { args += ["--author=" + filter.author] }
    let hashSearch =
      filter.text.count >= 7 && filter.text.count <= 64
      && filter.text.allSatisfy { $0.isHexDigit && $0.isASCII }
    if !filter.text.isEmpty && !hashSearch { args += ["--grep=" + filter.text] }
    if hashSearch {
      let result = try await run(
        repository.id, ["rev-parse", "--verify", "--end-of-options", filter.text + "^{commit}"],
        bytes: 65536, allowFailure: true, deadline: deadline)
      guard result.exitCode == 0 else {
        return GitLogPage(commits: [], hasMore: false, nextOffset: offset)
      }
      args += ["--no-walk", result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)]
    } else if !filter.reference.isEmpty {
      guard repository.references.contains(where: { $0.fullName == filter.reference }) else {
        throw ToolError.message("所选分支已不存在，请刷新仓库。")
      }
      args.append(filter.reference)
    } else {
      args += ["--branches", "--remotes", "--tags"]
      if !repository.head.isEmpty { args.append("HEAD") }
    }
    args.append("--")
    let result = try await run(repository.id, args, deadline: deadline)
    let fields = result.stdout.split(separator: "\0", omittingEmptySubsequences: false).map(
      String.init)
    var commits: [GitCommit] = []
    var index = 0
    while index + 5 < fields.count {
      let oid = fields[index]
      guard validOID(oid), let timestamp = Int64(fields[index + 4]) else {
        throw ToolError.message("Git 提交记录格式无效。")
      }
      commits.append(
        GitCommit(
          repository: repository.id, oid: oid,
          parents: fields[index + 1].split(separator: " ").map(String.init),
          author: fields[index + 2], email: fields[index + 3], timestamp: timestamp,
          subject: fields[index + 5]))
      index += 6
    }
    return GitLogPage(
      commits: Array(commits.prefix(limit)), hasMore: commits.count > limit,
      nextOffset: offset + min(commits.count, limit))
  }
  public static func detail(repository: GitRepository, oid: String, includeStatistics: Bool = true) async throws -> GitCommitDetail
  {
    guard validOID(oid) else { throw ConfigurationError.invalid }
    let message = try await run(
      repository.id, ["show", "--no-patch", "--format=%B", "--no-show-signature", oid, "--"],
      bytes: 256 * 1024)
    let files = try await run(
      repository.id,
      [
        "show", "--format=", "--root", "--name-status", "--no-renames", "--no-ext-diff",
        "--no-textconv", "-z", "--diff-merges=first-parent", oid, "--",
      ], bytes: 1024 * 1024)
    let fields = files.stdout.split(separator: "\0", omittingEmptySubsequences: true).map(
      String.init)
    var changes: [GitFileChange] = []
    for index in stride(from: 0, to: max(0, fields.count - 1), by: 2) {
      changes.append(GitFileChange(status: fields[index], path: fields[index + 1]))
      if changes.count >= 1001 { break }
    }
    var shown = Array(changes.prefix(1000))
    var statisticsError: String?
    if includeStatistics {
      do { shown = try await statistics(repository: repository, oid: oid, changes: shown) }
      catch is CancellationError { throw CancellationError() }
      catch { statisticsError = error.localizedDescription }
    }
    return GitCommitDetail(
      oid: oid, message: String(message.stdout.prefix(64_000)), files: shown,
      limited: changes.count > 1000 || message.stdout.count > 64_000,
      filesLimited: changes.count > 1000, statisticsError: statisticsError)
  }
  /// First-parent changed-line counts; no patch is returned and binary files have no numeric count.
  public static func statistics(repository: GitRepository, oid: String, changes: [GitFileChange]) async throws -> [GitFileChange] {
    guard validOID(oid), changes.count <= 1000 else { throw ConfigurationError.invalid }
    if changes.isEmpty { return [] }
    let result = try await run(repository.id, [
      "show", "--format=", "--root", "--numstat", "--no-renames", "--no-ext-diff",
      "--no-textconv", "-z", "--diff-merges=first-parent", oid, "--",
    ], bytes: 1024 * 1024, deadline: ProcessInfo.processInfo.systemUptime + 8)
    let wanted = Set(changes.map(\.path))
    var counts: [String: (Int?, Int?, Bool)] = [:]
    for record in result.stdout.split(separator: "\0", omittingEmptySubsequences: true) {
      let fields = record.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
      guard fields.count == 3 else { throw ToolError.message("Git 行数统计格式无效。") }
      let path = String(fields[2])
      guard wanted.contains(path) else { continue }
      if fields[0] == "-", fields[1] == "-" {
        counts[path] = (nil, nil, true)
      } else {
        guard let added = Int(fields[0]), let removed = Int(fields[1]), added >= 0, removed >= 0 else {
          throw ToolError.message("Git 行数统计超出支持范围。")
        }
        counts[path] = (added, removed, false)
      }
    }
    return try changes.map { change in
      guard let (added, removed, binary) = counts[change.path] else {
        throw ToolError.message("部分文件缺少行数统计，请刷新后重试。")
      }
      return GitFileChange(status: change.status, path: change.path, additions: added, deletions: removed, binary: binary)
    }
  }
  public static func validOID(_ oid: String) -> Bool {
    [40, 64].contains(oid.count) && oid.allSatisfy { $0.isASCII && $0.isHexDigit }
  }
  /// Merge topologically ordered per-root lists by their front timestamp; never reorder a root's parents before children.
  public static func merge(_ lists: [[GitCommit]]) -> [GitCommit] {
    var indices = Array(repeating: 0, count: lists.count)
    var output: [GitCommit] = []
    while let next = lists.indices.filter({ indices[$0] < lists[$0].count }).max(by: {
      lists[$0][indices[$0]].timestamp < lists[$1][indices[$1]].timestamp
    }) {
      output.append(lists[next][indices[next]])
      indices[next] += 1
    }
    return output
  }
}
