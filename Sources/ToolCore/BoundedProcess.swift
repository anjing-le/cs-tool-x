import Foundation

public struct CommandResult: Codable, Sendable {
  public let stdout: String
  public let stderr: String
  public let exitCode: Int32
  public let timedOut: Bool
  public let truncated: Bool
  public let elapsedMs: Int
}
/// Concurrent pipe draining, shared stdout/stderr budget, deadline and local-process termination.
public enum BoundedProcess {
  public static func run(
    executable: URL, arguments: [String], environment: [String: String]? = nil,
    input: Data? = nil, timeout: Double = 15, maxOutputBytes: Int = 1024 * 1024
  ) async throws -> CommandResult {
    guard timeout > 0, timeout <= 120, maxOutputBytes > 0, maxOutputBytes <= 8 * 1024 * 1024,
      (input?.count ?? 0) <= 128 * 1024
    else { throw ConfigurationError.invalid }
    let session = ProcessSession(timeout: timeout, budget: maxOutputBytes)
    return try await withCheckedThrowingContinuation { continuation in
      session.start(
        executable: executable, arguments: arguments, environment: environment, input: input,
        continuation: continuation)
    }
  }
}
private final class ProcessSession: @unchecked Sendable {
  let process = Process()
  let out = Pipe(), err = Pipe()
  let lock = NSLock()
  let timeout: Double, budget: Int
  let started = ProcessInfo.processInfo.systemUptime
  var stdout = Data(), stderr = Data()
  var outputEOF = false, errorEOF = false, exited = false, finished = false, timedOut = false,
    truncated = false
  var completion: CheckedContinuation<CommandResult, Error>?
  var timer: DispatchSourceTimer?
  var writer: Pipe?
  init(timeout: Double, budget: Int) {
    self.timeout = timeout
    self.budget = budget
  }
  func start(
    executable: URL, arguments: [String], environment: [String: String]?, input: Data?,
    continuation: CheckedContinuation<CommandResult, Error>
  ) {
    completion = continuation
    process.executableURL = executable
    process.arguments = arguments
    process.environment = environment
    process.standardOutput = out
    process.standardError = err
    if input != nil {
      writer = Pipe()
      process.standardInput = writer!
    } else {
      process.standardInput = FileHandle.nullDevice
    }
    out.fileHandleForReading.readabilityHandler = { [weak self] handle in
      self?.read(handle, isError: false)
    }
    err.fileHandleForReading.readabilityHandler = { [weak self] handle in
      self?.read(handle, isError: true)
    }
    process.terminationHandler = { [self] _ in
      lock.lock()
      exited = true
      lock.unlock()
      finishIfReady()
      DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
        self?.finishIfReady(force: true)
      }
    }
    do { try process.run() } catch {
      process.terminationHandler = nil
      out.fileHandleForReading.readabilityHandler = nil
      err.fileHandleForReading.readabilityHandler = nil
      try? out.fileHandleForReading.close()
      try? err.fileHandleForReading.close()
      try? writer?.fileHandleForReading.close()
      try? writer?.fileHandleForWriting.close()
      completion = nil
      continuation.resume(throwing: error)
      return
    }
    try? out.fileHandleForWriting.close()
    try? err.fileHandleForWriting.close()
    if let input, let writer {
      try? writer.fileHandleForReading.close()
      DispatchQueue.global().async {
        try? writer.fileHandleForWriting.write(contentsOf: input)
        try? writer.fileHandleForWriting.close()
      }
    }
    let timer = DispatchSource.makeTimerSource(queue: .global())
    self.timer = timer
    timer.schedule(deadline: .now() + timeout)
    timer.setEventHandler { [weak self] in
      guard let self else { return }
      lock.lock()
      let shouldStop = !finished
      if shouldStop { timedOut = true }
      lock.unlock()
      if shouldStop { terminate() }
    }
    timer.resume()
  }
  func read(_ handle: FileHandle, isError: Bool) {
    let data = (try? handle.read(upToCount: 64 * 1024)) ?? Data()
    lock.lock()
    guard !finished else {
      lock.unlock()
      return
    }
    if data.isEmpty {
      if isError { errorEOF = true } else { outputEOF = true }
      handle.readabilityHandler = nil
      lock.unlock()
      finishIfReady()
      return
    }
    let room = max(0, budget - stdout.count - stderr.count)
    if isError { stderr.append(data.prefix(room)) } else { stdout.append(data.prefix(room)) }
    let exceeded = data.count > room
    if exceeded { truncated = true }
    lock.unlock()
    if exceeded { terminate() }
  }
  func terminate() {
    if process.isRunning { process.terminate() }
    DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [weak self] in
      guard let self, process.isRunning else { return }
      kill(process.processIdentifier, SIGKILL)
    }
  }
  func finishIfReady(force: Bool = false) {
    lock.lock()
    guard !finished, exited, force || (outputEOF && errorEOF), let completion else {
      lock.unlock()
      return
    }
    finished = true
    self.completion = nil
    if force && !(outputEOF && errorEOF) { truncated = true }
    let code =
      process.terminationReason == .uncaughtSignal
      ? 128 + process.terminationStatus : process.terminationStatus
    let result = CommandResult(
      stdout: String(decoding: stdout, as: UTF8.self),
      stderr: String(decoding: stderr, as: UTF8.self), exitCode: code,
      timedOut: timedOut, truncated: truncated,
      elapsedMs: Int((ProcessInfo.processInfo.systemUptime - started) * 1000))
    lock.unlock()
    timer?.cancel()
    timer = nil
    out.fileHandleForReading.readabilityHandler = nil
    err.fileHandleForReading.readabilityHandler = nil
    try? out.fileHandleForReading.close()
    try? err.fileHandleForReading.close()
    process.terminationHandler = nil
    completion.resume(returning: result)
  }
}
