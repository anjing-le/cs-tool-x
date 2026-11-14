import AppKit
import Foundation
import ToolCore

@main struct DataTreeRegression {
  @MainActor static func main() throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    var first = ConnectionProfile(kind: .pg)
    first.host = "fixture.invalid"
    first.database = "one"
    first.name = "source one"
    var second = first
    second.id = UUID()
    second.database = "two"
    second.name = "source two"
    var third = ConnectionProfile(kind: .redis)
    third.name = "source three"
    let profiles = [first, second, third]
    let nav = DataNavigator()
    nav.scroll.frame = NSRect(x: 0, y: 0, width: 330, height: 700)
    nav.update(ConnectionGroup.build(profiles))
    let table = nav.scroll.documentView as! NSTableView
    precondition(nav.roots.count == 2 && table.numberOfRows == 2, "Collapsed connection roots")
    let root = nav.roots[0]
    func key(_ code: UInt16) {
      table.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!)
    }
    table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    key(124)
    precondition(table.numberOfRows == 4, "Right arrow expands selected connection")
    key(36)
    precondition(table.numberOfRows == 2, "Enter on a connection toggles expansion without a network action")
    nav.expand(root)
    precondition(
      table.numberOfRows == 4 && root.children.count == 2, "Database children under one connection")
    let database = root.children[0]
    let schema = DataTreeNode(
      id: database.id + "/schema/public", kind: .schema, title: "public", groupID: root.id,
      profile: first, expandable: true)
    let leaf = DataTreeNode(
      id: schema.id + "/table/sample", kind: .table, title: "sample", groupID: root.id,
      profile: first)
    schema.children = [leaf]
    database.children = [schema]
    nav.expand(database)
    nav.expand(schema)
    precondition(
      table.numberOfRows == 6 && nav.nodeCount == 7, "Database / Schema / table hierarchy")
    precondition(nav.node(leaf.id) === leaf && nav.isCurrent(leaf))
    nav.scroll.layoutSubtreeIfNeeded()
    for row in 0..<table.numberOfRows {
      let view = nav.tableView(table, viewFor: table.tableColumns[0], row: row)
      precondition(view != nil, "Theme-backed reusable row creation")
    }
    nav.update(ConnectionGroup.build(profiles))
    precondition(
      nav.root(root.id) === root && table.numberOfRows == 6,
      "Unchanged refresh preserves expanded objects")
    nav.invalidateGroup(root.id)
    nav.update(ConnectionGroup.build(profiles))
    precondition(
      !nav.isCurrent(leaf) && nav.node(leaf.id) == nil, "Disconnect clears metadata and stale nodes"
    )
    nav.changed(leaf)
    precondition(nav.node(leaf.id) == nil, "Stale response cannot restore removed nodes")
    precondition(
      ConnectionGroup.build(profiles).flatMap(\.profiles).map(\.id) == profiles.map(\.id),
      "Original records remain unchanged")
    if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--render-local" {
      let actual = try ProfileStore().load()
      let groups = ConnectionGroup.build(actual)
      nav.update(groups)
      let frame = NSRect(x: 0, y: 0, width: 330, height: 940)
      let window = NSWindow(
        contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
      let content = NSView(frame: frame)
      window.contentView = content
      nav.scroll.frame = frame
      content.addSubview(nav.scroll)
      content.layoutSubtreeIfNeeded()
      nav.scroll.documentView?.layoutSubtreeIfNeeded()
      if let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
        content.cacheDisplay(in: content.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(
          to: URL(fileURLWithPath: CommandLine.arguments[2]))
      }
      print(
        "Rendered local grouped configuration offscreen: \(groups.count) roots / \(actual.count) original records"
      )
    }
    print(
      "PASS: actual AppKit navigator grouping, four-level expansion, row construction, expansion retention, disconnect invalidation and original-record preservation (offscreen; no live-app interaction)"
    )
  }
}
