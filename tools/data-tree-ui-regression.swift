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
      table.keyDown(
        with: NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
          windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
          isARepeat: false, keyCode: code)!)
    }
    var activations = 0
    nav.onActivate = { node in
      precondition(node === root)
      activations += 1
    }
    table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
    precondition(table.numberOfRows == 2 && activations == 0, "Selection neither expands nor connects")
    let sidebarWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 298, height: 680),
      styleMask: [.borderless], backing: .buffered, defer: false)
    sidebarWindow.contentView = nav.scroll
    for width in [298.0, 210.0, 330.0] {
      sidebarWindow.setContentSize(NSSize(width: width, height: 680))
      nav.scroll.tile()
      nav.scroll.layoutSubtreeIfNeeded()
      table.layoutSubtreeIfNeeded()
      let cell = table.view(atColumn: 0, row: 0, makeIfNecessary: true)!
      cell.layoutSubtreeIfNeeded()
      let marker = cell.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue == "✓" }!
      let rect = marker.convert(marker.bounds, to: nav.scroll.contentView)
      precondition(!marker.isHidden && nav.scroll.contentView.bounds.contains(rect),
        "Selection marker stays inside narrow sidebar viewport")
      precondition(abs(table.frame.width - nav.scroll.contentSize.width) < 1, "Tree matches viewport without inset overflow")
    }
    key(36)
    precondition(table.numberOfRows == 4 && activations == 1, "Enter expands and opens connection once")
    key(36)
    precondition(table.numberOfRows == 2 && activations == 1, "Enter collapses without another connection")
    nav.expand(root, respectingUserCollapse: true)
    precondition(table.numberOfRows == 2, "Late connection callback cannot reopen collapsed directory")
    key(124)
    precondition(table.numberOfRows == 4 && activations == 1, "Right arrow only expands")
    key(123)
    precondition(table.numberOfRows == 2, "Left arrow collapses without opening")
    nav.activateSelection()
    precondition(table.numberOfRows == 4 && activations == 2, "Double-click action expands and opens")
    nav.activateSelection()
    precondition(table.numberOfRows == 2 && activations == 2, "Double-click collapse does not reconnect")
    nav.onActivate = nil
    let hit = HitButton(frame: NSRect(x: 0, y: 0, width: 100, height: 30))
    let target = GestureTarget()
    hit.requiredClicks = 2
    hit.target = target
    hit.action = #selector(GestureTarget.open)
    hit.selectionHandler = { target.selections += 1 }
    func click(_ count: Int) {
      hit.mouseDown(
        with: NSEvent.mouseEvent(
          with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
          context: nil, eventNumber: count, clickCount: count, pressure: 1)!)
    }
    click(1)
    precondition(target.selections == 1 && target.opens == 0, "Shell single click selects only")
    click(2)
    precondition(target.opens == 1, "Shell second click opens exactly once")
    hit.isEnabled = false
    click(2)
    precondition(target.opens == 1, "Disabled target cannot open")
    hit.isEnabled = true
    var directions: [Bool] = []
    hit.disclosureHandler = { directions.append($0) }
    for code: UInt16 in [124, 123] {
      hit.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
        windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!)
    }
    precondition(directions == [true, false] && target.opens == 1, "Shell group arrow keys expand/collapse without activation")

    let groupHit = HitButton(frame: NSRect(x: 0, y: 0, width: 100, height: 30))
    let groupTarget = GestureTarget()
    groupHit.target = groupTarget
    groupHit.action = #selector(GestureTarget.open)
    var renames = 0
    groupHit.doubleClickHandler = { renames += 1 }
    func groupClick(_ count: Int) {
      groupHit.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
        timestamp: 0, windowNumber: 0, context: nil, eventNumber: count, clickCount: count, pressure: 1)!)
    }
    groupHit.doubleClickUndo = { groupTarget.open() }
    groupClick(1)
    precondition(groupTarget.opens == 1 && groupTarget.expanded, "Group single click expands synchronously without waiting")
    precondition(!groupHit.keyboardFocusVisible, "Mouse click does not draw an inner keyboard focus ring")
    groupClick(2)
    precondition(renames == 1 && groupTarget.opens == 2 && !groupTarget.expanded, "Double click restores original expansion then renames")
    groupClick(1)
    precondition(groupTarget.opens == 3 && groupTarget.expanded, "Next single click is immediate")
    groupHit.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
      windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 120)!)
    precondition(renames == 2 && groupTarget.expanded && groupHit.keyboardFocusVisible, "F2 renames without undoing previous click and retains keyboard focus")
    groupHit.isEnabled = false
    groupClick(1)
    precondition(groupTarget.opens == 3, "Disabled group cannot toggle")
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
      let labels = view!.subviews.compactMap { $0 as? NSTextField }
      precondition(!view!.subviews.contains { $0 is NSButton }, "No disclosure button in data rows")
      let marker = labels.first { $0.stringValue == "✓" }!
      precondition(marker.isHidden == (row != table.selectedRow), "Right-side marker follows selection")
    }
    table.deselectAll(nil)
    let deselected = nav.tableView(table, viewFor: table.tableColumns[0], row: 0)!
    precondition(deselected.subviews.compactMap { $0 as? NSTextField }.first { $0.stringValue == "✓" }!.isHidden,
      "Clearing selection removes the right-side marker")
    var leafOpens = 0
    nav.onActivate = { node in
      precondition(node === leaf)
      leafOpens += 1
    }
    table.selectRowIndexes(IndexSet(integer: 3), byExtendingSelection: false)
    key(36)
    nav.activateSelection()
    precondition(leafOpens == 2 && table.numberOfRows == 6, "Enter/double-click open leaf without changing expansion")
    nav.onActivate = nil
    nav.filterConnection(root.id)
    precondition(
      table.numberOfRows == 5, "Connection picker filters the tree without dropping cached roots")
    nav.filterConnection(nil)
    precondition(table.numberOfRows == 6 && nav.roots.count == 2)
    nav.update(ConnectionGroup.build(profiles))
    precondition(
      nav.root(root.id) === root && table.numberOfRows == 6,
      "Unchanged refresh preserves expanded objects")
    var added = first
    added.id = UUID()
    added.database = "three"
    nav.update(ConnectionGroup.build(profiles + [added]))
    precondition(
      nav.root(root.id) === root && nav.isCurrent(leaf),
      "Connecting another database preserves loaded sibling schemas and expanded root")
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
    func descendants(_ view: NSView) -> [NSView] {
      [view] + view.subviews.flatMap { descendants($0) }
    }
    let objectBrowser = DataBrowser(frame: NSRect(x: 0, y: 0, width: 650, height: 700))
    objectBrowser.update(nav.roots[0], breadcrumb: "fixture")
    precondition(!descendants(objectBrowser).contains { $0 is NSTableView }, "Directory context must not duplicate sidebar objects")
    precondition(!descendants(objectBrowser).contains { ($0 as? NSTextField)?.isEditable == true }, "Directory context has no duplicate result filter")
    var queryRequested = false
    objectBrowser.onQuery = { queryRequested = true }
    descendants(objectBrowser).compactMap { $0 as? NSButton }.first { $0.title == "查询" }!
      .performClick(nil)
    precondition(queryRequested, "Directory context provides query entry")
    let workspace = DataWorkspace(
      profile: first, sessionID: "offscreen", elapsed: 0,
      engine: EngineClient(executable: URL(fileURLWithPath: "/missing/test-engine")))
    let editor = descendants(workspace).compactMap { $0 as? NSTextView }.first!
    editor.string = "SELECT 42 AS draft"
    descendants(workspace).compactMap { $0 as? NSButton }.first { $0.title == "数据" }!.performClick(
      nil)
    precondition(!workspace.queryMode, "Browse mode hides query controls")
    workspace.showQuery()
    precondition(
      workspace.queryMode && editor.string == "SELECT 42 AS draft",
      "Returning to query preserves its draft")
    let content = DataContentHost(frame: NSRect(x: 0, y: 0, width: 650, height: 700))
    content.showDirectory(objectBrowser)
    precondition(content.subviews.first === objectBrowser, "Initial directory context has no data list")
    objectBrowser.removeFromSuperview()
    Theme.pin(workspace, to: content)
    content.showDirectory(DataBrowser(frame: .zero))
    precondition(content.subviews.count == 1 && content.subviews.first === workspace && editor.string == "SELECT 42 AS draft",
      "Expanding another directory preserves the visible query and draft")
    let budgetNode = nav.roots[0].children[0]
    budgetNode.children = (0..<5001).map {
      DataTreeNode(
        id: "large-\($0)", kind: .table, title: "table-\($0)", groupID: nav.roots[0].id,
        profile: first)
    }
    nav.update(ConnectionGroup.build(profiles))
    precondition(
      nav.nodeCount <= 5000 && !nav.isCurrent(budgetNode),
      "Source refresh evicts metadata over budget and invalidates old callbacks")
    if CommandLine.arguments.count >= 3, CommandLine.arguments[1] == "--render-local" {
      let actual = try ProfileStore().load()
      let groups = ConnectionGroup.build(actual)
      nav.update(groups)
      let selected = nav.roots.first { $0.profile?.kind == .mysql } ?? nav.roots[0]
      if CommandLine.arguments.count >= 4 {
        let metadata = try JSONDecoder().decode(
          QueryOutput.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3])))
        selected.children = metadata.rows.compactMap { row in
          guard let name = row.first?.text, var profile = selected.profile else { return nil }
          profile.id = UUID()
          profile.database = name
          return nav.databaseNode(profile: profile, groupID: selected.groupID)
        }
        selected.loaded = true
      }
      nav.expand(selected)
      let frame = NSRect(x: 0, y: 0, width: 1200, height: 760)
      let window = NSWindow(
        contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
      let content = NSView(frame: frame)
      content.wantsLayer = true
      content.layer?.backgroundColor = Theme.paper.cgColor
      window.contentView = content
      nav.scroll.frame = NSRect(x: 0, y: 0, width: 330, height: 760)
      content.addSubview(nav.scroll)
      let browser = DataBrowser(frame: NSRect(x: 330, y: 0, width: 870, height: 760))
      browser.update(selected, breadcrumb: selected.title)
      content.addSubview(browser)
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

@MainActor final class GestureTarget: NSObject {
  var opens = 0
  var selections = 0
  var expanded = false
  @objc func open() { opens += 1; expanded.toggle() }
}
