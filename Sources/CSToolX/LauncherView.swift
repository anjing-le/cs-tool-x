import SwiftUI
import ToolCore

/// FinanceX's quiet equal-width cards, with a separate destination for each tool.
struct LauncherView: View {
  let enter: (ToolModule) -> Void
  var body: some View {
    GeometryReader { geometry in
      let count = max(1, min(2, Int((geometry.size.width - 112 + 24) / 244)))
      ScrollView {
        LazyVGrid(
          columns: Array(repeating: GridItem(.flexible(), spacing: 24), count: count), spacing: 24
        ) {
          ModuleCard(name: "Shell") { enter(.terminal) }
          ModuleCard(name: "数据") { enter(.data) }
        }.frame(maxWidth: 1120).padding(.horizontal, 56).padding(.vertical, 48)
          .frame(maxWidth: .infinity, minHeight: geometry.size.height)
      }.scrollIndicators(.hidden)
    }.background(Ink.background).preferredColorScheme(.light)
  }
}
private struct ModuleCard: View {
  let name: String
  let action: () -> Void
  @State private var hovered = false
  @FocusState private var focused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    Button {
      hovered = false
      action()
    } label: {
      Text(name).font(.system(size: 19, weight: .medium)).foregroundStyle(Ink.sage)
        .frame(maxWidth: .infinity).frame(height: 180)
        .background(
          .white.opacity(hovered || focused ? 0.72 : 0.48), in: RoundedRectangle(cornerRadius: 24)
        )
        .overlay(
          RoundedRectangle(cornerRadius: 24).strokeBorder(
            Ink.main.opacity(focused ? 0.26 : 0.10), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(hovered ? 0.12 : 0), radius: 24, x: 0, y: 10)
        .offset(y: reduceMotion ? 0 : (hovered ? -3 : 0))
    }.buttonStyle(.plain).focused($focused).onHover { hovered = $0 }.onDisappear { hovered = false }
      .animation(reduceMotion ? nil : .timingCurve(0.4, 0, 0.2, 1, duration: 0.28), value: hovered)
      .accessibilityLabel(name)
  }
}
