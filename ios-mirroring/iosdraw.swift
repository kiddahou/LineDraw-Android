// 透過 macOS「iPhone 鏡像輸出」視窗操作 iPhone：截圖、辨識畫面文字、點擊、捲動。
// 需要執行它的終端機 App 具備「螢幕錄製」與「輔助使用」權限。
import AppKit
import Vision

let bundleID = "com.apple.ScreenContinuity"

struct Mirror { let id: CGWindowID; let frame: CGRect; let pid: pid_t }
struct Line { let text: String; let center: CGPoint; let box: CGRect }

func fail(_ message: String) -> Never { FileHandle.standardError.write((message + "\n").data(using: .utf8)!); exit(1) }

func mirror() -> Mirror {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
        fail("找不到「iPhone 鏡像輸出」。請先開啟它並連上 iPhone。")
    }
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    let own = windows.filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier && ($0[kCGWindowLayer as String] as? Int) == 0 }
    // 取面積最大的那個：主畫面視窗，不是工具列或提示。
    let best = own.compactMap { info -> Mirror? in
        guard let id = info[kCGWindowNumber as String] as? CGWindowID, let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds) else { return nil }
        return Mirror(id: id, frame: frame, pid: app.processIdentifier)
    }.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    guard let found = best, found.frame.height > 200 else { fail("「iPhone 鏡像輸出」沒有可用的視窗（可能縮到最小或尚未連線）。") }
    return found
}

func capture(_ window: Mirror, to path: String) -> CGImage {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    task.arguments = ["-x", "-o", "-l", String(window.id), path]
    try? task.run(); task.waitUntilExit()
    guard let image = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fail("截圖失敗。請到「系統設定 → 隱私權與安全性 → 螢幕與系統錄音」允許這個終端機 App。")
    }
    return image
}

/// 辨識結果的座標換算成螢幕座標（左上為原點），可直接拿來點擊。
func read(_ image: CGImage, in window: Mirror) -> [Line] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["zh-Hant", "en-US"]
    request.usesLanguageCorrection = false
    try? VNImageRequestHandler(cgImage: image).perform([request])
    return (request.results ?? []).compactMap { observation in
        guard let text = observation.topCandidates(1).first?.string else { return nil }
        let b = observation.boundingBox
        let box = CGRect(x: window.frame.minX + b.minX * window.frame.width, y: window.frame.minY + (1 - b.maxY) * window.frame.height,
                         width: b.width * window.frame.width, height: b.height * window.frame.height)
        return Line(text: text, center: CGPoint(x: box.midX, y: box.midY), box: box)
    }.sorted { $0.center.y < $1.center.y }
}

func activate(_ window: Mirror) {
    NSRunningApplication(processIdentifier: window.pid)?.activate(options: [])
    usleep(250_000)
}

func click(_ point: CGPoint) {
    guard AXIsProcessTrusted() else { fail("無法送出點擊。請到「系統設定 → 隱私權與安全性 → 輔助使用」允許這個終端機 App。") }
    let source = CGEventSource(stateID: .hidSystemState)
    CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(120_000)
    CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(60_000)
    CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
}

func scroll(_ window: Mirror, lines: Int32) {
    guard AXIsProcessTrusted() else { fail("無法捲動。請到「系統設定 → 隱私權與安全性 → 輔助使用」允許這個終端機 App。") }
    let middle = CGPoint(x: window.frame.midX, y: window.frame.midY)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: middle, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(120_000)
    CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
}

let arguments = Array(CommandLine.arguments.dropFirst())
let shot = FileManager.default.temporaryDirectory.appendingPathComponent("iosdraw.png").path
switch arguments.first {
case "probe":
    let window = mirror()
    let path = arguments.count > 1 ? arguments[1] : shot
    let lines = read(capture(window, to: path), in: window)
    print("window \(Int(window.frame.minX)),\(Int(window.frame.minY)) \(Int(window.frame.width))x\(Int(window.frame.height)) shot=\(path)")
    for line in lines { print("\(Int(line.center.x)),\(Int(line.center.y))\t\(line.text)") }
case "click":
    guard arguments.count == 3, let x = Double(arguments[1]), let y = Double(arguments[2]) else { fail("用法：iosdraw click X Y") }
    activate(mirror()); click(CGPoint(x: x, y: y))
case "tap":
    guard arguments.count >= 2 else { fail("用法：iosdraw tap 文字") }
    let window = mirror()
    let lines = read(capture(window, to: shot), in: window)
    guard let hit = lines.first(where: { $0.text.replacingOccurrences(of: " ", with: "") == arguments[1] }) ?? lines.first(where: { $0.text.contains(arguments[1]) }) else {
        fail("畫面上找不到「\(arguments[1])」")
    }
    activate(window); click(hit.center)
    print("\(Int(hit.center.x)),\(Int(hit.center.y))\t\(hit.text)")
case "scroll":
    guard arguments.count == 2, let lines = Int32(arguments[1]) else { fail("用法：iosdraw scroll 行數（負數往下）") }
    let window = mirror(); activate(window); scroll(window, lines: lines)
default:
    fail("用法：iosdraw probe [截圖路徑] | click X Y | tap 文字 | scroll 行數")
}
