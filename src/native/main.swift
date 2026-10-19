import Cocoa
import WebKit
import CoreGraphics

class MainWindow: NSWindow {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.level = .normal
        self.hidesOnDeactivate = false
        self.collectionBehavior = [.managed, .participatesInCycle, .fullScreenPrimary]
        
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = false
        // 恢复原生通透高级质感与自适应毛玻璃通道
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        
        self.minSize = NSSize(width: 260, height: 280)
        
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true
    }
    
    // 关键修复 2：重写 contentRect / frameRect，明确告知调度中心 (Mission Control) 视觉内容 100% 充满 Frame，消除 28pt 标题栏扣减导致的纵向压扁
    override func contentRect(forFrameRect frameRect: NSRect) -> NSRect {
        return frameRect
    }
    
    override func frameRect(forContentRect contentRect: NSRect) -> NSRect {
        return contentRect
    }
    
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
}

// 探测目标工作区 (如 ZCode, Cursor, VS Code) 窗口坐标与尺寸
func getZCodeWindowFrame() -> NSRect? {
    let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 900

    for win in windowList {
        guard let owner = win[kCGWindowOwnerName as String] as? String,
              owner == "ZCode" || owner == "Cursor" || owner == "Code",
              let bounds = win[kCGWindowBounds as String] as? [String: Any],
              let x = bounds["X"] as? CGFloat,
              let y = bounds["Y"] as? CGFloat,
              let width = bounds["Width"] as? CGFloat,
              let height = bounds["Height"] as? CGFloat,
              width > 200 && height > 200 else { continue }

        let appKitY = primaryScreenHeight - (y + height)
        return NSRect(x: x, y: appKitY, width: width, height: height)
    }
    return nil
}

class ScriptBridge: NSObject, WKScriptMessageHandler {
    weak var panel: MainWindow?
    weak var delegate: AppDelegate?
    
    init(panel: MainWindow?, delegate: AppDelegate?) {
        self.panel = panel
        self.delegate = delegate
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let panel = self.panel else { return }
        
        if message.name == "startWindowDrag" {
            if let currentEvent = NSApp.currentEvent {
                panel.performDrag(with: currentEvent)
            }
        }
        
        if message.name == "setAlwaysOnTop" {
            if let isPinned = message.body as? Bool {
                panel.level = isPinned ? .floating : .normal
            }
        }
        
        if message.name == "setDockMode" {
            if let isDocked = message.body as? Bool {
                delegate?.toggleDockMode(docked: isDocked)
            }
        }
        
        // 原生系统剪贴板直通通道 (零权限弹窗、原生 NSPasteboard 瞬间写入)
        if message.name == "copyToClipboard" {
            if let text = message.body as? String {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }
        
        if message.name == "closeWindow" {
            panel.orderOut(nil)
        }
        if message.name == "miniaturizeWindow" {
            panel.miniaturize(nil)
        }
        if message.name == "zoomWindow" {
            panel.zoom(nil)
        }
        if message.name == "activateApp" {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    static weak var shared: AppDelegate?
    var statusItem: NSStatusItem?
    var panel: MainWindow?
    var webView: WKWebView?
    var bridge: ScriptBridge?
    
    var normalFrame: NSRect = NSRect(x: 0, y: 0, width: 520, height: 440)
    var isDocked: Bool = false
    var dockTrackingTimer: Timer?
    var serverProcess: Process?
    
    private var lastTargetFrame: NSRect? = nil
    private var staticTickCount: Int = 0
    private var isHighRate: Bool = true
    private var retryLoadCount: Int = 0
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        
        // 1. 注入标准主菜单
        setupMainMenu()
        
        // 2. 检查并拉起内置服务
        startEmbeddedServerIfNeeded()
        
        // 3. 设置状态栏常驻图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = createTemplateStatusIcon()
            button.imagePosition = .imageOnly
            button.toolTip = "ZCODE提示词润色 (左键显示/隐藏，右键菜单)"
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        // 4. 初始化主窗口
        let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let panelWidth: CGFloat = 520
        let panelHeight: CGFloat = 440
        let initialX = screenRect.maxX - panelWidth - 30
        let initialY = screenRect.maxY - panelHeight - 40
        normalFrame = NSRect(x: initialX, y: initialY, width: panelWidth, height: panelHeight)
        
        panel = MainWindow(contentRect: normalFrame)
        bridge = ScriptBridge(panel: panel, delegate: self)
        
        // 5. 配置 WKWebView
        let contentController = WKUserContentController()
        contentController.add(bridge!, name: "startWindowDrag")
        contentController.add(bridge!, name: "setAlwaysOnTop")
        contentController.add(bridge!, name: "setDockMode")
        contentController.add(bridge!, name: "copyToClipboard")
        contentController.add(bridge!, name: "closeWindow")
        contentController.add(bridge!, name: "miniaturizeWindow")
        contentController.add(bridge!, name: "zoomWindow")
        contentController.add(bridge!, name: "activateApp")
        
        // 关键修复 3：统一全窗口 Layer Backing 体系，锁定单一渲染根树
        panel?.contentView?.wantsLayer = true
        panel?.contentView?.layerContentsRedrawPolicy = .onSetNeedsDisplay
        
        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        
        webView = WKWebView(frame: panel!.contentView!.bounds, configuration: config)
        webView?.navigationDelegate = self
        webView?.wantsLayer = true
        webView?.autoresizingMask = [.width, .height]
        webView?.setValue(false, forKey: "drawsBackground")
        
        panel?.contentView?.addSubview(webView!)
        
        // 6. 初始加载本地服务页面
        loadServicePage()
        
        // 预先显示主窗口骨架，确保用户点击后立刻有视觉反馈
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func loadServicePage() {
        guard let url = URL(string: "http://127.0.0.1:38921") else { return }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 3.0)
        webView?.load(request)
    }
    
    // 关键生命周期修复：当 Node 刚启动发生连接失败时，自动重试直至成功
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        retryLoadCount += 1
        if retryLoadCount <= 30 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.loadServicePage()
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        retryLoadCount = 0
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // 核心图标修复：纯矢量极简线条 "Z" 字符，透明底座，彻底杜绝实心黑块
    private func createTemplateStatusIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(2.0)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            let path = CGMutablePath()
            path.move(to: CGPoint(x: 4.5, y: 13.5))
            path.addLine(to: CGPoint(x: 13.5, y: 13.5))
            path.addLine(to: CGPoint(x: 4.5, y: 4.5))
            path.addLine(to: CGPoint(x: 13.5, y: 4.5))

            ctx.addPath(path)
            ctx.strokePath()
            return true
        }
        img.isTemplate = true
        return img
    }
    
    @objc func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "显示/隐藏主窗口", action: #selector(togglePanel), keyEquivalent: "")
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "关于 ZCODE提示词润色", action: nil, keyEquivalent: "")
            menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem?.menu = menu
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        } else {
            togglePanel()
        }
    }
    
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: "ZCODE提示词润色")
        appMenu.addItem(withTitle: "关于 ZCODE提示词润色", action: nil, keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "隐藏", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "撤销", action: #selector(UndoManager.undo), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "重做", action: #selector(UndoManager.redo), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        
        let winMenuItem = NSMenuItem()
        mainMenu.addItem(winMenuItem)
        let winMenu = NSMenu(title: "Window")
        winMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        winMenu.addItem(withTitle: "缩放", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        winMenuItem.submenu = winMenu
        
        NSApp.mainMenu = mainMenu
    }
    
    private func startEmbeddedServerIfNeeded() {
        // 先检查端口是否已经在运行，若是则无需重复启动
        let bundlePath = Bundle.main.bundlePath
        let bundledServer = (bundlePath as NSString).appendingPathComponent("Contents/Resources/server/server.js")
        
        guard FileManager.default.fileExists(atPath: bundledServer) else { return }
        
        let possibleNodes = ["/usr/local/bin/node", "/opt/homebrew/bin/node", "/usr/bin/node"]
        var nodeBinary: String? = nil
        for p in possibleNodes {
            if FileManager.default.fileExists(atPath: p) {
                nodeBinary = p
                break
            }
        }
        
        guard let nodePath = nodeBinary else { return }
        
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: nodePath)
        proc.arguments = [bundledServer, "--parent-pid", String(ProcessInfo.processInfo.processIdentifier)]
        try? proc.run()
        serverProcess = proc
    }
    
    func toggleDockMode(docked: Bool) {
        guard let panel = panel else { return }
        if isDocked == docked { return }
        isDocked = docked
        
        if docked {
            // 仅在当前处于普通卡片形态时记录原始几何尺寸，避免被侧栏尺寸污染
            if panel.frame.width >= 360 {
                normalFrame = panel.frame
            }
            updateDockPosition(animated: true)
            startDockTracking()
        } else {
            stopDockTracking()
            let restoreFrame: NSRect
            if normalFrame.width < 360 {
                let screenRect = (panel.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
                restoreFrame = NSRect(x: screenRect.maxX - 520 - 30, y: screenRect.maxY - 440 - 40, width: 520, height: 440)
            } else {
                restoreFrame = normalFrame
            }
            panel.setFrame(restoreFrame, display: true, animate: true)
            panel.invalidateShadow()
        }
    }
    
    private func startDockTracking() {
        stopDockTracking()
        isHighRate = true
        staticTickCount = 0
        scheduleTrackingTimer(interval: 0.033)
    }
    
    private func scheduleTrackingTimer(interval: TimeInterval) {
        dockTrackingTimer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.dockTrackingTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        dockTrackingTimer = timer
    }
    
    private func stopDockTracking() {
        dockTrackingTimer?.invalidate()
        dockTrackingTimer = nil
    }
    
    private func dockTrackingTick() {
        guard panel != nil, isDocked else { return }
        let currentTarget = getZCodeWindowFrame()
        
        if let last = lastTargetFrame, let cur = currentTarget,
           abs(last.origin.x - cur.origin.x) < 0.5 &&
           abs(last.origin.y - cur.origin.y) < 0.5 &&
           abs(last.size.width - cur.size.width) < 0.5 &&
           abs(last.size.height - cur.size.height) < 0.5 {
            staticTickCount += 1
            if staticTickCount > 45 && isHighRate {
                isHighRate = false
                scheduleTrackingTimer(interval: 0.5)
            }
        } else {
            lastTargetFrame = currentTarget
            staticTickCount = 0
            if !isHighRate {
                isHighRate = true
                scheduleTrackingTimer(interval: 0.033)
            }
        }
        
        updateDockPosition(animated: false)
    }
    
    // 恢复 340px 纵向长条形侧栏形态，高度贴合对齐目标窗口（ZCode / Cursor / VS Code）
    private func updateDockPosition(animated: Bool) {
        guard let panel = panel, isDocked else { return }
        let currentScreen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first
        let screenRect = currentScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let dockWidth: CGFloat = 340
        
        let targetFrame: NSRect
        if let zcode = getZCodeWindowFrame() {
            var targetX = zcode.maxX
            if targetX + dockWidth > screenRect.maxX {
                targetX = screenRect.maxX - dockWidth
            }
            // 贴合对齐 ZCode 的可视纵向高度，同时严格限制在当前屏幕工作区内
            let topY = min(screenRect.maxY, zcode.maxY)
            let bottomY = max(screenRect.minY, zcode.minY)
            let targetHeight = max(280.0, min(screenRect.height, topY - bottomY))
            let targetY = max(screenRect.minY, topY - targetHeight)
            targetFrame = NSRect(x: targetX, y: targetY, width: dockWidth, height: targetHeight)
        } else {
            // 未检测到 ZCode 时贴附在屏幕右侧整列
            targetFrame = NSRect(x: screenRect.maxX - dockWidth, y: screenRect.minY, width: dockWidth, height: screenRect.height)
        }
        
        let cur = panel.frame
        if abs(cur.origin.x - targetFrame.origin.x) > 0.5 ||
           abs(cur.origin.y - targetFrame.origin.y) > 0.5 ||
           abs(cur.size.width - targetFrame.size.width) > 0.5 ||
           abs(cur.size.height - targetFrame.size.height) > 0.5 {
            panel.setFrame(targetFrame, display: true, animate: animated)
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        stopDockTracking()
        serverProcess?.terminate()
    }
    
    @objc func togglePanel() {
        guard let panel = panel else { return }
        
        if panel.isMiniaturized {
            panel.deminiaturize(nil)
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        if panel.isVisible && NSApp.isActive {
            panel.orderOut(nil)
        } else {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
