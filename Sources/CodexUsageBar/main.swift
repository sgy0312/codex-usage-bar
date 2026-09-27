import AppKit
import Foundation

struct UsageWindow {
    let usedPercent: Double
    let durationMinutes: Int
    let resetsAt: Date?

    var remainingPercent: Int {
        max(0, min(100, Int((100.0 - usedPercent).rounded())))
    }
}

struct UsageSnapshot {
    let fiveHour: UsageWindow
    let weekly: UsageWindow
    let fetchedAt: Date
}

final class UsageRingsView: NSView {
    var fiveHourRemaining: Int? {
        didSet { needsDisplay = true }
    }

    var weeklyRemaining: Int? {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 52, height: 22)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawRing(center: NSPoint(x: 14, y: bounds.midY), label: "5H", remaining: fiveHourRemaining)
        drawRing(center: NSPoint(x: 39, y: bounds.midY), label: "1W", remaining: weeklyRemaining)
    }

    private func drawRing(center: NSPoint, label: String, remaining: Int?) {
        let radius: CGFloat = 8.5
        let lineWidth: CGFloat = 2.0
        let circleRect = NSRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )

        let background = NSBezierPath(ovalIn: circleRect)
        background.lineWidth = lineWidth
        NSColor.quaternaryLabelColor.setStroke()
        background.stroke()

        if let remaining {
            let clamped = max(0, min(100, remaining))
            let progress = NSBezierPath()
            progress.lineWidth = lineWidth
            progress.lineCapStyle = .round
            progress.appendArc(
                withCenter: center,
                radius: radius,
                startAngle: 90,
                endAngle: 90 - (360 * CGFloat(clamped) / 100),
                clockwise: true
            )
            ringColor(for: clamped).setStroke()
            progress.stroke()
        }

        let fontSize: CGFloat = 6.2
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let textSize = label.size(withAttributes: attributes)
        label.draw(
            at: NSPoint(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2),
            withAttributes: attributes
        )
    }

    private func ringColor(for remaining: Int) -> NSColor {
        if remaining <= 20 { return .systemRed }
        if remaining <= 50 { return .systemOrange }
        return .systemGreen
    }
}

enum UsageError: LocalizedError {
    case codexNotFound
    case launchFailed(String)
    case timeout
    case server(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .codexNotFound:
            return "未找到 Codex 命令行程序"
        case .launchFailed(let message):
            return "无法启动 Codex：\(message)"
        case .timeout:
            return "读取用量超时"
        case .server(let message):
            return "Codex 返回错误：\(message)"
        case .invalidResponse:
            return "Codex 返回了无法识别的用量数据"
        }
    }
}

final class CodexUsageClient {
    private let timeout: TimeInterval = 25

    func fetch(completion: @escaping (Result<UsageSnapshot, Error>) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let result = self.fetchSynchronously()
            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    func fetchSynchronously() -> Result<UsageSnapshot, Error> {
        guard let executable = findCodexExecutable() else {
            return .failure(UsageError.codexNotFound)
        }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        let semaphore = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var buffer = Data()
        var response: Result<UsageSnapshot, Error>?

        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }

            lock.lock()
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[..<newline]
                buffer.removeSubrange(...newline)
                guard
                    let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                    (object["id"] as? NSNumber)?.intValue == 2
                else { continue }

                if let error = object["error"] as? [String: Any] {
                    let message = error["message"] as? String ?? "未知错误"
                    response = .failure(UsageError.server(message))
                } else if let snapshot = Self.parseSnapshot(object) {
                    response = .success(snapshot)
                } else {
                    response = .failure(UsageError.invalidResponse)
                }
                semaphore.signal()
                break
            }
            lock.unlock()
        }

        do {
            try process.run()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            return .failure(UsageError.launchFailed(error.localizedDescription))
        }

        let messages: [[String: Any]] = [
            [
                "id": 1,
                "method": "initialize",
                "params": [
                    "clientInfo": ["name": "codex-usage-bar", "version": "1.0.0"],
                    "capabilities": ["experimentalApi": true]
                ]
            ],
            ["method": "initialized"],
            [
                "id": 2,
                "method": "account/rateLimits/read",
                "params": ["excludeResetCreditDetails": true]
            ]
        ]

        do {
            for message in messages {
                var data = try JSONSerialization.data(withJSONObject: message)
                data.append(0x0A)
                input.fileHandleForWriting.write(data)
            }
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            if process.isRunning { process.terminate() }
            return .failure(error)
        }

        let waitResult = semaphore.wait(timeout: .now() + timeout)
        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }

        if waitResult == .timedOut {
            return .failure(UsageError.timeout)
        }

        lock.lock()
        let finalResponse = response
        lock.unlock()
        return finalResponse ?? .failure(UsageError.invalidResponse)
    }

    private func findCodexExecutable() -> URL? {
        var candidates: [String] = []
        if let configured = ProcessInfo.processInfo.environment["CODEX_CLI_PATH"], !configured.isEmpty {
            candidates.append(configured)
        }
        candidates.append(contentsOf: [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ])

        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map(URL.init(fileURLWithPath:))
    }

    static func parseSnapshot(_ object: [String: Any]) -> UsageSnapshot? {
        guard let result = object["result"] as? [String: Any] else { return nil }

        let limits: [String: Any]
        if
            let buckets = result["rateLimitsByLimitId"] as? [String: Any],
            let codex = buckets["codex"] as? [String: Any]
        {
            limits = codex
        } else if let legacy = result["rateLimits"] as? [String: Any] {
            limits = legacy
        } else {
            return nil
        }

        guard
            let primary = parseWindow(limits["primary"]),
            let secondary = parseWindow(limits["secondary"])
        else { return nil }

        let fiveHour: UsageWindow
        let weekly: UsageWindow
        if primary.durationMinutes <= secondary.durationMinutes {
            fiveHour = primary
            weekly = secondary
        } else {
            fiveHour = secondary
            weekly = primary
        }

        return UsageSnapshot(fiveHour: fiveHour, weekly: weekly, fetchedAt: Date())
    }

    private static func parseWindow(_ value: Any?) -> UsageWindow? {
        guard
            let dictionary = value as? [String: Any],
            let used = dictionary["usedPercent"] as? NSNumber,
            let duration = dictionary["windowDurationMins"] as? NSNumber
        else { return nil }

        let reset: Date?
        if let timestamp = dictionary["resetsAt"] as? NSNumber {
            reset = Date(timeIntervalSince1970: timestamp.doubleValue)
        } else {
            reset = nil
        }

        return UsageWindow(
            usedPercent: used.doubleValue,
            durationMinutes: duration.intValue,
            resetsAt: reset
        )
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let client = CodexUsageClient()
    private var statusItem: NSStatusItem!
    private var ringsView: UsageRingsView!
    private var fiveHourItem: NSMenuItem!
    private var fiveHourResetItem: NSMenuItem!
    private var weeklyItem: NSMenuItem!
    private var weeklyResetItem: NSMenuItem!
    private var updatedItem: NSMenuItem!
    private var refreshItem: NSMenuItem!
    private var refreshIntervalItems: [NSMenuItem] = []
    private var snapshot: UsageSnapshot?
    private var refreshTimer: Timer?
    private var displayTimer: Timer?
    private var isRefreshing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        refresh()

        scheduleRefreshTimer()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.updateDisplay()
        }
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: 52)
        if let button = statusItem.button {
            button.title = ""
            button.toolTip = "Codex 剩余用量"
            ringsView = UsageRingsView(frame: button.bounds)
            ringsView.autoresizingMask = [.width, .height]
            button.addSubview(ringsView)
        }

        let menu = NSMenu()
        fiveHourItem = NSMenuItem(title: "5 小时剩余：--", action: nil, keyEquivalent: "")
        fiveHourItem.isEnabled = false
        fiveHourResetItem = NSMenuItem(title: "重置时间：--", action: nil, keyEquivalent: "")
        fiveHourResetItem.isEnabled = false
        weeklyItem = NSMenuItem(title: "每周剩余：--", action: nil, keyEquivalent: "")
        weeklyItem.isEnabled = false
        weeklyResetItem = NSMenuItem(title: "重置时间：--", action: nil, keyEquivalent: "")
        weeklyResetItem.isEnabled = false
        updatedItem = NSMenuItem(title: "正在读取用量…", action: nil, keyEquivalent: "")
        updatedItem.isEnabled = false

        refreshItem = NSMenuItem(title: "立即刷新", action: #selector(refreshFromMenu), keyEquivalent: "r")
        refreshItem.target = self
        let refreshIntervalItem = NSMenuItem(title: "刷新频率", action: nil, keyEquivalent: "")
        let refreshIntervalMenu = NSMenu()
        for minutes in [1, 5, 10, 15, 30] {
            let item = NSMenuItem(
                title: minutes == 1 ? "每分钟" : "每 \(minutes) 分钟",
                action: #selector(changeRefreshInterval(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = minutes
            refreshIntervalMenu.addItem(item)
            refreshIntervalItems.append(item)
        }
        refreshIntervalItem.submenu = refreshIntervalMenu
        updateRefreshIntervalChecks()
        let quitItem = NSMenuItem(title: "退出 Codex Usage Bar", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self

        menu.addItem(fiveHourItem)
        menu.addItem(fiveHourResetItem)
        menu.addItem(.separator())
        menu.addItem(weeklyItem)
        menu.addItem(weeklyResetItem)
        menu.addItem(.separator())
        menu.addItem(updatedItem)
        menu.addItem(refreshItem)
        menu.addItem(refreshIntervalItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        statusItem.menu = menu
    }

    @objc private func refreshFromMenu() {
        refresh()
    }

    @objc private func changeRefreshInterval(_ sender: NSMenuItem) {
        guard let minutes = sender.representedObject as? Int else { return }
        UserDefaults.standard.set(minutes, forKey: "refreshIntervalMinutes")
        updateRefreshIntervalChecks()
        scheduleRefreshTimer()
        updateDisplay()
    }

    private var refreshIntervalMinutes: Int {
        let value = UserDefaults.standard.integer(forKey: "refreshIntervalMinutes")
        return [1, 5, 10, 15, 30].contains(value) ? value : 5
    }

    private func updateRefreshIntervalChecks() {
        let selected = refreshIntervalMinutes
        for item in refreshIntervalItems {
            item.state = (item.representedObject as? Int) == selected ? .on : .off
        }
    }

    private func scheduleRefreshTimer() {
        refreshTimer?.invalidate()
        let interval = TimeInterval(refreshIntervalMinutes * 60)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshItem?.isEnabled = false
        updatedItem?.title = "正在刷新…"

        client.fetch { [weak self] result in
            guard let self else { return }
            self.isRefreshing = false
            self.refreshItem.isEnabled = true
            switch result {
            case .success(let snapshot):
                self.snapshot = snapshot
                self.updateDisplay()
            case .failure(let error):
                self.ringsView.fiveHourRemaining = nil
                self.ringsView.weeklyRemaining = nil
                self.updatedItem.title = "读取失败：\(error.localizedDescription)"
                self.statusItem.button?.toolTip = error.localizedDescription
            }
        }
    }

    private func updateDisplay() {
        guard let snapshot else { return }
        let five = snapshot.fiveHour.remainingPercent
        let week = snapshot.weekly.remainingPercent
        ringsView.fiveHourRemaining = five
        ringsView.weeklyRemaining = week
        statusItem.button?.toolTip = "Codex：5 小时剩余 \(five)%，每周剩余 \(week)%"
        fiveHourItem.title = "5 小时剩余：\(five)%"
        fiveHourResetItem.title = "重置：\(formatReset(snapshot.fiveHour.resetsAt))"
        weeklyItem.title = "每周剩余：\(week)%"
        weeklyResetItem.title = "重置：\(formatReset(snapshot.weekly.resetsAt))"
        updatedItem.title = "更新：\(formatTime(snapshot.fetchedAt))（每 \(refreshIntervalMinutes) 分钟）"
    }

    private func formatReset(_ date: Date?) -> String {
        guard let date else { return "未知" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "今天 HH:mm" : "M月d日 HH:mm"

        let remaining = max(0, date.timeIntervalSinceNow)
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if hours >= 24 {
            return "\(formatter.string(from: date))（约 \(hours / 24) 天）"
        }
        return "\(formatter.string(from: date))（\(hours) 小时 \(minutes) 分）"
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

if CommandLine.arguments.contains("--self-test") {
    let fixture: [String: Any] = [
        "id": 2,
        "result": [
            "rateLimits": [
                "primary": [
                    "usedPercent": 9,
                    "windowDurationMins": 300,
                    "resetsAt": 1_790_522_911
                ],
                "secondary": [
                    "usedPercent": 1,
                    "windowDurationMins": 10_080,
                    "resetsAt": 1_791_109_711
                ]
            ]
        ]
    ]
    guard
        let snapshot = CodexUsageClient.parseSnapshot(fixture),
        snapshot.fiveHour.remainingPercent == 91,
        snapshot.weekly.remainingPercent == 99
    else {
        fputs("自检失败\n", stderr)
        exit(2)
    }
    print("自检通过：5 小时剩余 91% · 每周剩余 99%")
    exit(0)
}

if CommandLine.arguments.contains("--print-once") {
    switch CodexUsageClient().fetchSynchronously() {
    case .success(let snapshot):
        print("5 小时剩余 \(snapshot.fiveHour.remainingPercent)% · 每周剩余 \(snapshot.weekly.remainingPercent)%")
        exit(0)
    case .failure(let error):
        fputs("\(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
