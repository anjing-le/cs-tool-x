import Darwin
import Foundation

/// Text never goes into configuration, temporary files, or a recovery store.
public enum TextWorkbench {
  public static let editorBytes = 32 * 1024 * 1024
  public static let lineBytes = 128 * 1024
  public static let previewBytes = 4 * 1024 * 1024
  public static let previewOutputBytes = 8 * 1024 * 1024
  public static func read(_ url: URL, limit: Int = editorBytes) throws -> String {
    guard limit > 0, limit <= editorBytes else { throw ToolboxError("无效文本预算") }
    let fd = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
    guard fd >= 0 else { throw ToolboxError("无法读取文本文件") }
    let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    defer { try? handle.close() }
    var metadata = stat()
    guard fstat(fd, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG else {
      throw ToolboxError("只能导入普通文本文件")
    }
    guard metadata.st_size <= limit else {
      throw ToolboxError("文本超过 \(limit / 1024 / 1024) MiB 上限")
    }
    var data = Data()
    var currentLine = 0
    while let chunk = try handle.read(upToCount: min(256 * 1024, limit + 1 - data.count)),
      !chunk.isEmpty
    {
      try Task.checkCancellation()
      for byte in chunk {
        if byte == 10 || byte == 13 {
          currentLine = 0
        } else {
          currentLine += 1
          if currentLine > lineBytes { throw ToolboxError("单行超过 128 KiB；为保持编辑响应，本次未导入，原文保留") }
        }
      }
      data.append(chunk)
      guard data.count <= limit else { throw ToolboxError("文本超过大小上限") }
    }
    if data.starts(with: [0xef, 0xbb, 0xbf]) { data.removeFirst(3) }
    guard !data.contains(0), let text = String(data: data, encoding: .utf8) else {
      throw ToolboxError("仅支持 UTF-8 文本，不导入二进制或 UTF-16 文件")
    }
    return text
  }
  public static func acceptsLines(_ text: String, prefix: Int = 0, suffix: Int = 0) -> Bool {
    var current = prefix
    for byte in text.utf8 {
      if byte == 10 || byte == 13 {
        current = 0
      } else {
        current += 1
        if current > lineBytes { return false }
      }
    }
    return current + suffix <= lineBytes
  }
  public static func importText(_ url: URL, executable: URL, limit: Int = editorBytes) async throws
    -> String
  {
    guard limit == editorBytes || limit == previewBytes else { throw ToolboxError("无效文本预算") }
    let response = try await BoundedProcess.run(
      executable: executable,
      arguments: [limit == previewBytes ? "--read-markdown" : "--read-text", url.path], timeout: 15,
      maxOutputBytes: limit)
    guard !response.timedOut else { throw ToolboxError("读取超时，已终止读取进程；原文保留") }
    guard !response.truncated else { throw ToolboxError("文本超过 32 MiB；原文保留") }
    guard response.exitCode == 0 else {
      throw ToolboxError(response.stderr.isEmpty ? "无法导入文本" : response.stderr)
    }
    return response.stdout
  }
  public static func preview(_ text: String, executable: URL) async throws -> String {
    guard text.utf8.count <= previewBytes else {
      throw ToolboxError("首版完整 Markdown 预览上限为 4 MiB；正文仍可继续编辑，不截断内容")
    }
    let response = try await BoundedProcess.run(
      executable: executable, arguments: [], input: Data(text.utf8), timeout: 5,
      maxOutputBytes: previewOutputBytes, maxInputBytes: previewBytes)
    guard !response.timedOut else { throw ToolboxError("Markdown 解析超时，已终止计算；正文保留") }
    guard !response.truncated else { throw ToolboxError("Markdown 结果超过 8 MiB；正文保留") }
    guard response.exitCode == 0 else {
      throw ToolboxError(
        response.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ? "Markdown 解析未完成" : response.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return response.stdout
  }
  public static func page(_ body: String) -> String {
    """
    <!doctype html><html lang="zh"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width">
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src 'none'; media-src 'none'; font-src 'none'; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">
    <style>
    :root{color-scheme:light}*{box-sizing:border-box}html{background:#fcfcf9;color:#3d423d}
    body{margin:0;padding:32px max(24px,7.5vw) 80px;font:19px/1.45 'HanziPen SC','Kaiti SC',system-ui;overflow-wrap:anywhere}
    h1,h2,h3,h4,h5,h6{line-height:1.35;margin:1.2em 0 .55em;font-weight:600}h1{font-size:1.9em}h2{font-size:1.5em}h3{font-size:1.2em}
    p,ul,ol,blockquote,pre,table{margin:.7em 0}li>p{margin:.2em 0}a{color:#5e7d64;text-decoration-thickness:1px;text-underline-offset:3px}
    blockquote{border-left:2px solid #a7b39d;margin-left:0;padding:.3em 1em;background:#eff1e9;color:#73786b}
    code,pre{font-family:ui-monospace,Menlo,monospace;font-size:.85em}code{background:#efefe7;padding:.1em .3em;border-radius:4px}
    pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#f0f0e9;border:1px solid #e3e4d9;border-radius:12px;padding:16px}pre code{background:none;padding:0}
    table{border-collapse:collapse;display:block;overflow:auto;max-width:100%}td,th{padding:8px 12px;border-bottom:1px solid #d9ddcf;text-align:left}
    th{color:#5e7d64}hr{border:0;border-top:1px solid #d9ddcf;margin:1.5em 0}img{display:none}input{accent-color:#5e7d64}
    ::selection{background:#dde2d6} 
    </style></head><body>\(body)</body></html>
    """
  }
}
