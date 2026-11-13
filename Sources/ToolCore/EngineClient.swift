import Foundation

/// Lazy, private stdio transport. No listener port, shell interpolation or credential files.
public actor EngineClient {
  private var process: Process?
  private var input: FileHandle?
  private var output: FileHandle?
  private var buffer = Data()
  private var serial: UInt64 = 0
  private var pending: [UInt64: CheckedContinuation<JSONValue, Error>] = [:]
  private var deadlines: [UInt64: Task<Void, Never>] = [:]
  private var generation = 0
  private var readerTask: Task<Void, Never>?
  private let executable: URL
  public init(executable: URL) { self.executable = executable }
  private func launch() throws {
    guard process == nil else { return }
    guard FileManager.default.isExecutableFile(atPath: executable.path) else {
      throw ToolError.message("数据引擎缺失，请使用完整应用包。")
    }
    let child = Process()
    let incoming = Pipe()
    let outgoing = Pipe()
    child.executableURL = executable
    child.standardInput = incoming
    child.standardOutput = outgoing
    child.standardError = FileHandle.nullDevice
    generation += 1
    let current = generation
    let stream = AsyncStream<Data>(bufferingPolicy: .bufferingOldest(256)) { continuation in
      outgoing.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        if case .dropped = continuation.yield(data) {
          handle.readabilityHandler = nil
          continuation.finish()
        }
        if data.isEmpty { continuation.finish() }
      }
    }
    readerTask = Task { [weak self] in
      for await data in stream {
        guard !Task.isCancelled else { break }
        await self?.receive(data, generation: current)
      }
      await self?.terminated(generation: current)
    }
    child.terminationHandler = { [weak self] _ in
      Task { await self?.terminated(generation: current) }
    }
    do { try child.run() } catch {
      outgoing.fileHandleForReading.readabilityHandler = nil
      readerTask?.cancel()
      readerTask = nil
      throw error
    }
    process = child
    input = incoming.fileHandleForWriting
    output = outgoing.fileHandleForReading
  }
  public func call(_ method: String, params: JSONValue = .object([:])) async throws -> JSONValue {
    guard pending.count < 8 else { throw ToolError.message("任务较多，请等待当前操作完成。") }
    try launch()
    serial += 1
    let id = serial
    let message = JSONValue.object([
      "id": .number(Decimal(id)), "method": .string(method), "params": params,
    ])
    var bytes = try JSONEncoder().encode(message)
    guard bytes.count < 256 * 1024 else { throw ToolError.message("请求超过 256 KiB，请缩小内容。") }
    bytes.append(10)
    return try await withCheckedThrowingContinuation { continuation in
      pending[id] = continuation
      deadlines[id] = Task { [weak self] in
        do { try await Task.sleep(nanoseconds: 25_000_000_000) } catch { return }
        await self?.expire(id)
      }
      do { try input?.write(contentsOf: bytes) } catch {
        finish(id, result: .failure(ToolError.message("无法写入数据引擎。")))
      }
    }
  }
  private func receive(_ data: Data, generation: Int) {
    guard generation == self.generation else { return }
    guard !data.isEmpty else {
      stop()
      return
    }
    guard buffer.count + data.count <= 17 * 1024 * 1024 else {
      stop()
      return
    }
    buffer.append(data)
    while let index = buffer.firstIndex(of: 10) {
      let frame = Data(buffer[..<index])
      buffer.removeSubrange(...index)
      do {
        let reply = try JSONDecoder().decode(JSONValue.self, from: frame)
        guard let idText = reply["id"]?.text, let id = UInt64(idText) else {
          throw ToolError.message("响应协议无效。")
        }
        if reply["ok"] == .bool(true) {
          finish(id, result: .success(reply["result"] ?? .null))
        } else {
          finish(id, result: .failure(ToolError.message(reply["error"]?.text ?? "数据操作失败。")))
        }
      } catch {
        stop()
        return
      }
    }
  }
  private func finish(_ id: UInt64, result: Result<JSONValue, Error>) {
    deadlines.removeValue(forKey: id)?.cancel()
    pending.removeValue(forKey: id)?.resume(with: result)
  }
  private func expire(_ id: UInt64) {
    finish(id, result: .failure(ToolError.message("客户端等待超时；服务端执行状态尚未确认。")))
  }
  private func terminated(generation: Int) { if generation == self.generation { stop() } }
  public func stop() {
    generation += 1
    readerTask?.cancel()
    readerTask = nil
    output?.readabilityHandler = nil
    try? input?.close()
    try? output?.close()
    if process?.isRunning == true { process?.terminate() }
    process = nil
    input = nil
    output = nil
    buffer.removeAll(keepingCapacity: false)
    for id in Array(pending.keys) {
      finish(id, result: .failure(ToolError.message("数据引擎已停止，请重新连接。")))
    }
  }
  public func connect(profile: ConnectionProfile, password: String, apiKey: String) async throws
    -> (String, Int)
  {
    try profile.validate()
    let greeting = try await call("hello")
    guard greeting["protocol"]?.text == "1" else {
      stop()
      throw ToolError.message("数据引擎协议不兼容，请使用完整更新包。")
    }
    let reply = try await call(
      "connect",
      params: .object([
        "kind": .string(profile.kind.rawValue), "host": .string(profile.host),
        "port": .number(Decimal(profile.port)),
        "username": .string(profile.username), "password": .string(password),
        "database": .string(profile.database),
        "tls": .bool(profile.tls), "endpoint": .string(profile.endpoint), "apiKey": .string(apiKey),
      ]))
    guard let id = reply["id"]?.text, let elapsedText = reply["elapsedMs"]?.text,
      let elapsed = Int(elapsedText)
    else { throw ToolError.message("连接响应无效。") }
    return (id, elapsed)
  }
  public func run(
    id: String, action: String, text: String, target: String = "", cursor: String = "0"
  ) async throws -> QueryOutput {
    let reply = try await call(
      "run",
      params: .object([
        "id": .string(id), "action": .string(action), "text": .string(text),
        "target": .string(target), "cursor": .string(cursor),
      ]))
    return try JSONDecoder().decode(QueryOutput.self, from: JSONEncoder().encode(reply))
  }
  public func disconnect(id: String) async throws {
    _ = try await call("disconnect", params: .object(["id": .string(id)]))
  }
}
