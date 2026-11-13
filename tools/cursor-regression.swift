import AppKit
import Foundation

@MainActor final class CursorOwner:NSView,WritingCursorProviding {
  var writingCursorRole:WritingCursorRole = .drag
}
@main struct CursorRegression {
  @MainActor static func main() throws {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    func check(_ condition:@autoclosure ()->Bool,_ message:String) {
      precondition(condition(),message)
    }
    let button=NSButton();let child=NSView();button.addSubview(child)
    check(WritingCursors.role(for:child) == .clickable,"Nested button hit target")
    button.isEnabled=false
    check(WritingCursors.role(for:child) == .disabled,"Disabled button")
    let field=NSTextField();field.isEditable=true
    check(WritingCursors.role(for:field) == .text,"Text entry")
    let secure=NSSecureTextField();secure.isEditable=true
    check(WritingCursors.role(for:secure) == .text,"Secure text entry")
    secure.isEnabled=false
    check(WritingCursors.role(for:secure) == .disabled,"Disabled secure field")
    let text=NSTextView();text.isEditable=false;text.isSelectable=true
    check(WritingCursors.role(for:text) == .text,"Selectable result text")
    let owner=CursorOwner();let inner=NSView();owner.addSubview(inner)
    for role in WritingCursorRole.allCases {
      owner.writingCursorRole=role
      check(WritingCursors.role(for:inner) == role,"Owner precedence")
      let cursor=WritingCursors.cursor(for:role)
      check(cursor === WritingCursors.cursor(for:role),"Cached cursor identity")
      check(cursor.image.size == NSSize(width:24,height:24),"Consistent logical size")
      check(cursor !== NSCursor.arrow && cursor !== NSCursor.iBeam && cursor !== NSCursor.pointingHand,"Custom artwork instance")
    }
    check(WritingCursors.horizontal !== WritingCursors.vertical,"Independent resize axes")
    if CommandLine.arguments.count>1 {
      let directory=URL(fileURLWithPath:CommandLine.arguments[1])
      let theme=WritingCursorPreviewTheme.load(from:directory)!
      let json=try JSONSerialization.jsonObject(with:Data(contentsOf:directory.appendingPathComponent("cursors.json"))) as! [String:Any]
      let logical=json["logicalSize"] as! Double
      for (name,cursor) in [("arrow",theme.arrow),("pointer",theme.pointer)] {
        let spec=json[name] as! [String:Any];let point=spec["hotspot"] as! [Double]
        let source=NSImage(contentsOf:directory.appendingPathComponent(spec["file"] as! String))!
        let bitmap=source.representations.compactMap{$0 as? NSBitmapImageRep}.first!
        let ratio=logical/Double(bitmap.pixelsWide)
        check(cursor.image.size == NSSize(width:logical,height:logical),"Peer logical size")
        check(cursor.hotSpot == NSPoint(x:point[0]*ratio,y:point[1]*ratio),"Peer hotspot")
      }
      check(theme.cursor(for:.clickable) === theme.pointer,"Peer clickable family")
      check(theme.cursor(for:.text) === WritingCursors.text,"Custom text remains semantic")
    }
    // An event overlay must not swallow clicks or survive through a strong registry.
    weak var released:CursorRegionView?
    autoreleasepool {
      let region=CursorRegionView(frame:NSRect(x:0,y:0,width:30,height:30));released=region
      check(region.hitTest(.zero) == nil,"Click-through overlay")
    }
    check(released == nil,"Weak region lifetime")
    print("PASS: button/text/secure/disabled/owner roles, cached custom cursors, peer sizes/hotspots, resize axes and overlay lifetime")
  }
}
