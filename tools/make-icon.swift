import AppKit
import Foundation
let out = CommandLine.arguments[1]
let image = NSImage(size:NSSize(width:1024,height:1024))
image.lockFocus()
NSColor(calibratedWhite:0.16,alpha:1).setFill()
NSBezierPath(roundedRect:NSRect(x:42,y:42,width:940,height:940),xRadius:210,yRadius:210).fill()
let attrs:[NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:440,weight:.medium),.foregroundColor:NSColor(calibratedWhite:0.96,alpha:1)]
("Cx" as NSString).draw(at:NSPoint(x:200,y:235),withAttributes:attrs)
image.unlockFocus()
let bitmap = NSBitmapImageRep(data:image.tiffRepresentation!)!
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:out))
