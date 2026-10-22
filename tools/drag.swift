import CoreGraphics
import Foundation
let a = CommandLine.arguments
guard a.count >= 5, let x1 = Double(a[1]), let y1 = Double(a[2]), let x2 = Double(a[3]), let y2 = Double(a[4]) else { exit(2) }
let p1 = CGPoint(x: x1, y: y1), p2 = CGPoint(x: x2, y: y2)
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p1, mouseButton: .left)?.post(tap: .cghidEventTap)
usleep(120000)
CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: p1, mouseButton: .left)?.post(tap: .cghidEventTap)
usleep(120000)
for i in 1...12 {
    let t = Double(i) / 12.0
    let p = CGPoint(x: x1 + (x2 - x1) * t, y: y1 + (y2 - y1) * t)
    CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(20000)
}
usleep(100000)
CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: p2, mouseButton: .left)?.post(tap: .cghidEventTap)
print("dragged")
