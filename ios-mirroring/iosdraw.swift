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


// MARK: - 畫面判讀（純函式，`selftest` 會驗）

enum Screen: Equatable {
    case blocker(String)      // 需要本人處理：停下來
    case funboxDone           // Funbox 頁顯示全部完成
    case funbox               // Funbox 清單頁，等它自己開下一筆
    case openPrompt(Int)      // Safari 詢問是否在 LINE 打開；附「打開」那一行的索引
    case result(String)       // 活動頁已有結果或不可抽：關掉即可
    case draw(Int, String)    // 可抽：附按鈕那一行的索引與文字
    case friend(Int)          // 只有加入好友按鈕
    case unknown
}

/// 判讀規則對齊 Android 版 `engine/Rules.kt`。
enum Reader {
    static let prompts = ["請輸入驗證碼", "請登入", "請先登入", "請完成驗證", "請完成安全驗證", "請先解除封鎖", "CAPTCHA"]
    static let ended = ["抽獎期間已結束", "抽選期間已結束", "抽籤期間已結束", "已結束"]
    static let already = ["您已參加過此抽選", "已參加過抽獎", "已抽過"]
    static let loss = ["很可惜未中獎", "未中獎", "未抽中", "銘謝惠顧", "可惜沒有抽中", "很可惜沒有抽中", "沒有抽中"]
    static let win = ["恭喜中獎", "恭喜您中獎了", "恭喜獲得優惠券"]
    static let coupon = ["查看已領取的優惠券", "使用優惠券"]
    static let complete = ["抽選完成", "抽獎完成"]
    static let combined = ["加入好友並抽選", "加入好友並抽獎", "加入好友並參加抽獎"]
    static let submit = ["參加抽選", "立即抽選", "挑戰抽獎", "立即抽獎", "參加抽獎", "抽獎", "抽選"]
    static let funboxMarks = ["自動連抽", "抽選模式", "手動抽選"]

    /// 去掉空白與標點再比對，容許辨識結果多一個驚嘆號或空格。
    static func canonical(_ text: String) -> String {
        String(text.precomposedStringWithCompatibilityMapping.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0) && !CharacterSet.punctuationCharacters.contains($0) && !CharacterSet.symbols.contains($0)
        })
    }

    static func classify(_ lines: [String]) -> Screen {
        let texts = lines.map(canonical)
        func has(_ labels: [String]) -> Bool { texts.contains { labels.map(canonical).contains($0) } }
        func index(_ labels: [String]) -> Int? { texts.firstIndex { labels.map(canonical).contains($0) } }
        if let hit = texts.first(where: { prompts.map(canonical).contains($0) }) { return .blocker(hit) }
        if texts.contains(where: { text in funboxMarks.contains { text.contains($0) } }) {
            return texts.contains { $0.contains("全部完成") } ? .funboxDone : .funbox
        }
        if texts.contains(where: { $0.contains("中打開") }), let open = index(["打開"]) { return .openPrompt(open) }
        if has(ended) { return .result("已結束") }
        if has(coupon) { return .result("已領取優惠券") }
        if has(already) { return .result("已抽過") }
        if has(loss) { return .result("未中獎") }
        if has(win) { return .result("中獎") }
        if has(complete) { return .result("抽選完成") }
        if let i = index(combined) ?? index(submit) { return .draw(i, lines[i]) }
        if let i = index(["加入好友"]) { return .friend(i) }
        return .unknown
    }
}

func selftest() {
    var failures = 0
    func expect(_ lines: [String], _ expected: Screen, _ name: String) {
        let actual = Reader.classify(lines)
        if actual != expected { failures += 1; print("FAIL \(name): \(actual) != \(expected)") }
    }
    expect(["任意店家", "UX-03 魔導神杖", "抽 獎"], .draw(2, "抽 獎"), "draw button with a stray space")
    expect(["加入好友並參加抽獎"], .draw(0, "加入好友並參加抽獎"), "combined button")
    expect(["加入好友", "抽獎"], .draw(1, "抽獎"), "draw wins over friend when both show")
    expect(["加入好友"], .friend(0), "friend only")
    expect(["恭喜中獎！", "查看已領取的優惠券"], .result("已領取優惠券"), "coupon button")
    expect(["很可惜，未中獎"], .result("未中獎"), "loss with punctuation")
    expect(["可惜...沒有抽中！"], .result("未中獎"), "loss variant")
    expect(["您已參加過此抽選", "抽選"], .result("已抽過"), "already beats a leftover button")
    expect(["抽獎期間已結束！", "確認"], .result("已結束"), "ended notice")
    expect(["請輸入驗證碼", "抽獎"], .blocker("請輸入驗證碼"), "blocker beats everything")
    expect(["本活動不需登入或驗證碼", "抽獎"], .draw(1, "抽獎"), "instructions mentioning 驗證碼 are not a prompt")
    expect(["10/08 10/09 抽選", "抽選模式", "⚡ 自動連抽", "UX-13 魔像奇岩"], .funbox, "funbox list is never a draw page")
    expect(["抽選模式", "全部完成，已停止自動連續抽選"], .funboxDone, "funbox finished")
    expect(["要在「LINE」中打開嗎？", "取消", "打開"], .openPrompt(2), "safari open-in-LINE prompt")
    expect(["如果沒有抽中可以參加下次抽選"], .unknown, "loss mentioned inside a sentence is not a result")
    expect(["聊天", "主頁", "錢包"], .unknown, "LINE home")
    print(failures == 0 ? "selftest ok" : "selftest: \(failures) failed")
    exit(failures == 0 ? 0 : 1)
}

// MARK: - 自動輪迴

struct Settings {
    var closeX = 0.93, closeY = 0.075      // 活動頁右上角關閉鈕在視窗內的相對位置
    var dwell = 1.0...2.0                  // 活動頁出現後、按抽獎前
    var settle = 1.0...3.0                 // 按抽獎後、關視窗前
    var stall = 120.0                      // 這麼久沒有任何動作就停
    var maxItems = Int.max
    var dryRun = false
}

func pause(_ seconds: Double) { usleep(useconds_t(seconds * 1_000_000)) }
func log(_ message: String) {
    let stamp = DateFormatter(); stamp.dateFormat = "HH:mm:ss"
    print("\(stamp.string(from: Date())) \(message)"); fflush(stdout)
}

func run(_ settings: Settings) -> Never {
    var window = mirror()
    func look() -> ([Line], Screen) {
        window = mirror()
        let lines = read(capture(window, to: shot), in: window)
        return (lines, Reader.classify(lines.map(\.text)))
    }
    func act(_ what: String, _ point: CGPoint) {
        log("\(settings.dryRun ? "[試跑，不點] " : "")\(what) @\(Int(point.x)),\(Int(point.y))")
        if !settings.dryRun { click(point) }
    }
    /// 關掉活動頁；關完若人還在 LINE，點左上角的「◀ Safari」回清單，讓 Funbox 自己開下一筆。
    func closeAndReturn() {
        act("關閉視窗", CGPoint(x: window.frame.minX + settings.closeX * window.frame.width, y: window.frame.minY + settings.closeY * window.frame.height))
        pause(1.0)
        let (lines, screen) = look()
        if screen == .funbox || screen == .funboxDone { return }
        if let back = lines.first(where: { $0.text.contains("Safari") && $0.center.y < window.frame.minY + 0.09 * window.frame.height }) {
            act("回到 Safari", back.center)
        }
    }
    activate(window)
    var done = 0, closes = 0, friendTapped = false
    var lastAction = Date()
    var results: [String: Int] = [:]
    func finish(_ reason: String, _ code: Int32) -> Never {
        log("結束：\(reason)。共處理 \(done) 筆 \(results.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: "、"))")
        exit(code)
    }
    while true {
        let (lines, screen) = look()
        switch screen {
        case .blocker(let text): finish("畫面要求「\(text)」，請本人處理後再重跑", 2)
        case .funboxDone: finish("Funbox 顯示全部完成", 0)
        case .funbox:
            closes = 0; friendTapped = false
        case .openPrompt(let i):
            act("在 LINE 打開", lines[i].center); lastAction = Date()
        case .friend(let i):
            if !friendTapped { act("加入好友", lines[i].center); friendTapped = true; lastAction = Date(); pause(1.5) }
        case .draw:
            pause(Double.random(in: settings.dwell))
            // 等完再讀一次，只按當下還在的按鈕。
            let (fresh, again) = look()
            guard case .draw(let i, let label) = again else { continue }
            act("按「\(label)」", fresh[i].center)
            pause(Double.random(in: settings.settle))
            let (_, after) = look()
            if case .blocker(let text) = after { finish("送出後畫面要求「\(text)」，請本人處理", 2) }
            var outcome = "已送出"
            if case .result(let text) = after { outcome = text }
            done += 1; results[outcome, default: 0] += 1; friendTapped = false; closes = 0
            log("第 \(done) 筆：\(outcome)")
            closeAndReturn(); lastAction = Date()
            if done >= settings.maxItems { finish("已達指定筆數", 0) }
        case .result(let text):
            closes += 1
            // 同一個結果畫面關了三次還在：關閉鈕位置不對，別再亂點。
            if closes > 3 { finish("關不掉活動頁，請用 --close-x / --close-y 調整關閉鈕位置（截圖在 \(shot)）", 3) }
            if closes == 1 { done += 1; results[text, default: 0] += 1; log("第 \(done) 筆：\(text)（未送出）") }
            closeAndReturn(); lastAction = Date()
            if done >= settings.maxItems { finish("已達指定筆數", 0) }
        case .unknown: break
        }
        if Date().timeIntervalSince(lastAction) > settings.stall {
            finish(screen == .funbox ? "Funbox 頁沒有開下一筆；請確認已切到「自動連抽」並按開始" : "畫面超過 \(Int(settings.stall)) 秒認不出來（截圖在 \(shot)）", 4)
        }
        pause(0.7)
    }
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
case "selftest":
    selftest()
case "run":
    var settings = Settings()
    var rest = Array(arguments.dropFirst())
    while !rest.isEmpty {
        let flag = rest.removeFirst()
        func number() -> Double {
            guard !rest.isEmpty, let value = Double(rest.removeFirst()) else { fail("\(flag) 後面要接數字") }
            return value
        }
        switch flag {
        case "--dry-run": settings.dryRun = true
        case "--max": settings.maxItems = Int(number())
        case "--close-x": settings.closeX = number()
        case "--close-y": settings.closeY = number()
        case "--stall": settings.stall = number()
        default: fail("不認得的選項：\(flag)")
        }
    }
    run(settings)
default:
    fail("用法：iosdraw run [--dry-run] [--max N] [--close-x 0.93] [--close-y 0.075] [--stall 秒] | probe [截圖路徑] | click X Y | tap 文字 | scroll 行數 | selftest")
}
