import AppKit
import ImageIO
import SwiftUI
import ToolCore

/// A finite, shared set of decoded entrance images. Resource I/O and decoding stay off the UI thread.
@MainActor final class LauncherArtwork: ObservableObject {
  @Published private(set) var images: [String: CGImage] = [:]
  private let directory: URL?
  private var loading: Task<[String: CGImage], Never>?
  init(directory: URL? = Bundle.main.resourceURL?.appendingPathComponent("Entrances")) {
    self.directory = directory
  }
  func load() async {
    guard images.isEmpty else { return }
    if loading == nil {
      let directory = directory
      loading = Task.detached(priority: .userInitiated) {
        var result: [String: CGImage] = [:]
        for key in ["shell", "data", "git", "text", "toolbox"] {
          guard let url = directory?.appendingPathComponent(key + ".png"),
            let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 8 * 1024 * 1024,
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int,
            width > 0, height > 0, width <= 4096, height <= 4096,
            let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
              kCGImageSourceCreateThumbnailFromImageAlways: true,
              kCGImageSourceCreateThumbnailWithTransform: true,
              kCGImageSourceThumbnailMaxPixelSize: 1536,
              kCGImageSourceShouldCacheImmediately: true,
            ] as CFDictionary)
          else { continue }
          result[key] = image
        }
        return result
      }
    }
    // Immutable bundled assets can finish loading after navigation; the home view keeps this cache.
    images = await loading!.value
  }
}

@MainActor struct LauncherView: View {
  let enter: (ToolModule) -> Void
  @StateObject private var artwork: LauncherArtwork
  init(artwork: LauncherArtwork? = nil, enter: @escaping (ToolModule) -> Void) {
    _artwork = StateObject(wrappedValue: artwork ?? LauncherArtwork())
    self.enter = enter
  }
  var body: some View {
    GeometryReader { geometry in
      let upperHeight: CGFloat = min(geometry.size.height * 0.6, geometry.size.width / 4 / 0.72)
      let upperSize = CGSize(width: geometry.size.width, height: upperHeight)
      VStack(spacing: 0) {
        HStack(spacing: 0) {
          entrance("shell", name: "Shell", label: "Shell：终端与文件传输", color: Color(red: 0.96, green: 0.82, blue: 0.55), module: .terminal, size: upperSize)
          entrance("data", name: "数据", label: "数据：MySQL、PostgreSQL、Redis 与 Elasticsearch", color: Color(red: 0.75, green: 0.83, blue: 0.86), module: .data, size: upperSize)
          entrance("git", name: "Git", label: "Git：仓库、分支与提交历史", color: Color(red: 0.75, green: 0.80, blue: 0.61), module: .git, size: upperSize)
          entrance("text", name: "临时文本", label: "临时文本：写作与 Markdown 预览", color: Color(red: 0.91, green: 0.81, blue: 0.75), module: .text, size: upperSize)
        }
        IllustratedEntrance(name: "百宝箱", label: "百宝箱：离线小工具", image: artwork.images["toolbox"], color: Color(red: 0.90, green: 0.92, blue: 0.86)) { enter(.utilities) }
          .frame(width: geometry.size.width, height: max(0, geometry.size.height - upperHeight)).clipped()
      }

    }
    .background(Color(nsColor: Theme.paper))
    .preferredColorScheme(.light)
    .ignoresSafeArea()
    .task { await artwork.load() }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("工具入口")
  }
  private func entrance(_ key: String, name: String, label: String, color: Color, module: ToolModule, size: CGSize) -> some View {
    IllustratedEntrance(name: name, label: label, image: artwork.images[key], color: color) {
      enter(module)
    }.frame(width: size.width / 4, height: size.height).clipped()
  }
}

@MainActor private struct IllustratedEntrance: View {
  let name: String, label: String
  let image: CGImage?
  let color: Color
  let action: () -> Void
  @State private var hovered = false
  @FocusState private var focused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    Button {
      hovered = false
      action()
    } label: {
      GeometryReader { geometry in
        ZStack(alignment: .bottomLeading) {
          color
          if let image {
            Image(decorative: image, scale: 1)
              .resizable().scaledToFill()
              .frame(width: geometry.size.width, height: geometry.size.height)
          }
          Color.black.opacity(hovered || focused ? 0.045 : 0)
          if hovered || focused || image == nil {
            Text(name)
              .font(Font(Theme.font(20, weight: .medium)))
              .foregroundStyle(Color(nsColor: Theme.ink))
              .padding(.leading, 26).padding(.bottom, 30)
              .accessibilityHidden(true)
          }
          if focused {
            Rectangle().fill(Color(nsColor: Theme.sage)).frame(height: 3).accessibilityHidden(true)
          }
        }.frame(width: geometry.size.width, height: geometry.size.height)
          .clipped().contentShape(Rectangle())
      }
    }
    .buttonStyle(.plain).writingCursor(.clickable).focused($focused)
    .onHover { hovered = $0 }
    .onDisappear { hovered = false }
    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hovered)
    .accessibilityLabel(label)
    .accessibilityHint("打开工作区")
  }
}
