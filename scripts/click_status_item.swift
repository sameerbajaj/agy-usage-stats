import Foundation
import CoreGraphics

func click(at point: CGPoint) {
    print("Clicking at \(point)")
    let mouseDown = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
    let mouseUp = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
    mouseDown?.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.1)
    mouseUp?.post(tap: .cghidEventTap)
}

let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements)
let windowListInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: AnyObject]] ?? []

var statusItemCenter: CGPoint? = nil

for info in windowListInfo {
    let owner = info[kCGWindowOwnerName as String] as? String ?? ""
    let name = info[kCGWindowName as String] as? String ?? ""
    let bounds = info[kCGWindowBounds as String] as? [String: Int] ?? [:]
    
    if owner.contains("agy-usage-stats") && name.contains("Item-0") {
        if let x = bounds["X"], let y = bounds["Y"], let w = bounds["Width"], let h = bounds["Height"] {
            statusItemCenter = CGPoint(x: CGFloat(x) + CGFloat(w)/2.0, y: CGFloat(y) + CGFloat(h)/2.0)
            break
        }
    }
}

if let center = statusItemCenter {
    click(at: center)
} else {
    print("Error: Could not find agy-usage-stats status item window")
}
