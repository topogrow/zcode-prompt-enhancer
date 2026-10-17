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
        // 普通窗口层级，取消强制全局置顶，正常参与调度中心 (Mission Control) 平铺
        self.level = .normal
        self.hidesOnDeactivate = false
        self.collectionBehavior = [.managed, .participatesInCycle, .fullScreenPrimary]
        
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = false
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        
        // 最小尺寸放宽至 260px
        self.minSize = NSSize(width: 260, height: 280)
        
        // 隐藏原生左上角控制按钮，由顶栏统一样式接管
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true
    }
    
    override var canBecomeKey: Bool {
        return true
    }
    
    override var canBecomeMain: Bool {
        return true
    }
}

// 探测目标工作区 (如 ZCode) 窗口坐标与尺寸
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
        
        // 1. 窗口原生平滑拖动
        if message.name == "startWindowDrag" {
            if let currentEvent = NSApp.currentEvent {
                panel.performDrag(with: currentEvent)
            }
        }
        
        // 2. 动态切换置顶
        if message.name == "setAlwaysOnTop" {
            if let isPinned = message.body as? Bool {
                panel.level = isPinned ? .floating : .normal
            }
        }
        
        // 3. 动态切换右侧磁贴吸附与联动跟随模式
        if message.name == "setDockMode" {
            if let isDocked = message.body as? Bool {
                delegate?.toggleDockMode(docked: isDocked)
            }
        }
        
        // 4. 标准三点窗口控制
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

class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?
    var statusItem: NSStatusItem?
    var panel: MainWindow?
    var webView: WKWebView?
    var bridge: ScriptBridge?
    
    var normalFrame: NSRect = NSRect(x: 0, y: 0, width: 520, height: 440)
    var isDocked: Bool = false
    var dockTrackingTimer: Timer?
    var serverProcess: Process?
    
    // 磁贴跟随降频状态变量
    private var lastTargetFrame: NSRect? = nil
    private var staticTickCount: Int = 0
    private var isHighRate: Bool = true
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        
        // 1. 注入标准 macOS 应用程序菜单 (激活 Cmd+C / Cmd+V / Cmd+X / Cmd+A / Cmd+Z)
        setupMainMenu()
        
        // 2. 自管理拉起内置本地 Node 服务
        startEmbeddedServerIfNeeded()
        
        // 3. 设置状态栏常驻图标 (使用规范的 isTemplate 矢量模板图标，完美适配刘海屏与系统主题)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = createTemplateStatusIcon()
            button.imagePosition = .imageOnly
            button.toolTip = "ZCODE提示词润色 (左键显示/隐藏，右键菜单)"
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        // 4. 初始化标准应用窗口
        let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let panelWidth: CGFloat = 520
        let panelHeight: CGFloat = 440
        let initialX = screenRect.maxX - panelWidth - 30
        let initialY = screenRect.maxY - panelHeight - 40
        normalFrame = NSRect(x: initialX, y: initialY, width: panelWidth, height: panelHeight)
        
        panel = MainWindow(contentRect: normalFrame)
        bridge = ScriptBridge(panel: panel, delegate: self)
        
        // 5. 配置 WKWebView 与通信桥接
        let contentController = WKUserContentController()
        contentController.add(bridge!, name: "startWindowDrag")
        contentController.add(bridge!, name: "setAlwaysOnTop")
        contentController.add(bridge!, name: "setDockMode")
        contentController.add(bridge!, name: "closeWindow")
        contentController.add(bridge!, name: "miniaturizeWindow")
        contentController.add(bridge!, name: "zoomWindow")
        contentController.add(bridge!, name: "activateApp")
        
        let config = WKWebViewConfiguration()
        config.userContentController = contentController
        
        webView = WKWebView(frame: panel!.contentView!.bounds, configuration: config)
        webView?.autoresizingMask = [.width, .height]
        webView?.setValue(false, forKey: "drawsBackground")
        
        panel?.contentView?.addSubview(webView!)
        
        // 6. 加载本地服务页面
        if let url = URL(string: "http://127.0.0.1:38921") {
            let request = URLRequest(url: url)
            webView?.load(request)
        }
        
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // 矢量绘制标准 18x18 圆角 Squircle Z 字符菜单栏图标 (等比尺寸、标准圆角、isTemplate自动反色)
    private func createTemplateStatusIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setFillColor(NSColor.black.cgColor)

            let path = CGMutablePath()

            // 1. 标准 15x15 pt 外层圆角 Squircle 底座 (内边距 1.5pt，经典 4.0pt 圆角)
            let squircleRect = CGRect(x: 1.5, y: 1.5, width: 15.0, height: 15.0)
            path.addRoundedRect(in: squircleRect, cornerWidth: 4.0, cornerHeight: 4.0)

            // 2. 居中对称镂空极简 "Z" 字符 (笔画宽度 1.8pt，中心 9.0, 9.0)
            path.move(to: CGPoint(x: 5.0, y: 13.0))       // 顶横条 左上
            path.addLine(to: CGPoint(x: 13.0, y: 13.0))   // 顶横条 右上
            path.addLine(to: CGPoint(x: 13.0, y: 11.2))   // 顶横条 右下
            path.addLine(to: CGPoint(x: 7.8, y: 6.8))     // 斜笔画 右下 (连接底条上方)
            path.addLine(to: CGPoint(x: 13.0, y: 6.8))    // 底横条 右上
            path.addLine(to: CGPoint(x: 13.0, y: 5.0))    // 底横条 右下
            path.addLine(to: CGPoint(x: 5.0, y: 5.0))     // 底横条 左下
            path.addLine(to: CGPoint(x: 5.0, y: 6.8))     // 底横条 左上
            path.addLine(to: CGPoint(x: 10.2, y: 11.2))   // 斜笔画 左上 (连接顶条下方)
            path.addLine(to: CGPoint(x: 5.0, y: 11.2))    // 顶横条 左下
            path.closeSubpath()

            // 3. 采用 Even-Odd 缠绕规则实现负空间镂空效果
            ctx.addPath(path)
            ctx.fillPath(using: .evenOdd)
            return true
        }
        img.isTemplate = true
        return img
    }
    
    // 状态栏图标点击处理 (区分左键切换与右键菜单)
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
            statusItem?.menu = nil // 弹出后清空，保持默认左键单触发动作
        } else {
            togglePanel()
        }
    }
    
    // 配置 macOS 标准主菜单系统
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
    
    // 自启动内置 Node 服务
    private func startEmbeddedServerIfNeeded() {
        let bundlePath = Bundle.main.bundlePath
        let bundledServer = (bundlePath as NSString).appendingPathComponent("Contents/Resources/server/server.js")
        
        var scriptToRun: String? = nil
        if FileManager.default.fileExists(atPath: bundledServer) {
            scriptToRun = bundledServer
        }
        
        guard let serverScript = scriptToRun else { return }
        
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
        proc.arguments = [serverScript]
        try? proc.run()
        serverProcess = proc
    }
    
    // 吸附模式切换与磁贴跟随联动
    func toggleDockMode(docked: Bool) {
        guard let panel = panel else { return }
        isDocked = docked
        
        if docked {
            normalFrame = panel.frame
            updateDockPosition(animated: true)
            startDockTracking()
        } else {
            stopDockTracking()
            panel.setFrame(normalFrame, display: true, animate: true)
        }
    }
    
    // 启动具有智能动态降频的磁贴跟随定时器 (P1 性能优化)
    private func startDockTracking() {
        stopDockTracking()
        isHighRate = true
        staticTickCount = 0
        scheduleTrackingTimer(interval: 0.033) // 初始 30 FPS 极速对齐
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
        
        // 动态判定目标窗口是否处于静止状态
        if let last = lastTargetFrame, let cur = currentTarget,
           abs(last.origin.x - cur.origin.x) < 0.5 &&
           abs(last.origin.y - cur.origin.y) < 0.5 &&
           abs(last.size.width - cur.size.width) < 0.5 &&
           abs(last.size.height - cur.size.height) < 0.5 {
            staticTickCount += 1
            // 若静止超过 1.5 秒 (45 帧)，自动降频至 0.5 秒一次，消除静止时的 CPU 浪费
            if staticTickCount > 45 && isHighRate {
                isHighRate = false
                scheduleTrackingTimer(interval: 0.5)
            }
        } else {
            lastTargetFrame = currentTarget
            staticTickCount = 0
            if !isHighRate {
                isHighRate = true
                scheduleTrackingTimer(interval: 0.033) // 发生移动，立刻恢复 30 FPS 高帧率跟手
            }
        }
        
        updateDockPosition(animated: false)
    }
    
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
            let targetY = max(screenRect.minY, zcode.minY)
            let targetHeight = min(screenRect.height, zcode.height)
            targetFrame = NSRect(x: targetX, y: targetY, width: dockWidth, height: targetHeight)
        } else {
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
    
    // 关键唤醒逻辑：优先还原已最小化窗口，再执行显示/隐藏切换
    @objc func togglePanel() {
        guard let panel = panel else { return }
        
        // 修复关键缺陷：如果已被最小化到 Dock，必须先唤醒还原
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
