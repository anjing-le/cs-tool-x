import CryptoKit
import Darwin
import Foundation
import Security

public struct ToolboxItem: Codable, Sendable, Identifiable {
  public let id: String, name: String, glyph: String
  public let modes: [String]
  public init(id: String, name: String, glyph: String, modes: [String]) { self.id = id; self.name = name; self.glyph = glyph; self.modes = modes }
}
public struct ToolboxRequest: Codable, Sendable {
  public var tool: String
  public var mode: String
  public var text: String
  public var other: String
  public var length: Int
  public var count: Int
  public var replacement: String
  public var file: String?
  public init(
    tool: String, mode: String = "", text: String = "", other: String = "", length: Int = 24,
    count: Int = 1, file: String? = nil, replacement: String = ""
  ) {
    self.tool = tool
    self.mode = mode
    self.text = text
    self.other = other
    self.length = length
    self.count = count
    self.file = file
    self.replacement = replacement
  }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    tool = try c.decode(String.self, forKey: .tool)
    mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? ""
    text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
    other = try c.decodeIfPresent(String.self, forKey: .other) ?? ""
    length = try c.decodeIfPresent(Int.self, forKey: .length) ?? 24
    count = try c.decodeIfPresent(Int.self, forKey: .count) ?? 1
    file = try c.decodeIfPresent(String.self, forKey: .file)
    replacement = try c.decodeIfPresent(String.self, forKey: .replacement) ?? ""
  }
}
public struct ToolboxResult: Codable, Sendable {
  public let output: String
  public let detail: String
}
public struct ToolboxError: LocalizedError, Sendable {
  public let message: String
  public var errorDescription: String? { message }
  public init(_ message: String) { self.message = message }
}
public enum Toolbox {
  public static let items: [ToolboxItem] = [
    .init(
      id: "case", name: "大小写转换", glyph: "Aa",
      modes: ["upper", "lower", "title", "camel", "snake", "kebab"]),
    .init(id: "lines", name: "重复行", glyph: "≡", modes: ["deduplicate", "count"]),
    .init(id: "srt", name: "字幕提取", glyph: "CC", modes: ["extract"]),
    .init(id: "diff", name: "文本对比", glyph: "±", modes: ["lines"]),
    .init(
      id: "timestamp", name: "时间戳", glyph: "◷",
      modes: ["seconds-to-date", "milliseconds-to-date", "date-to-seconds", "date-to-milliseconds"]),
    .init(
      id: "codec", name: "编码解码", glyph: "↔",
      modes: [
        "base64-encode", "base64-decode", "url-encode", "url-decode", "hex-encode", "hex-decode",
        "json-escape", "json-unescape",
      ]),
    .init(id: "json", name: "JSON 格式化", glyph: "{}", modes: ["pretty", "compact", "sorted"]),
    .init(id: "regex", name: "正则测试", glyph: ".*", modes: ["match", "replace"]),
    .init(id: "hash", name: "Hash 校验", glyph: "#", modes: ["sha256", "sha512", "sha1", "md5"]),
    .init(
      id: "random", name: "随机字符串", glyph: "⚿",
      modes: ["password", "alphanumeric", "digits", "uuid"]),
  ]
  public static let inputLimit = 48 * 1024
  public static let outputLimit = 384 * 1024
  public static func run(_ r: ToolboxRequest) throws -> ToolboxResult {
    guard let item = items.first(where: { $0.id == r.tool }) else { throw ToolboxError("未知工具") }
    let mode = r.mode.isEmpty ? item.modes[0] : r.mode
    guard item.modes.contains(mode), r.text.utf8.count <= inputLimit,
      r.other.utf8.count <= inputLimit, r.replacement.utf8.count <= inputLimit
    else { throw ToolboxError("模式无效或单项输入超过 48 KiB") }
    guard r.file == nil || r.tool == "hash" else { throw ToolboxError("只有 Hash 支持读取本地文件") }
    var output = ""
    var detail = ""
    switch r.tool {
    case "case":
      let words = r.text.replacingOccurrences(
        of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression
      ).components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
      switch mode {
      case "upper": output = r.text.uppercased()
      case "lower": output = r.text.lowercased()
      case "title": output = r.text.capitalized
      case "camel":
        output = words.enumerated().map {
          $0.offset == 0 ? $0.element.lowercased() : $0.element.lowercased().capitalized
        }.joined()
      default: output = words.map { $0.lowercased() }.joined(separator: mode == "snake" ? "_" : "-")
      }
    case "lines":
      var order: [String] = []
      var counts: [String: Int] = [:]
      for line in lines(r.text) {
        if counts[line] == nil { order.append(line) }
        counts[line, default: 0] += 1
      }
      output = order.map { mode == "count" ? "\(counts[$0]!)\t\($0)" : $0 }.joined(separator: "\n")
      detail = "\(order.count) 个不同的行 · 保留首次出现顺序"
    case "srt":
      let blocks = r.text.replacingOccurrences(of: "\u{feff}", with: "").replacingOccurrences(
        of: "\r\n", with: "\n"
      ).replacingOccurrences(of: #"\n[ \t]*\n+"#, with: "\n\n", options: .regularExpression)
        .trimmingCharacters(in: .newlines).components(separatedBy: "\n\n")
      var extracted: [String] = []
      for block in blocks {
        var rows = block.components(separatedBy: "\n")
        if rows.count >= 2,
          rows[0].trimmingCharacters(in: .whitespaces).allSatisfy({ $0.isNumber }),
          rows[1].contains("-->")
        {
          rows.removeFirst()
        }
        if let first = rows.first,
          first.range(of: #"^\s*\d{2}:\d{2}:\d{2}[,.]\d{3}\s*-->"#, options: .regularExpression)
            != nil
        {
          rows.removeFirst()
          extracted.append(rows.joined(separator: "\n"))
        }
      }
      guard !extracted.isEmpty else { throw ToolboxError("没有找到 SRT 时间轴") }
      output = extracted.joined(separator: "\n")
      detail = "\(extracted.count) 段字幕 · 保留原文字与标签"
    case "diff":
      output = try diff(r.text, r.other)
      detail = "按行比较 · − 原文 / + 新文 / 空格 未变"
    case "timestamp":
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      formatter.timeZone = TimeZone(secondsFromGMT: 0)
      if mode.hasSuffix("to-date") {
        guard let n = Double(r.text.trimmingCharacters(in: .whitespacesAndNewlines)), n.isFinite
        else { throw ToolboxError("请输入数字时间戳") }
        let seconds = mode.hasPrefix("milliseconds") ? n / 1000 : n
        guard abs(seconds) <= 253_402_300_799 else { throw ToolboxError("时间超出支持范围") }
        output = formatter.string(from: Date(timeIntervalSince1970: seconds))
      } else {
        let plain = ISO8601DateFormatter()
        guard let date = formatter.date(from: r.text) ?? plain.date(from: r.text) else {
          throw ToolboxError("请输入带时区的 ISO 8601 日期，例如 2026-11-21T08:00:00+08:00")
        }
        guard abs(date.timeIntervalSince1970) <= 253_402_300_799 else {
          throw ToolboxError("时间超出支持范围")
        }
        output = String(
          Int64(
            (date.timeIntervalSince1970 * (mode.hasSuffix("milliseconds") ? 1000 : 1)).rounded(
              .towardZero)))
      }
      detail = "日期输出为 UTC · 秒与毫秒显式区分"
    case "codec": output = try codec(mode, r.text)
    case "json":
      try checkJSONDepth(r.text)
      let object = try JSONSerialization.jsonObject(
        with: Data(r.text.utf8), options: [.fragmentsAllowed])
      let options: JSONSerialization.WritingOptions =
        mode == "compact"
        ? [.fragmentsAllowed]
        : (mode == "sorted"
          ? [.fragmentsAllowed, .prettyPrinted, .sortedKeys] : [.fragmentsAllowed, .prettyPrinted])
      output = String(
        decoding: try JSONSerialization.data(withJSONObject: object, options: options),
        as: UTF8.self)
    case "regex":
      guard r.other.utf8.count <= 4096 else { throw ToolboxError("正则表达式最多 4 KiB") }
      let expression = try NSRegularExpression(pattern: r.other)
      let range = NSRange(r.text.startIndex..., in: r.text)
      if mode == "replace" {
        guard r.replacement.utf8.count <= 1024, r.replacement.filter({ $0 == "$" }).count <= 32
        else { throw ToolboxError("替换模板最多 1 KiB、32 个捕获引用") }
        var cursor = 0
        var pieces: [String] = []
        var bytes = 0
        var seen = 0
        let source = r.text as NSString
        var exceeded = false
        expression.enumerateMatches(in: r.text, range: range) { match, _, stop in
          guard let match else { return }
          seen += 1
          let prefix = source.substring(
            with: NSRange(location: cursor, length: match.range.location - cursor))
          let replacement = expression.replacementString(
            for: match, in: r.text, offset: 0, template: r.replacement)
          bytes += prefix.utf8.count + replacement.utf8.count
          if seen > 500 || bytes > outputLimit {
            exceeded = true
            stop.pointee = true
            return
          }
          pieces.append(prefix)
          pieces.append(replacement)
          cursor = NSMaxRange(match.range)
        }
        guard !exceeded else { throw ToolboxError("替换超过 500 次或结果超过 384 KiB") }
        pieces.append(source.substring(from: cursor))
        output = pieces.joined()
        detail = "ICU 正则 · \(seen) 次替换 · $1 为捕获组"
        break
      }
      var matches: [String] = []
      var limited = false
      var matchBytes = 0
      expression.enumerateMatches(in: r.text, range: range) { match, _, stop in
        guard let match else { return }
        if matches.count >= 500 {
          limited = true
          stop.pointee = true
          return
        }
        var parts: [String] = ["[\(match.range.location):\(match.range.length)]"]
        for i in 0..<min(match.numberOfRanges, 33) {
          if let range = Range(match.range(at: i), in: r.text) {
            parts.append("\(i): " + String(r.text[range]))
          }
        }
        let row = parts.joined(separator: "\n")
        matchBytes += row.utf8.count
        if matchBytes > outputLimit {
          limited = true
          stop.pointee = true
          return
        }
        matches.append(row)
      }
      output = matches.joined(separator: "\n\n")
      detail = "ICU 正则 · UTF-16 位置 · \(matches.count) 个匹配" + (limited ? " · 已达 500 上限" : "")
    case "hash":
      let digest = try hash(r, mode: mode)
      output = digest
      if !r.other.isEmpty {
        let expected = r.other.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard expected.count == digest.count, expected.allSatisfy({ $0.isHexDigit && $0.isASCII })
        else { throw ToolboxError("校验值长度或格式不正确") }
        detail = digest == expected ? "校验一致" : "校验不一致"
      } else {
        detail = r.file == nil ? "UTF-8 文本" : "本地文件 · 流式读取"
      }
      if mode == "md5" || mode == "sha1" { detail += " · 仅作旧式校验，不用于安全用途" }
    case "random":
      guard (1...256).contains(r.length), (1...100).contains(r.count),
        mode != "password" || r.length >= 4
      else { throw ToolboxError("长度 1–256，数量 1–100；密码至少 4 位") }
      var rows: [String] = []
      let groups = [
        Array("abcdefghijkmnopqrstuvwxyz"), Array("ABCDEFGHJKLMNPQRSTUVWXYZ"), Array("23456789"),
        Array("!@#$%&*+-=?_"),
      ]
      for _ in 0..<r.count {
        if mode == "uuid" {
          rows.append(UUID().uuidString.lowercased())
          continue
        }
        let alphabet =
          mode == "digits"
          ? Array("0123456789")
          : (mode == "password"
            ? groups.flatMap { $0 }
            : Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"))
        var chars: [Character] = []
        if mode == "password" {
          for group in groups { chars.append(group[try secureIndex(group.count)]) }
        }
        while chars.count < r.length { chars.append(alphabet[try secureIndex(alphabet.count)]) }
        if chars.count > 1 {
          for i in stride(from: chars.count - 1, through: 1, by: -1) {
            chars.swapAt(i, try secureIndex(i + 1))
          }
        }
        rows.append(String(chars))
      }
      output = rows.joined(separator: "\n")
      detail = "系统安全随机源 · 不自动复制或保存"
    default: throw ToolboxError("未知工具")
    }
    guard output.utf8.count <= outputLimit else { throw ToolboxError("结果超过 384 KiB，请缩小输入") }
    return .init(output: output, detail: detail)
  }
  private static func lines(_ text: String) -> [String] {
    text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
      .components(separatedBy: "\n")
  }
  private static func secureIndex(_ count: Int) throws -> Int {
    let limit = 256 - 256 % count
    while true {
      var byte: UInt8 = 0
      guard SecRandomCopyBytes(kSecRandomDefault, 1, &byte) == errSecSuccess else {
        throw ToolboxError("安全随机源不可用")
      }
      if Int(byte) < limit { return Int(byte) % count }
    }
  }
  private static func checkJSONDepth(_ text: String) throws {
    var depth = 0
    var quoted = false
    var escaped = false
    for c in text.utf8 {
      if quoted {
        if escaped {
          escaped = false
        } else if c == 92 {
          escaped = true
        } else if c == 34 {
          quoted = false
        }
      } else if c == 34 {
        quoted = true
      } else if c == 91 || c == 123 {
        depth += 1
        if depth > 128 { throw ToolboxError("JSON 嵌套最多 128 层") }
      } else if c == 93 || c == 125 {
        depth -= 1
      }
    }
  }
  private static func codec(_ mode: String, _ text: String) throws -> String {
    switch mode {
    case "base64-encode": return Data(text.utf8).base64EncodedString()
    case "url-encode":
      return text.addingPercentEncoding(
        withAllowedCharacters: CharacterSet(
          charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"))!
    case "url-decode":
      guard let v = text.removingPercentEncoding else { throw ToolboxError("无效 URL 编码") }
      return v
    case "hex-encode": return Data(text.utf8).map { String(format: "%02x", $0) }.joined()
    case "json-escape":
      return String(
        decoding: try JSONSerialization.data(withJSONObject: text, options: [.fragmentsAllowed]),
        as: UTF8.self)
    case "json-unescape":
      guard
        let value = try JSONSerialization.jsonObject(
          with: Data(text.utf8), options: [.fragmentsAllowed]) as? String
      else { throw ToolboxError("请输入 JSON 字符串，含双引号") }
      return value
    default:
      let data: Data?
      if mode == "base64-decode" {
        data = Data(base64Encoded: text)
      } else {
        let chars = Array(text.utf8)
        guard chars.count % 2 == 0 else { throw ToolboxError("十六进制长度须为偶数") }
        var bytes = Data()
        for i in stride(from: 0, to: chars.count, by: 2) {
          guard let byte = UInt8(String(decoding: chars[i...i + 1], as: UTF8.self), radix: 16)
          else { throw ToolboxError("无效十六进制") }
          bytes.append(byte)
        }
        data = bytes
      }
      guard let data, let result = String(data: data, encoding: .utf8) else {
        throw ToolboxError("无效编码或解码结果不是 UTF-8 文本")
      }
      return result
    }
  }
  private static func diff(_ left: String, _ right: String) throws -> String {
    let a = lines(left)
    let b = lines(right)
    guard a.count <= 1000, b.count <= 1000 else { throw ToolboxError("文本对比每侧最多 1000 行") }
    let stride = b.count + 1
    var lengths = [UInt16](repeating: 0, count: (a.count + 1) * stride)
    for i in a.indices.reversed() {
      for j in b.indices.reversed() {
        lengths[i * stride + j] =
          a[i] == b[j]
          ? lengths[(i + 1) * stride + j + 1] + 1
          : max(lengths[(i + 1) * stride + j], lengths[i * stride + j + 1])
      }
    }
    var i = 0
    var j = 0
    var result: [String] = []
    while i < a.count || j < b.count {
      if i < a.count, j < b.count, a[i] == b[j] {
        result.append("  " + a[i])
        i += 1
        j += 1
      } else if j < b.count,
        i == a.count || lengths[i * stride + j + 1] > lengths[(i + 1) * stride + j]
      {
        result.append("+ " + b[j])
        j += 1
      } else {
        result.append("− " + a[i])
        i += 1
      }
    }
    return result.joined(separator: "\n")
  }
  private static func hash(_ r: ToolboxRequest, mode: String) throws -> String {
    var h256 = SHA256()
    var h512 = SHA512()
    var h1 = Insecure.SHA1()
    var md5 = Insecure.MD5()
    func update(_ data: Data) {
      switch mode {
      case "sha256": h256.update(data: data)
      case "sha512": h512.update(data: data)
      case "sha1": h1.update(data: data)
      default: md5.update(data: data)
      }
    }
    if let path = r.file {
      let url = URL(fileURLWithPath: path)
      let fd = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
      guard fd >= 0 else { throw ToolboxError("无法读取本地文件") }
      let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
      defer { try? handle.close() }
      var metadata = stat()
      guard fstat(fd, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG,
        metadata.st_size <= 8 * 1024 * 1024 * 1024
      else { throw ToolboxError("请选择不超过 8 GiB 的普通文件") }
      var read = 0
      while let chunk = try handle.read(upToCount: 256 * 1024), !chunk.isEmpty {
        read += chunk.count
        guard read <= 8 * 1024 * 1024 * 1024 else { throw ToolboxError("文件超过 8 GiB") }
        update(chunk)
      }
    } else {
      update(Data(r.text.utf8))
    }
    let bytes: [UInt8]
    switch mode {
    case "sha256": bytes = Array(h256.finalize())
    case "sha512": bytes = Array(h512.finalize())
    case "sha1": bytes = Array(h1.finalize())
    default: bytes = Array(md5.finalize())
    }
    return bytes.map { String(format: "%02x", $0) }.joined()
  }
}
