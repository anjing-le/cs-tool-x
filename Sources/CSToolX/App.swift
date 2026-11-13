import AppKit
import ToolCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var workbench: WorkbenchController?
  private var keyMonitor: Any?
  private let updater = UpdateController()
  private let engine = EngineClient(
    executable: Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/cs-tool-engine"))
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.appearance = NSAppearance(named: .aqua)
    let menu = NSMenu()
    let appItem = NSMenuItem()
    menu.addItem(appItem)
    let appMenu = NSMenu()
    appItem.submenu = appMenu
    appMenu.addItem(withTitle: "关于 cs-tool-x", action: #selector(about), keyEquivalent: "").target =
      self
    appMenu.addItem(
      withTitle: "检查更新…", action: #selector(UpdateController.check(_:)), keyEquivalent: ""
    ).target = updater
    appMenu.addItem(.separator())
    appMenu.addItem(
      withTitle: "退出 cs-tool-x", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    let edit = NSMenuItem()
    menu.addItem(edit)
    edit.submenu = NSMenu(title: "编辑")
    for (title, action, key) in [
      ("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"),
      ("全选", "selectAll:", "a"),
    ] {
      edit.submenu?.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
    }
    let windowItem = NSMenuItem()
    menu.addItem(windowItem)
    windowItem.submenu = NSMenu(title: "窗口")
    windowItem.submenu?.addItem(
      withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
    let navigation = NSMenuItem()
    menu.addItem(navigation)
    navigation.submenu = NSMenu(title: "工作区")
    for (name, action, key, mods) in [
      ("首页", #selector(home), "1", NSEvent.ModifierFlags.command),
      ("新建终端标签", #selector(newTab), "t", .command),
      ("关闭标签或窗口", #selector(closeTab), "w", .command),
      ("左右分屏", #selector(splitHorizontal), "d", .command),
      ("上下分屏", #selector(splitVertical), "d", [.command, .shift]),
      ("上一个标签", #selector(previousTab), "[", [.command, .shift]),
      ("下一个标签", #selector(nextTab), "]", [.command, .shift]),
    ] {
      let item = navigation.submenu!.addItem(withTitle: name, action: action, keyEquivalent: key)
      item.target = self
      item.keyEquivalentModifierMask = mods
    }
    NSApp.mainMenu = menu
    NSApp.windowsMenu = windowItem.submenu
    workbench = WorkbenchController(engine: engine)
    workbench?.onCheckUpdates = { [weak self] in self?.updater.check(nil) }
    workbench?.showWindow(nil)
    workbench?.window?.makeKeyAndOrderFront(nil)
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, let window = self.workbench?.window,
        event.window === window || window.isKeyWindow, window.attachedSheet == nil
      else { return event }
      let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      if flags == .command {
        if event.keyCode == 13 {
          self.workbench?.closeShellTab()
          return nil
        }
        if event.keyCode == 46 {
          window.performMiniaturize(nil)
          return nil
        }
        if event.keyCode == 18 {
          self.workbench?.goHome()
          window.makeFirstResponder(nil)
          return nil
        }
      }
      if flags == [.control, .command], event.keyCode == 3 {
        if !event.isARepeat { window.toggleFullScreen(nil) }
        return nil
      }
      if event.keyCode == 53 {
        if let editor = window.firstResponder as? NSTextView, editor.hasMarkedText() {
          return event
        }
        if self.workbench?.handleEscape() == true { return nil }
      }
      return event
    }
    updater.start()
    NSApp.activate(ignoringOtherApps: true)
  }
  @objc private func home() { workbench?.goHome() }
  @objc private func newTab() { workbench?.newShellTab() }
  @objc private func closeTab() { workbench?.closeShellTab() }
  @objc private func splitHorizontal() { workbench?.splitShell(vertical: false) }
  @objc private func splitVertical() { workbench?.splitShell(vertical: true) }
  @objc private func previousTab() { workbench?.cycleShell(-1) }
  @objc private func nextTab() { workbench?.cycleShell(1) }
  @objc private func about() { NSApp.orderFrontStandardAboutPanel(nil) }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
  func applicationWillTerminate(_ notification: Notification) { workbench?.stopAll() }
}
@main
struct ApplicationMain {
  @MainActor static func main() {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.regular)
    withExtendedLifetime(delegate) { application.run() }
  }
}
