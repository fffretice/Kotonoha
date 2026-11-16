import AppKit

@main struct FixtureApp {
    static func main() {
        let app = NSApplication.shared; app.setActivationPolicy(.regular)
        let delegate = FixtureDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
final class FixtureDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var testTimer: Timer?
    var resizeTimer: Timer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu(); let item = NSMenuItem(); menu.addItem(item); let sub = NSMenu(); item.submenu = sub
        sub.addItem(withTitle: "退出试读", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); NSApp.mainMenu = menu
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1100, height: 700), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "言叶试读 · 放課後の約束"; window.minSize = CGSize(width: 800, height: 550)
        window.contentView = StoryView(frame: CGRect(x: 0, y: 0, width: 1100, height: 700))
        window.center(); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(window.contentView); NSApp.activate(ignoringOtherApps: true)
        if CommandLine.arguments.contains("--resize-sequence") {
            resizeTimer = Timer.scheduledTimer(withTimeInterval:4,repeats:false) { [weak self] _ in
                self?.window.setContentSize(CGSize(width:820,height:560))
            }
        }
        if CommandLine.arguments.contains("--test-sequence") {
            testTimer = Timer.scheduledTimer(withTimeInterval: CommandLine.arguments.contains("--fast-test") ? 2.2 : (CommandLine.arguments.contains("--jitter-test") ? 8 : 5), repeats: true) { [weak self] _ in (self?.window.contentView as? StoryView)?.advance() }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
final class StoryView: NSView {
    let scenes: [(String, String)] = [
        ("美咲", "「おかえりなさい。今日は、少し遅かったね。」"),
        ("美咲", "「別に、あなたのことを待っていたわけじゃないんだから。」"),
        ("", "放課後の教室には、まだ彼女の笑い声が残っていた。"),
        ("美咲", "「明日も、ここで会えるかな？ 約束だよ。」"),
        ("選択肢", "一緒に帰ろう\nもう少し、ここにいたい\nまた明日ね")
    ]
    var index = 0, characters = 0
    let fastScenes: [(String,String)] = [
        ("美咲","「お嬢様、ご休憩です。お茶をどうぞ。」"),
        ("美咲","「今日はとてもいい天気ですね。」"),
        ("美咲","「放課後に図書館で待っています。」"),
        ("美咲","「この本を読んだことがありますか。」"),
        ("美咲","「明日の試験は少し心配です。」"),
        ("美咲","「一緒に駅まで歩きませんか。」"),
        ("美咲","「あなたに伝えたいことがあります。」"),
        ("美咲","「夕焼けがとても綺麗ですね。」"),
        ("美咲","「もう少しここで話しましょう。」"),
        ("美咲","「約束を忘れないでくださいね。」"),
        ("美咲","「また明日ここで会いましょう。」"),
        ("美咲","「今日もありがとうございました。」")
    ]
    var activeScenes: [(String,String)] { CommandLine.arguments.contains("--fast-test") ? fastScenes : scenes }
    var noisePhase = 0
    var noiseTimer: Timer?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if CommandLine.arguments.contains("--jitter-test"), noiseTimer == nil {
            noiseTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
                self?.noisePhase += 1; self?.needsDisplay = true
            }
        }
    }
    var typewriter = false
    var timer: Timer?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 || event.keyCode == 36 { advance() }
        else if event.charactersIgnoringModifiers?.lowercased() == "t" { typewriter.toggle(); resetTyping() }
        else if event.keyCode == 123 { index = (index + activeScenes.count - 1) % activeScenes.count; resetTyping() }
    }
    override func mouseDown(with event: NSEvent) { advance() }
    func advance() {
        if typewriter && characters < activeScenes[index].1.count { characters = activeScenes[index].1.count; timer?.invalidate(); needsDisplay = true; return }
        if CommandLine.arguments.contains("--fast-test"), index == activeScenes.count - 1 { return }
        index = (index + 1) % activeScenes.count; resetTyping()
    }
    func resetTyping() {
        timer?.invalidate(); characters = typewriter ? 0 : activeScenes[index].1.count
        if typewriter { timer = Timer.scheduledTimer(withTimeInterval: 0.065, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }; self.characters += 1; self.needsDisplay = true
            if self.characters >= self.activeScenes[self.index].1.count { t.invalidate() }
        } }
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        let w = bounds.width, h = bounds.height
        let gradient = NSGradient(starting: NSColor(calibratedRed: 0.18, green: 0.26, blue: 0.38, alpha: 1), ending: NSColor(calibratedRed: 0.96, green: 0.69, blue: 0.49, alpha: 1))!
        gradient.draw(in: bounds, angle: -90)
        // A small native, vector-drawn sunset classroom: no external art or copyrighted game content.
        let sun = NSBezierPath(ovalIn: CGRect(x: w*0.64, y: h*0.53, width: 95, height: 95)); NSColor(calibratedRed: 1, green: 0.89, blue: 0.66, alpha: 0.8).setFill(); sun.fill()
        NSColor(calibratedRed: 0.18, green: 0.25, blue: 0.29, alpha: 0.6).setFill()
        let hills = NSBezierPath(); hills.move(to: CGPoint(x: 0, y: h*0.4)); hills.curve(to: CGPoint(x: w, y: h*0.43), controlPoint1: CGPoint(x: w*0.3, y: h*0.68), controlPoint2: CGPoint(x: w*0.5, y: h*0.23)); hills.line(to: CGPoint(x:w,y:0)); hills.line(to:.zero); hills.close(); hills.fill()
        NSColor(calibratedRed: 0.08, green: 0.12, blue: 0.17, alpha: 0.85).setFill()
        for x in [w*0.06, w*0.48, w*0.9] { CGRect(x:x,y:h*0.28,width:14,height:h*0.72).fill() }
        CGRect(x:0,y:h*0.47,width:w,height:12).fill(); CGRect(x:0,y:h*0.93,width:w,height:18).fill()
        NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.18, alpha: 1).setFill(); CGRect(x:0,y:0,width:w,height:h*0.29).fill()
        let box = CGRect(x: 36, y: 50, width: w-72, height: 160)
        NSColor(calibratedRed: 0.055, green: 0.075, blue: 0.12, alpha: 1).setFill(); NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10).fill()
        NSColor(calibratedRed: 0.7, green: 0.77, blue: 0.83, alpha: 0.5).setStroke(); NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10).stroke()
        let a: [NSAttributedString.Key: Any] = [.font: NSFont(name:"HiraginoSans-W3",size:26) ?? NSFont.systemFont(ofSize:26), .foregroundColor:NSColor.white]
        let speaker: [NSAttributedString.Key: Any] = [.font:NSFont.systemFont(ofSize:20,weight:.medium), .foregroundColor:NSColor(calibratedRed:0.56,green:0.87,blue:0.8,alpha:1)]
        (activeScenes[index].0 as NSString).draw(at: CGPoint(x: 58,y: 220), withAttributes:speaker)
        var text = typewriter ? String(activeScenes[index].1.prefix(characters)) : activeScenes[index].1
        if CommandLine.arguments.contains("--jitter-test") {
            if noisePhase % 2 == 0 { text = text.replacingOccurrences(of:"。",with:"．").replacingOccurrences(of:"、",with:" ") }
            ((noisePhase % 2 == 0 ? "美咲" : "美吹") as NSString).draw(at:CGPoint(x:w-120,y:66),withAttributes:speaker)
        }
        (text as NSString).draw(with: box.insetBy(dx: 24,dy: 21), options: [.usesLineFragmentOrigin,.usesFontLeading], attributes:a)
        let title: [NSAttributedString.Key: Any] = [.font:NSFont.systemFont(ofSize:13,weight:.medium), .foregroundColor:NSColor.white.withAlphaComponent(0.8)]
        ("放課後の約束   /   KOTONOHA ORIGINAL TEST SCENE" as NSString).draw(at:CGPoint(x:36,y:h-45),withAttributes:title)
        ("点击 / 空格：下一句    ←：上一句    T：逐字显示 \(typewriter ? "开" : "关")    ·    \(index+1) / \(activeScenes.count)" as NSString).draw(at:CGPoint(x:36,y:20),withAttributes:title)
    }
}
