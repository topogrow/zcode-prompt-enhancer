import Cocoa
import WebKit
import CoreGraphics

class MainWindow: NSWindow {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            // 包含 .miniaturizable 支持原生最小化，.titled 与 .resizable 支持拖拽缩放
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // 默认层级为普通应用窗口 (.normal)，取消强制全局置顶，使其能够正常参与 macOS 调度中心平铺缩放
        self.level = .normal
        self.hidesOnDeactivate = false
        // 关键：允许参与窗口周期循环与调度中心平铺管理
        self.collectionBehavior = [.managed, .participatesInCycle, .fullScreenPrimary]
        
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.isMovableByWindowBackground = false
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        
        // 限制窗口最小尺寸放宽至 260px，支持更窄侧边栏形态
        self.minSize = NSSize(width: 260, height: 280)
        
        // 隐藏原生不可控标题栏按钮，由前端顶栏标准的“红黄绿”三点按钮接管精准触发
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

// 探测 ZCode 窗口坐标与尺寸
func getZCodeWindowFrame() -> NSRect? {
    let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 900

    for win in windowList {
        guard let owner = win[kCGWindowOwnerName as String] as? String, owner == "ZCode",
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
        
        // 1. 窗口原生平滑拖拽
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
        
        // 4. macOS 标准三点窗口控制
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
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        
        // 1. 注入标准 macOS 应用程序菜单 (关键：激活 Cmd+C / Cmd+V / Cmd+X / Cmd+A / Cmd+Z)
        setupMainMenu()
        
        // 2. 自管理拉起内置本地 Node 服务
        startEmbeddedServerIfNeeded()
        
        // 3. 设置状态栏常驻图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.title = "✨"
            button.toolTip = "ZCODE提示词润色"
            button.action = #selector(togglePanel)
            button.target = self
        }
        
        // 4. 初始化标准应用窗口 (初始居右上方，尺寸 520 x 440)
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
        if let url = URL(string: "http://localhost:38921") {
            let request = URLRequest(url: url)
            webView?.load(request)
        }
        
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // 配置 macOS 标准主菜单系统 (彻底激活系统级快捷键通道)
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        
        // 应用程序主菜单
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: "ZCODE提示词润色")
        appMenu.addItem(withTitle: "关于 ZCODE提示词润色", action: nil, keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "隐藏", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        
        // 编辑菜单 (核心：负责转发 Cmd+C, Cmd+V, Cmd+X, Cmd+A, Cmd+Z 到 WKWebView)
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
        
        // 窗口菜单
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
    
    // 启动 30 FPS 轻量跟随定时器
    private func startDockTracking() {
        stopDockTracking()
        let timer = Timer(timeInterval: 0.033, repeats: true) { [weak self] _ in
            self?.updateDockPosition(animated: false)
        }
        RunLoop.main.add(timer, forMode: .common)
        dockTrackingTimer = timer
    }
    
    private func stopDockTracking() {
        dockTrackingTimer?.invalidate()
        dockTrackingTimer = nil
    }
    
    // 实时计算吸附坐标与尺寸 (平滑防抖跟随)
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
    
    @objc func togglePanel() {
        guard let panel = panel else { return }
        if panel.isVisible {
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
// 设置为标准独立桌面应用，参与系统调度中心多任务与窗口切换
app.setActivationPolicy(.regular)
app.run()
