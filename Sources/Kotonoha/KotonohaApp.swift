import AppKit
import SwiftUI
import Carbon

@main struct KotonohaApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    var window: NSWindow!
    var statusItem: NSStatusItem!
    var hotkeys: [EventHotKeyRef] = []
    var eventHandler: EventHandlerRef?
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--profile-timing-test") {
            NSApp.setActivationPolicy(.prohibited)
            Task { await Diagnostics.profileTimingTest(model:model); NSApp.terminate(nil) }
            return
        }
        if CommandLine.arguments.contains("--dialogue-append-test") {
            NSApp.setActivationPolicy(.prohibited)
            Task { await Diagnostics.dialogueAppendTest(model:model); NSApp.terminate(nil) }
            return
        }
        if CommandLine.arguments.contains("--typewriter-test") {
            NSApp.setActivationPolicy(.prohibited)
            Task { await Diagnostics.typewriterTest(model:model); NSApp.terminate(nil) }
            return
        }
        if CommandLine.arguments.contains("--resize-test") {
            NSApp.setActivationPolicy(.prohibited)
            Task { await Diagnostics.resizeTest(model:model); NSApp.terminate(nil) }
            return
        }
        if CommandLine.arguments.contains("--recording-replay-test") {
            NSApp.setActivationPolicy(.prohibited)
            Task { await Diagnostics.recordingReplayTest(model:model); NSApp.terminate(nil) }
            return
        }
        if CommandLine.arguments.contains("--visual-text-test") {
            NSApp.setActivationPolicy(.prohibited)
            Task { await Diagnostics.visualTextTest(model:model); NSApp.terminate(nil) }
            return
        }
        if CommandLine.arguments.contains("--presentation-test") {
            NSApp.setActivationPolicy(.prohibited)
            Task { await Diagnostics.presentationTest(model:model); NSApp.terminate(nil) }
            return
        }
        if CommandLine.arguments.contains("--layout-test") {
            NSApp.setActivationPolicy(.prohibited)
            Task { await Diagnostics.layoutTest(model: model); NSApp.terminate(nil) }
            return
        }
        if CommandLine.arguments.contains("--pipeline-test") {
            NSApp.setActivationPolicy(.prohibited)
            Task { await Diagnostics.pipelineTest(model: model); NSApp.terminate(nil) }
            return
        }
        if CommandLine.arguments.contains("--screen-test") {
            NSApp.setActivationPolicy(.prohibited)
            Task { await Diagnostics.screenTest(model: model); NSApp.terminate(nil) }
            return
        }
        if CommandLine.arguments.contains("--diagnose") {
            NSApp.setActivationPolicy(.prohibited)
            Task { await Diagnostics.run(model: model); NSApp.terminate(nil) }
            return
        }
        buildMenu()
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1080, height: 790), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.sharingType = .none
        window.title = "言叶 Kotonoha"; window.minSize = CGSize(width: 1000, height: 720)
        window.isReleasedWhenClosed = false; window.titlebarAppearsTransparent = true
        window.contentView = NSHostingView(rootView: MainView(model: model, engine: model.engine))
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "言"
        let menu = NSMenu()
        menu.addItem(withTitle: "打开言叶", action: #selector(showWindow), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "开始 / 暂停翻译  ⌃⌥T", action: #selector(toggle), keyEquivalent: "")
        menu.addItem(withTitle: "重新框选  ⌃⌥R", action: #selector(selectRegion), keyEquivalent: "")
        menu.addItem(withTitle: "显示 / 隐藏译文  ⌃⌥H", action: #selector(peek), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出言叶", action: #selector(quit), keyEquivalent: "")
        for item in menu.items { item.target = self }; statusItem.menu = menu
        registerHotkeys()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.model.stop(); self?.model.region = nil; self?.model.status = "显示器布局已变化，请重新框选" }
        }

    }
    func buildMenu() {
        let root = NSMenu(); let appItem = NSMenuItem(); root.addItem(appItem)
        let m = NSMenu(); appItem.submenu = m
        m.addItem(withTitle: "关于言叶", action: #selector(about), keyEquivalent: "").target = self
        m.addItem(.separator()); m.addItem(withTitle: "隐藏言叶", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        m.addItem(withTitle: "退出言叶", action: #selector(quit), keyEquivalent: "q").target = self
        let editItem = NSMenuItem(); root.addItem(editItem); let edit = NSMenu(title: "编辑"); editItem.submenu = edit
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let helpItem = NSMenuItem(); root.addItem(helpItem)
        let help = NSMenu(title:"帮助"); helpItem.submenu = help
        help.addItem(withTitle:"言叶使用说明",action:#selector(showHelp),keyEquivalent:"").target = self
        NSApp.mainMenu = root
    }
    func registerHotkeys() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, data -> OSStatus in
            guard let event, let data else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            let delegate = Unmanaged<AppDelegate>.fromOpaque(data).takeUnretainedValue()
            MainActor.assumeIsolated {
                switch id.id { case 1: delegate.toggle(); case 2: delegate.selectRegion(); case 3: delegate.peek(); default: break }
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        for (id, key) in [(1, kVK_ANSI_T), (2, kVK_ANSI_R), (3, kVK_ANSI_H)] {
            var ref: EventHotKeyRef?
            let result = RegisterEventHotKey(UInt32(key), UInt32(controlKey | optionKey), EventHotKeyID(signature: 0x4B4F544F, id: UInt32(id)), GetApplicationEventTarget(), 0, &ref)
            if result == noErr, let ref { hotkeys.append(ref) }
            else { model.error = "部分全局快捷键已被占用，可通过菜单栏控制翻译" }
        }
    }
    @objc func showWindow() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func toggle() { model.toggle() }
    @objc func selectRegion() { model.chooseRegion() }
    @objc func peek() { model.peek.toggle() }
    @objc func quit() { NSApp.terminate(nil) }
    @objc func showHelp() {
        if let url = Bundle.main.url(forResource:"使用说明",withExtension:"txt") { NSWorkspace.shared.open(url) }
    }
    @objc func about() { NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "言叶 Kotonoha", .applicationVersion: Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "0.6.0", .credits: NSAttributedString(string: "本地日中视觉小说翻译\nVision OCR · Qwen3 · llama.cpp\n画面及原文不上传")]) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown(); for hotkey in hotkeys { UnregisterEventHotKey(hotkey) }; if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}
