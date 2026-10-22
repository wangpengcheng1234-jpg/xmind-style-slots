import Cocoa
import WebKit
import ObjectiveC

// MARK: - 日志

private let logPath = "/tmp/xmind-style-panel.log"

func panelLog(_ text: String) {
    let line = "[\(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium))] \(text)\n"
    guard let data = line.data(using: .utf8) else { return }
    if let fh = FileHandle(forWritingAtPath: logPath) {
        fh.seekToEndOfFile()
        fh.write(data)
        fh.closeFile()
    } else {
        try? data.write(to: URL(fileURLWithPath: logPath))
    }
}

// MARK: - CDP 客户端

final class CDPClient: NSObject, URLSessionWebSocketDelegate {
    private var task: URLSessionWebSocketTask?
    private var session: URLSession!
    private var nextId = 1
    private var pending: [Int: (String?) -> Void] = [:]

    private(set) var isOpen = false
    var onOpen: (() -> Void)?
    var onClosed: (() -> Void)?

    override init() {
        super.init()
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 6
        session = URLSession(configuration: cfg, delegate: nil, delegateQueue: nil)
    }

    func connect(_ url: URL) {
        disconnect()
        let t = session.webSocketTask(with: url)
        t.delegate = self
        task = t
        t.resume()
        receive()
    }

    func disconnect() {
        isOpen = false
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        pending.removeAll()
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure:
                self.isOpen = false
                self.onClosed?()
            case .success(let message):
                if case .string(let text) = message {
                    self.handle(text)
                }
                self.receive()
            }
        }
    }

    private func handle(_ text: String) {
        guard
            let data = text.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        guard let id = obj["id"] as? Int, let completion = pending.removeValue(forKey: id) else { return }
        if obj["error"] != nil {
            completion(nil)
            return
        }
        let result = obj["result"] as? [String: Any]
        let inner = result?["result"] as? [String: Any]
        completion(inner?["value"] as? String)
    }

    func evaluate(_ expression: String, completion: ((String?) -> Void)? = nil) {
        guard let task, isOpen else {
            completion?(nil)
            return
        }
        let id = nextId
        nextId += 1
        let message: [String: Any] = [
            "id": id,
            "method": "Runtime.evaluate",
            "params": [
                "expression": expression,
                "returnByValue": true,
                "awaitPromise": true,
            ],
        ]
        guard
            let data = try? JSONSerialization.data(withJSONObject: message),
            let text = String(data: data, encoding: .utf8)
        else {
            completion?(nil)
            return
        }
        if let completion {
            pending[id] = completion
        }
        task.send(.string(text)) { [weak self] error in
            if error != nil {
                self?.pending.removeValue(forKey: id)
                completion?(nil)
            }
        }
    }

    // URLSessionWebSocketDelegate
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        isOpen = true
        panelLog("CDP 已连接")
        onOpen?()
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        isOpen = false
        panelLog("CDP 已断开")
        onClosed?()
    }
}

// MARK: - 悬浮面板

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// 让面板接住「第一次点击」，否则需要点两下
final class PanelWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

final class PanelController: NSObject, WKScriptMessageHandler {
    private let panelWidth: CGFloat = 304
    private let panelHeight: CGFloat = 404

    private var panel: FloatingPanel!
    private var webView: WKWebView!
    private let cdp = CDPClient()

    private var tickTimer: Timer?
    private var isConnected = false
    private var isConnecting = false
    private var lastConnectAttempt = Date.distantPast

    private var dragging = false
    private var dragOffset = NSPoint.zero
    private var resizing = false
    private var resizeOrigin = NSPoint.zero
    private var resizeStartFrame = NSRect.zero
    private var gestureMonitor: Any?
    private var lastPushedStamp = ""

    func start() {
        buildWindow()
        buildWebView()
        cdp.onOpen = { [weak self] in
            self?.isConnected = true
            self?.isConnecting = false
            self?.refresh()
        }
        cdp.onClosed = { [weak self] in
            self?.isConnected = false
            self?.isConnecting = false
            self?.pushDisconnected()
        }
        panel.orderFrontRegardless()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        panelLog("面板已启动")
    }

    private func buildWindow() {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let x = screen.maxX - panelWidth - 24
        let y = screen.maxY - panelHeight - 56
        panel = FloatingPanel(
            contentRect: NSRect(x: x, y: y, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        // 紧凑模式最低：5 个小色圆点横排
        panel.minSize = NSSize(width: 140, height: 60)
        panel.maxSize = NSSize(width: 900, height: 1200)

        let autosaveKey = "NSWindow Frame XmindStylePanelFrame"
        panel.setFrameAutosaveName("XmindStylePanelFrame")

        // 验证存档是否还在当前屏幕内（换显示器/拔线后可能跑到屏幕外）
        let savedFrame = panel.frame
        let visibleScreen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 99999, height: 99999)
        let inScreen =
          NSIntersectsRect(savedFrame, visibleScreen) &&
          savedFrame.width >= panel.minSize.width &&
          savedFrame.height >= panel.minSize.height
        if !inScreen {
          // 存档坏了，清掉让系统下次用默认位置
          UserDefaults.standard.removeObject(forKey: autosaveKey)
          UserDefaults.standard.set(true, forKey: autosaveKey + ".reset")
          panel.setContentSize(NSSize(width: panelWidth, height: panelHeight))
          // 放在当前屏幕右上角
          let sx = visibleScreen.maxX - panelWidth - 24
          let sy = visibleScreen.maxY - panelHeight - 56
          panel.setFrameOrigin(NSPoint(x: sx, y: sy))
          panelLog("存档 frame=\(savedFrame) 不在屏幕内，回退默认位置")
        } else {
          panelLog("沿用存档 frame=\(savedFrame)")
        }
    }

    private func buildWebView() {
        // 底层玻璃：macOS 26 用原生液态玻璃，旧系统退回普通毛玻璃
        let glassFrame = panel.contentView!.bounds.insetBy(dx: 10, dy: 10)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: glassFrame)
            glass.cornerRadius = 18
            glass.style = .regular
            glass.tintColor = NSColor.white.withAlphaComponent(0.10)
            glass.autoresizingMask = [.width, .height]
            panel.contentView!.addSubview(glass)
        } else {
            let blur = NSVisualEffectView(frame: glassFrame)
            blur.material = .popover
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.wantsLayer = true
            blur.layer?.cornerRadius = 18
            blur.layer?.masksToBounds = true
            blur.autoresizingMask = [.width, .height]
            panel.contentView!.addSubview(blur)
        }

        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "cmd")
        config.suppressesIncrementalRendering = false

        webView = PanelWebView(frame: panel.contentView!.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        panel.contentView!.addSubview(webView)

        if let url = Bundle.main.url(forResource: "index", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            panelLog("找不到 index.html")
        }
    }

    // MARK: 轮询

    // 把「第一次点击」交给 WKWebView 内部的私有视图处理，
    // 否则点击会先被用来激活窗口，表现为要点两下。
    private var patchedClasses = Set<ObjectIdentifier>()

    private func patchFirstMouseDeep(_ view: NSView) {
        for sub in view.subviews {
            patchFirstMouse(type(of: sub))
            patchFirstMouseDeep(sub)
        }
    }

    private func patchFirstMouse(_ cls: AnyClass) {
        let key = ObjectIdentifier(cls)
        guard !patchedClasses.contains(key) else { return }
        let sel = #selector(NSView.acceptsFirstMouse(for:))
        guard let method = class_getInstanceMethod(cls, sel) else { return }
        patchedClasses.insert(key)
        let block: @convention(block) (AnyObject, NSEvent?) -> Bool = { _, _ in true }
        let imp = imp_implementationWithBlock(block)
        class_replaceMethod(cls, sel, imp, method_getTypeEncoding(method))
        panelLog("首击直达已接管: \(NSStringFromClass(cls))")
    }

    private func tick() {
        patchFirstMouseDeep(webView)
        if isConnected {
            refresh()
        } else if !isConnecting, Date().timeIntervalSince(lastConnectAttempt) > 1.5 {
            discover()
        }
    }

    private func discover() {
        lastConnectAttempt = Date()
        guard let url = URL(string: "http://127.0.0.1:9222/json/list") else { return }
        isConnecting = true
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self else { return }
            var wsURL: String?
            if let data,
               let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                for item in list {
                    if let pageURL = item["url"] as? String,
                       pageURL.contains("editor.html"),
                       let raw = item["webSocketDebuggerUrl"] as? String {
                        wsURL = raw
                        break
                    }
                }
            }
            DispatchQueue.main.async {
                if let raw = wsURL, let ws = URL(string: raw) {
                    self.cdp.connect(ws)
                } else {
                    self.isConnecting = false
                    self.isConnected = false
                    self.pushDisconnected()
                }
            }
        }.resume()
    }

    private func refresh() {
        cdp.evaluate("JSON.stringify((window.__xmindStyleSlots && window.__xmindStyleSlots.info()) || {})") {
            [weak self] value in
            guard let self else { return }
            guard
                let value,
                let data = value.data(using: .utf8),
                var state = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                self.isConnected = false
                self.pushDisconnected()
                return
            }
            state["connected"] = true
            self.push(state)
        }
    }

    private func push(_ state: [String: Any]) {
        guard
            let data = try? JSONSerialization.data(withJSONObject: state),
            let json = String(data: data, encoding: .utf8)
        else { return }
        let slots = (state["slots"] as? [Any]) ?? []
        let filled = slots.filter { !($0 is NSNull) }.count
        let selection = (state["selection"] as? [String: Any])?["count"] as? Int ?? 0
        let stamp = "connected=\(state["connected"] ?? false) filled=\(filled) selection=\(selection)"
        if stamp != lastPushedStamp {
            lastPushedStamp = stamp
            panelLog("状态 \(stamp)")
        }
        webView.evaluateJavaScript("window.__pushState(\(json))", completionHandler: nil)
    }

    private func pushDisconnected() {
        push(["connected": false, "slots": [], "selection": ["type": "none", "count": 0]])
    }

    // MARK: JS 消息

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard
            let body = message.body as? [String: Any],
            let type = body["type"] as? String
        else { return }
        let slot = (body["slot"] as? Int) ?? 0

        switch type {
        case "apply":
            guard isConnected else { return }
            cdp.evaluate("window.__xmindStyleSlots && window.__xmindStyleSlots.apply(\(slot + 1))") { _ in }
            after(0.45) { self.refresh() }
        case "save":
            guard isConnected else { return }
            cdp.evaluate("window.__xmindStyleSlots && window.__xmindStyleSlots.save(\(slot + 1))") { _ in }
            after(0.45) { self.refresh() }
        case "clear":
            guard isConnected else { return }
            cdp.evaluate("window.__xmindStyleSlots && window.__xmindStyleSlots.clearSlot(\(slot))") { _ in }
            after(0.25) { self.refresh() }
        case "dragStart":
            beginDrag()
        case "resizeStart":
            beginResize()
        case "quit":
            NSApp.terminate(nil)
        default:
            break
        }
    }

    private func after(_ seconds: Double, _ block: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: block)
    }

    // MARK: 拖动

    private func ensureGestureMonitor() {
        guard gestureMonitor == nil else { return }
        gestureMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            guard let self else { return event }
            if self.resizing {
                if event.type == .leftMouseUp {
                    self.resizing = false
                    return nil
                }
                self.stepResize()
                return nil
            }
            if self.dragging {
                if event.type == .leftMouseUp {
                    self.dragging = false
                    return nil
                }
                self.stepDrag()
                return nil
            }
            return event
        }
    }

    private func beginDrag() {
        let mouse = NSEvent.mouseLocation
        dragOffset = NSPoint(
            x: mouse.x - panel.frame.origin.x,
            y: mouse.y - panel.frame.origin.y
        )
        dragging = true
        ensureGestureMonitor()
    }

    private func beginResize() {
        resizeOrigin = NSEvent.mouseLocation
        resizeStartFrame = panel.frame
        resizing = true
        ensureGestureMonitor()
        panelLog("开始缩放 起点=\(resizeOrigin) 起始frame=\(resizeStartFrame)")
    }

    private func stepDrag() {
        let now = NSEvent.mouseLocation
        panel.setFrameOrigin(NSPoint(x: now.x - dragOffset.x, y: now.y - dragOffset.y))
    }

    // 以左上角为锚点，向右下角拖拽改变尺寸
    private func stepResize() {
        let now = NSEvent.mouseLocation
        let dx = now.x - resizeOrigin.x
        let dy = now.y - resizeOrigin.y
        let newW = max(panel.minSize.width, min(panel.maxSize.width, resizeStartFrame.width + dx))
        let newH = max(panel.minSize.height, min(panel.maxSize.height, resizeStartFrame.height - dy))
        var frame = resizeStartFrame
        frame.origin.y = resizeStartFrame.origin.y + (resizeStartFrame.height - newH)
        frame.size = NSSize(width: newW, height: newH)
        panel.setFrame(frame, display: true)
    }
}

// MARK: - 入口

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: PanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.local.xmindstylepanel"
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0 != NSRunningApplication.current }
        if !others.isEmpty {
            panelLog("已有面板在运行，本次退出")
            NSApp.terminate(nil)
            return
        }
        let c = PanelController()
        controller = c
        c.start()
    }
}

let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
app.setActivationPolicy(.accessory)
app.run()
