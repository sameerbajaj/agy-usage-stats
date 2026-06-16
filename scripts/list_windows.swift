import Cocoa

let options = CGWindowListOption(arrayLiteral: .excludeDesktopElements)
let windowListInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: AnyObject]] ?? []

for info in windowListInfo {
    let owner = info[kCGWindowOwnerName as String] as? String ?? "Unknown"
    let name = info[kCGWindowName as String] as? String ?? ""
    let bounds = info[kCGWindowBounds as String] as? [String: Int] ?? [:]
    let pid = info[kCGWindowOwnerPID as String] as? Int ?? 0
    let layer = info[kCGWindowLayer as String] as? Int ?? 0
    let windowID = info[kCGWindowNumber as String] as? Int ?? 0
    if owner.contains("agy") || owner.contains("Usage") || owner.contains("Stats") {
        print("WindowID: \(windowID), PID: \(pid), Owner: \(owner), Name: \(name), Layer: \(layer), Bounds: \(bounds)")
    }
}
