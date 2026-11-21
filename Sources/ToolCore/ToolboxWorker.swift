import Foundation

public struct ToolboxReply: Codable, Sendable {
  public let result: ToolboxResult?
  public let error: String?
  public init(result: ToolboxResult? = nil, error: String? = nil) {
    self.result = result
    self.error = error
  }
}
public enum ToolboxWorker {
  public static func run(_ request: ToolboxRequest, executable: URL) async throws -> ToolboxResult {
    let input = try JSONEncoder().encode(request)
    guard input.count <= 128 * 1024 else { throw ToolboxError("请求超过 128 KiB") }
    let response = try await BoundedProcess.run(
      executable: executable, arguments: ["--toolbox-worker"], input: input,
      timeout: request.tool == "hash" && request.file != nil ? 30 : 4,
      maxOutputBytes: 2 * 1024 * 1024)
    guard !response.timedOut else { throw ToolboxError("计算超时，已终止本地计算进程") }
    guard !response.truncated else { throw ToolboxError("结果超限，已终止本地计算进程") }
    guard response.exitCode == 0,
      let reply = try? JSONDecoder().decode(ToolboxReply.self, from: Data(response.stdout.utf8))
    else { throw ToolboxError("本地计算进程未正常完成") }
    if let error = reply.error { throw ToolboxError(error) }
    guard let result = reply.result else { throw ToolboxError("本地计算结果缺失") }
    return result
  }
  /// Internal CLI entry only: one bounded request and one reply, never configuration or network access.
  public static func serve() {
    let reply: ToolboxReply
    do {
      let data = try FileHandle.standardInput.read(upToCount: 128 * 1024 + 1) ?? Data()
      // Pipe reads may be short. Read to EOF, retaining the same fixed budget.
      var bytes = data
      while bytes.count <= 128 * 1024 {
        let chunk =
          try FileHandle.standardInput.read(upToCount: min(8192, 128 * 1024 + 1 - bytes.count))
          ?? Data()
        if chunk.isEmpty { break }
        bytes.append(chunk)
      }
      guard bytes.count <= 128 * 1024 else { throw ToolboxError("请求超过 128 KiB") }
      let request = try JSONDecoder().decode(ToolboxRequest.self, from: bytes)
      reply = .init(result: try Toolbox.run(request))
    } catch { reply = .init(error: error.localizedDescription) }
    if let data = try? JSONEncoder().encode(reply) {
      try? FileHandle.standardOutput.write(contentsOf: data)
    }
  }
}
