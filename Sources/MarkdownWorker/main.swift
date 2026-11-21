import Darwin
import Foundation
import ToolCore
import cmark_gfm
import cmark_gfm_extensions

// One bounded process: explicit readonly file import or stdin Markdown; no writes, networking or scripts.
let maximum = 4 * 1024 * 1024
func reject(_ message: String) -> Never {
  try? FileHandle.standardError.write(contentsOf: Data(message.utf8))
  exit(2)
}
if CommandLine.arguments.count == 3,
  ["--read-text", "--read-markdown"].contains(CommandLine.arguments[1])
{
  do {
    let text = try TextWorkbench.read(
      URL(fileURLWithPath: CommandLine.arguments[2]),
      limit: CommandLine.arguments[1] == "--read-markdown"
        ? TextWorkbench.previewBytes : TextWorkbench.editorBytes)
    try FileHandle.standardOutput.write(contentsOf: Data(text.utf8))
    exit(0)
  } catch { reject(error.localizedDescription) }
}
guard CommandLine.arguments.count == 1 else { reject("Invalid worker arguments") }
do {
  var data = Data()
  while let chunk = try FileHandle.standardInput.read(
    upToCount: min(64 * 1024, maximum + 1 - data.count)), !chunk.isEmpty
  {
    data.append(chunk)
    if data.count > maximum { reject("Markdown 超过 4 MiB") }
  }
  guard String(data: data, encoding: .utf8) != nil, !data.contains(0) else {
    reject("Markdown 必须是 UTF-8 文本")
  }
  cmark_gfm_core_extensions_ensure_registered()
  guard let parser = cmark_parser_new(CMARK_OPT_VALIDATE_UTF8) else { reject("无法创建 Markdown 解析器") }
  defer { cmark_parser_free(parser) }
  for name in ["table", "strikethrough", "tasklist", "autolink"] {
    if let extensionNode = cmark_find_syntax_extension(name) {
      cmark_parser_attach_syntax_extension(parser, extensionNode)
    }
  }
  data.withUnsafeBytes { bytes in
    if let base = bytes.baseAddress {
      cmark_parser_feed(parser, base.assumingMemoryBound(to: CChar.self), bytes.count)
    }
  }
  guard let document = cmark_parser_finish(parser) else { reject("Markdown 解析失败") }
  defer { cmark_node_free(document) }
  guard let iterator = cmark_iter_new(document) else { reject("Markdown 解析失败") }
  defer { cmark_iter_free(iterator) }
  var count = 0
  while true {
    let event = cmark_iter_next(iterator)
    if event == CMARK_EVENT_DONE { break }
    if event != CMARK_EVENT_ENTER { continue }
    count += 1
    var parent = cmark_iter_get_node(iterator)
    var depth = 0
    while let node = parent {
      depth += 1
      if depth > 256 { reject("Markdown 嵌套超过 256 层；正文保留") }
      parent = cmark_node_parent(node)
    }
    if count > 30_000 { reject("Markdown 结构超过 30000 节点；正文保留") }
  }
  // Safe mode is the upstream default: raw HTML and unsafe link schemes are omitted.
  guard
    let html = cmark_render_html(
      document, CMARK_OPT_DEFAULT, cmark_parser_get_syntax_extensions(parser))
  else { reject("Markdown 渲染失败") }
  defer { free(html) }
  let length = strnlen(html, 8 * 1024 * 1024 + 1)
  guard length <= 8 * 1024 * 1024 else { reject("Markdown 结果超过 8 MiB") }
  try FileHandle.standardOutput.write(contentsOf: Data(bytes: html, count: length))
} catch { reject("Markdown 工作进程读取或输出失败") }
