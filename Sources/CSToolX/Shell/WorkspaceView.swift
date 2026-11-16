import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PaperAction<Content: View>: View {
  let label: String
  let action: () -> Void
  var doubleClick = false
  var onSelect: (() -> Void)? = nil
  var onDisclosure: ((Bool) -> Void)? = nil
  var onDoubleClick: (() -> Void)? = nil
  var onFocusChange: ((Bool) -> Void)? = nil
  @ViewBuilder let content: () -> Content
  @State private var hovered = false
  var body: some View {
    content().allowsHitTesting(false)
      .background(hovered ? Ink.main.opacity(0.055) : .clear, in: RoundedRectangle(cornerRadius: 8))
      .overlay(
        ActionTarget(label: label, doubleClick: doubleClick, onSelect: onSelect, onDisclosure: onDisclosure, onDoubleClick: onDoubleClick, onFocusChange: onFocusChange, action: action)
      )
      .onHover { hovered = $0 }
  }
}
struct IconAction: View {
  let icon: String
  let label: String
  var selected = false
  var visible = true
  let action: () -> Void
  @State private var focused = false
  var body: some View {
    PaperAction(label: label, action: action, onFocusChange: { focused = $0 }) {
      Image(systemName: icon).font(.system(size: 14, weight: .regular))
        .foregroundStyle(selected ? Ink.sage : Ink.muted)
        .frame(width: 30, height: 30)
        .background(
          selected ? Ink.pale.opacity(0.75) : .clear, in: RoundedRectangle(cornerRadius: 7))
        .opacity(visible || focused || selected ? 1 : 0)
    }
  }
}
struct WorkspaceView: View {
  @ObservedObject var model: Workspace
  var openFiles: () -> Void = {}
  @AppStorage("sidebar.visible") private var sidebar = true
  @AppStorage("files.visible") private var files = true
  @AppStorage("sidebar.width") private var sidebarWidth = 206.0
  @AppStorage("files.width") private var fileWidth = 252.0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var tabsHovered = false
  var body: some View {
    VStack(spacing: 0) {
      topBar
      if model.settings {
        settings
      } else {
        GeometryReader { geometry in
          let side = min(sidebarWidth, max(170, geometry.size.width * 0.24))
          let right = min(fileWidth, max(200, geometry.size.width * 0.28))
          ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
              if sidebar {
                serverSidebar.frame(width: side)
                divider(size: side, fraction: 0.5) { sidebarWidth = min(280, max(170, $0)) }
              }
              center.frame(minWidth: 280, maxWidth: .infinity)
              if files && model.active != nil {
                divider(size: geometry.size.width - right, fraction: 0.5) {
                  fileWidth = min(340, max(200, geometry.size.width - $0))
                }
                fileSidebar.frame(width: right)
              }
            }
            if let panel = model.sidebarPanel {
              Color.black.opacity(0.035).contentShape(Rectangle())
                .onTapGesture { model.sidebarPanel = nil }
                .accessibilityLabel("关闭侧栏面板")
              SidebarPanelView(model: model, panel: panel)
                .id(String(describing: panel))
                .padding(.leading, sidebar ? side + 21 : 24)
                .padding(.top, 10)
            }
          }
        }
      }
    }
    .padding(.top, 4)
    .foregroundStyle(Ink.main)
    .font(Font(Theme.font(14)))
    .preferredColorScheme(.light).tint(Ink.sage)
    .overlay(alignment: .bottom) {
      if let notice = model.notice {
        Text(notice).font(.system(size: 12)).padding(.horizontal, 16).padding(.vertical, 10)
          .background(Ink.pale, in: Capsule())
          .overlay(Capsule().stroke(Ink.line)).padding(.bottom, 38).allowsHitTesting(false)
      }
    }
    .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: model.settings)
  }
  private var topBar: some View {
    HStack(spacing: 9) {
      Spacer()
      IconAction(icon: "sidebar.left", label: "显示或隐藏服务器栏", selected: sidebar) {
        model.sidebarPanel = nil
        sidebar.toggle()
      }
      IconAction(icon: "rectangle.split.2x1", label: "左右分屏") {
        model.active?.split(vertical: false)
      }
      IconAction(icon: "rectangle.split.1x2", label: "上下分屏") { model.active?.split(vertical: true) }
      Color.clear.frame(width: 1, height: 14).overlay(Ink.line)
      IconAction(icon: "sidebar.right", label: "显示或隐藏文件栏", selected: files) { files.toggle() }
      IconAction(icon: "gearshape", label: "设置") { model.settings.toggle() }
    }.padding(.horizontal, 18).padding(.bottom, 4)
  }
  private var serverSidebar: some View {
    ServerSidebar(model: model)
  }
  private var center: some View {
    VStack(spacing: 0) {
      ScrollView(.horizontal) {
        HStack(spacing: 5) {
          ForEach(Array(model.sessions.enumerated()), id: \.element.id) { index, session in
            SessionTab(
              session: session, index: index, selected: model.selected == session.id,
              select: { model.select(session.id) }, close: { model.close(session.id) }
            )
            .onDrag { NSItemProvider(object: session.id.uuidString as NSString) }
            .onDrop(of: [.text], isTargeted: nil) { providers in
              guard let provider = providers.first else { return false }
              _ = provider.loadObject(ofClass: String.self) { value, _ in
                guard let value, let id = UUID(uuidString: value) else { return }
                Task { @MainActor in
                  guard let from = model.sessions.firstIndex(where: { $0.id == id }),
                    let to = model.sessions.firstIndex(where: { $0.id == session.id })
                  else { return }
                  let item = model.sessions.remove(at: from)
                  model.sessions.insert(item, at: min(to, model.sessions.count))
                }
              }
              return true
            }
          }
          IconAction(icon: "plus", label: "新建会话", visible: tabsHovered) { model.newTab() }
        }.padding(.horizontal, 7).padding(.vertical, 7)
      }.scrollIndicators(.hidden).frame(height: 48).onHover { tabsHovered = $0 }
      if let session = model.active {
        SessionView(session: session).id(session.id)
          .padding(.horizontal, 8).padding(.bottom, 12)
      } else {
        VStack(spacing: 15) {
          Image(systemName: "terminal").font(.system(size: 34, weight: .ultraLight))
            .foregroundStyle(Ink.sage)
          PaperAction(label: "打开本地终端", action: { model.openLocal() }) {
            Text("本地终端").font(Font(Theme.font(14))).padding(.horizontal, 15).padding(.vertical, 10).background(
              Ink.pale, in: Capsule())
          }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }
  private var fileSidebar: some View {
    VStack(alignment: .leading, spacing: 15) {
      Spacer()
      Image(systemName: "folder").font(.system(size: 25, weight: .ultraLight))
        .foregroundStyle(Ink.sage).frame(maxWidth: .infinity)
      Text("目录浏览尚未提供").font(Font(Theme.font(12))).foregroundStyle(Ink.muted)
        .frame(maxWidth: .infinity)
      Spacer()
      PaperAction(label: "在当前 Shell 打开 SFTP 控制台", action: openFiles) {
        HStack {
          Image(systemName: "arrow.up.arrow.down")
          Text("SFTP 控制台")
        }.font(.system(size: 11)).foregroundStyle(Ink.sage)
          .frame(maxWidth: .infinity).padding(.vertical, 10).background(
            Ink.pale.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
      }
    }.padding(.leading, 7).padding(.trailing, 18).padding(.top, 12).padding(.bottom, 18)
  }
  private var settings: some View {
    VStack(alignment: .leading, spacing: 28) {
      HStack {
        Text("设置").font(.system(size: 23, weight: .medium))
        Spacer()
        IconAction(icon: "xmark", label: "返回工作区") { model.settings = false }
      }
      HStack {
        Text("服务器侧栏")
        Spacer()
        PaperAction(label: "切换服务器侧栏", action: { sidebar.toggle() }) {
          Text(sidebar ? "显示" : "隐藏").foregroundStyle(Ink.sage).padding(8)
        }
      }
      HStack {
        Text("文件栏")
        Spacer()
        PaperAction(label: "切换文件栏", action: { files.toggle() }) {
          Text(files ? "显示" : "隐藏").foregroundStyle(Ink.sage).padding(8)
        }
      }
      Rectangle().fill(Ink.line).frame(height: 1)
      Spacer()
    }.padding(42).frame(maxWidth: 640, maxHeight: .infinity).frame(maxWidth: .infinity)
  }
  private func divider(size: CGFloat, fraction: Double, resize: @escaping (CGFloat) -> Void)
    -> some View
  {
    StudySplitHandle(
      axis: .horizontal, topHeight: size, fraction: fraction, resize: resize, finish: {}
    )
    .frame(width: 16).padding(.vertical, 17)
  }
}

struct SessionTab: View {
  @ObservedObject var session: Session
  let index: Int
  let selected: Bool
  let select: () -> Void
  let close: () -> Void
  @State private var hovered = false
  var body: some View {
    HStack(spacing: 0) {
      PaperAction(label: "切换到 \(session.server.name) 标签 \(index + 1)", action: select) {
        HStack(spacing: 7) {
          Circle().fill(session.server.tint).frame(width: 5, height: 5)
          Text(session.server.name).font(Font(Theme.font(13, weight: selected ? .medium : .regular)))
          if session.second != nil {
            Image(systemName: "rectangle.split.2x1").font(.system(size: 9)).foregroundStyle(
              Ink.muted)
          }
        }.padding(.leading, 11).padding(.trailing, 7).frame(height: 33)
      }
      IconAction(icon: "xmark", label: "关闭 \(session.server.name) 标签", visible: selected || hovered) { close() }
        .frame(width: 25, height: 27)
    }.padding(.trailing, 3).background(
      selected ? Color.white.opacity(0.65) : .clear, in: RoundedRectangle(cornerRadius: 8)
    )
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Ink.line : .clear))
    .onHover { hovered = $0 }
  }
}

struct SessionView: View {
  @ObservedObject var session: Session
  var body: some View {
    GeometryReader { geometry in
      if let second = session.second {
        let available = max(1, (session.vertical ? geometry.size.height : geometry.size.width) - 18)
        let minimum = min(session.vertical ? 140.0 : 170.0, available * 0.4)
        let size = min(available - minimum, max(minimum, available * session.splitFraction))
        let resize: (CGFloat) -> Void = { value in
          session.splitFraction = min(available - minimum, max(minimum, value)) / available
        }
        let finish: () -> Void = {
          UserDefaults.standard.set(session.splitFraction, forKey: "terminal.fraction")
        }
        if session.vertical {
          VStack(spacing: 0) {
            pane(session.main).frame(height: size)
            StudySplitHandle(
              topHeight: size, fraction: session.splitFraction, resize: resize, finish: finish
            ).frame(height: 18).padding(.horizontal, 14)
            pane(second)
          }
        } else {
          HStack(spacing: 0) {
            pane(session.main).frame(width: size)
            StudySplitHandle(
              axis: .horizontal, topHeight: size, fraction: session.splitFraction, resize: resize,
              finish: finish
            ).frame(width: 18).padding(.vertical, 14)
            pane(second)
          }
        }
      } else {
        pane(session.main)
      }
    }
  }
  private func pane(_ terminal: RealTerminal) -> some View {
    TerminalPane(
      terminal: terminal, focused: session.focusedPane == terminal.id,
      focus: { session.focusedPane = terminal.id },
      close: session.second != nil ? { session.closePane(terminal.id) } : nil)
  }
}

struct TerminalPane: View {
  @ObservedObject var terminal: RealTerminal
  let focused: Bool
  let focus: () -> Void
  let close: (() -> Void)?
  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 6) {
        Image(systemName: terminal.server.local ? "terminal" : "network").foregroundStyle(Ink.sage)
          .help(terminal.server.name)
        Spacer(minLength: 0)
        Text(terminal.status).foregroundStyle(Ink.muted).lineLimit(1).help(terminal.status)
        if let close { IconAction(icon: "xmark", label: "关闭此分屏", action: close) }
      }.font(.system(size: 10, design: .monospaced)).padding(.horizontal, 12).frame(height: 36)
      LiveTerminalView(terminal: terminal).id(terminal.id).padding(7)
    }.background(Color.white.opacity(0.47), in: RoundedRectangle(cornerRadius: 10))
      .overlay(
        RoundedRectangle(cornerRadius: 10).stroke(focused ? Ink.sage.opacity(0.4) : Ink.line)
      )
      .simultaneousGesture(TapGesture().onEnded(focus))
  }
}
