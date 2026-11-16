import AppKit
import TranslationCore
import ScreenCaptureKit

@MainActor extension Diagnostics {
    static func dialogueAppendTest(model:AppModel) async {
        var report:[String:Any]=[:]
        let originalMode=model.timingMode
        defer {model.timingMode=originalMode}
        do {
            model.engine.load()
            for _ in 0..<240 {if model.engine.ready || !model.engine.loading {break};try await Task.sleep(nanoseconds:500_000_000)}
            guard model.engine.ready else {throw AppFailure(model.engine.status)}
            model.timingMode = .typewriter
            // Real recording: the translated first row must survive OCR spelling changes and appended rows.
            var frames:[(CGImage,[RecognizedLine])]=[]
            for second in [16,18,20,23,27,34] {
                let path=String(format:"work/video-review/frame-%06.2f.jpg",Double(second))
                guard let image=NSImage(contentsOfFile:path)?.cgImage(forProposedRect:nil,context:nil,hints:nil) else {throw AppFailure("Missing recording frame")}
                let lines=try await CaptureService.recognize(image,glossary:"").filter {$0.rect.minX < 0.15 && $0.rect.midY < 0.55}
                frames.append((image,lines))
            }
            let size=CGSize(width:946,height:302)
            model.beginFrameReplay(region:CaptureRegion(displayID:0,screenFrame:CGRect(origin:.zero,size:size),rect:CGRect(origin:.zero,size:size),scale:2,displayName:"Dialogue recording"))
            for _ in 0..<100 {
                model.acceptReplayFrame(frames[0].1,image:frames[0].0)
                if !model.coveredSourceKeys.isEmpty {break}
                try await Task.sleep(nanoseconds:100_000_000)
            }
            guard !model.coveredSourceKeys.isEmpty else {throw AppFailure("Recording prefix translation missing")}
            let prefix=model.translation
            var recordingHeld:[Bool]=[]
            for frame in frames.dropFirst().dropLast() {
                model.acceptReplayFrame(frame.1,image:frame.0)
                recordingHeld.append(model.translation == prefix)
                try await Task.sleep(nanoseconds:80_000_000)
            }
            report["recordingAppendFramesPreservePrefix"]=recordingHeld
            guard recordingHeld.allSatisfy({$0}) else {throw AppFailure("Recorded appended rows cleared the displayed prefix")}
            model.acceptReplayFrame(frames.last!.1,image:frames.last!.0)
            guard model.translation.isEmpty else {throw AppFailure("Next dialogue kept the previous page")}
            report["recordingNextPageClearsOldTranslation"]=true

            // A slow request can finish after the next rows have started typing. Its own source must still appear.
            func image(_ text:String)->CGImage {
                let ctx=CGContext(data:nil,width:1800,height:400,bitsPerComponent:8,bytesPerRow:7200,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
                NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:ctx,flipped:false)
                NSColor.white.setFill();CGRect(x:0,y:0,width:1800,height:400).fill()
                let attrs:[NSAttributedString.Key:Any]=[.font:NSFont(name:"HiraginoSans-W3",size:32)!, .foregroundColor:NSColor.black]
                for (i,row) in text.components(separatedBy:"\n").enumerated() {(row as NSString).draw(at:CGPoint(x:55,y:300-i*42),withAttributes:attrs)}
                NSGraphicsContext.restoreGraphicsState();return ctx.makeImage()!
            }
            let source="通信魔法みたいなもので、思考を読み取られているとか。"
            let tail="体内に、音を拾うマジックアイテムを埋め込まれているとか。\nそういう可能性もある……ちょっと楽観的すぎたかもしれない。"
            let first=image(source), lines=try await CaptureService.recognize(first,glossary:"")
            let canvas=CGSize(width:900,height:200)
            model.beginFrameReplay(region:CaptureRegion(displayID:0,screenFrame:CGRect(origin:.zero,size:canvas),rect:CGRect(origin:.zero,size:canvas),scale:2,displayName:"Late prefix result"))
            for _ in 0..<50 {
                model.acceptReplayFrame(lines,image:first)
                if model.status == "正在本地翻译…" {break}
                try await Task.sleep(nanoseconds:80_000_000)
            }
            guard model.status == "正在本地翻译…" else {throw AppFailure("Prefix request did not start")}
            let began=ProcessInfo.processInfo.systemUptime
            var firstVisible:Double?, heldImage:Data?, heldRect:CGRect?, dropouts=0, paintChanges=0, completedUpdates=0
            var paintedKeys=Set<String>()
            var finalImage=first, finalLines=lines
            for count in 1...tail.count {
                finalImage=image(source+"\n"+String(tail.prefix(count)))
                finalLines=try await CaptureService.recognize(finalImage,glossary:"")
                model.acceptReplayFrame(finalLines,image:finalImage)
                if !model.coveredSourceKeys.isEmpty {
                    if firstVisible == nil {firstVisible=ProcessInfo.processInfo.systemUptime;heldRect=model.overlay.presentationRects.first}
                    if let render=model.overlay.renderedImage(), let data=NSBitmapImageRep(cgImage:render).representation(using:.png,properties:[:]) {
                        if paintedKeys == model.coveredSourceKeys {
                            if let heldImage, heldImage != data {paintChanges+=1}
                        } else if !paintedKeys.isEmpty {completedUpdates+=1}
                        heldImage=data;paintedKeys=model.coveredSourceKeys
                    }
                } else if firstVisible != nil {dropouts+=1}
                try await Task.sleep(nanoseconds:80_000_000)
            }
            let hold=ProcessInfo.processInfo.systemUptime-(firstVisible ?? ProcessInfo.processInfo.systemUptime)
            report["latePrefixAppearedWhileTyping"]=firstVisible != nil
            report["continuousPrefixSeconds"]=hold
            report["appendOverlayDropouts"]=dropouts
            report["prefixPaintChanges"]=paintChanges
            report["completedPrefixUpdates"]=completedUpdates
            report["typingDurationSeconds"]=ProcessInfo.processInfo.systemUptime-began
            guard firstVisible != nil,hold > 5,dropouts == 0,paintChanges == 0 else {throw AppFailure("Late prefix did not remain readable at its frozen position")}
            let fullKey=OCRText.key(TextTools.signature(finalLines))
            for _ in 0..<120 {
                model.acceptReplayFrame(finalLines,image:finalImage)
                if model.coveredSourceKeys.contains(fullKey) {break}
                try await Task.sleep(nanoseconds:100_000_000)
            }
            guard model.coveredSourceKeys.contains(fullKey) else {throw AppFailure("Full appended dialogue was not translated separately")}
            report["fullDialogueTranslatedWithoutPrefixCacheReuse"]=true
            if let heldRect, let expanded=model.overlay.presentationRects.first {
                let anchored=abs(heldRect.minX-expanded.minX)<1 && abs(heldRect.maxY-expanded.maxY)<1
                report["expandedCoverKeepsTopLeftAnchor"]=anchored
                guard anchored else {throw AppFailure("Expanded paragraph moved its reading anchor")}
            } else {throw AppFailure("Missing paragraph paint geometry")}
            report["completeTranslation"]=model.translation
            let next=image("内通者……なるほどなぁ。"), nextLines=try await CaptureService.recognize(next,glossary:"")
            model.acceptReplayFrame(nextLines,image:next)
            guard model.translation.isEmpty else {throw AppFailure("New dialogue failed to clear old page")}
            report["nextDialogueClearsPageImmediately"]=true
            report["passed"]=true
        } catch {report["passed"]=false;report["error"]=error.localizedDescription}
        model.shutdown()
        try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:outputFolder.appendingPathComponent("dialogue-append-test.json"))
    }
}

@MainActor enum Diagnostics {
    static var outputFolder: URL {
        if let path = ProcessInfo.processInfo.environment["KOTONOHA_DIAGNOSTICS_DIR"] { return URL(fileURLWithPath:path) }
        return Bundle.main.bundleURL.deletingLastPathComponent()
    }
    static func run(model: AppModel) async {
        var report: [String: Any] = ["date": ISO8601DateFormatter().string(from: Date()), "system": ProcessInfo.processInfo.operatingSystemVersionString]
        let target = outputFolder.appendingPathComponent("diagnostics.json")
        do {
            let image = fixtureImage()
            let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
            try data.write(to: target.deletingLastPathComponent().appendingPathComponent("ocr-fixture.png"))
            let began = ProcessInfo.processInfo.systemUptime
            let lines = try await CaptureService.recognize(image, glossary: "")
            report["ocrSeconds"] = ProcessInfo.processInfo.systemUptime - began
            report["recognized"] = lines.map { $0.text }
            guard lines.count >= 2 else { throw AppFailure("OCR fixture did not recognize expected dialogue") }
            model.engine.load()
            for _ in 0..<240 {
                if model.engine.ready || (!model.engine.loading) { break }
                try await Task.sleep(nanoseconds: 500_000_000)
            }
            guard model.engine.ready else { throw AppFailure(model.engine.status) }
            var trials: [[String: Any]] = []
            for source in ["「おかえりなさい。今日は、少し遅かったね。」", "「別に、あなたのことを待っていたわけじゃないんだから。」", "放課後の教室には、まだ彼女の笑い声が残っていた。"] {
                let t = ProcessInfo.processInfo.systemUptime
                let result = try await model.engine.translate([source], context: [], glossary: "")
                trials.append(["ja": source, "zh": result, "seconds": ProcessInfo.processInfo.systemUptime - t])
            }
            report["translations"] = trials
            report["passed"] = true
        } catch { report["passed"] = false; report["error"] = error.localizedDescription }
        model.shutdown()
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: target) }
    }
    static func fixtureImage() -> CGImage {
        let width = 1400, height = 400
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSColor(calibratedRed: 0.08, green: 0.1, blue: 0.17, alpha: 1).setFill(); CGRect(x: 0, y: 0, width: width, height: height).fill()
        let a: [NSAttributedString.Key: Any] = [.font: NSFont(name: "HiraginoSans-W3", size: 38) ?? NSFont.systemFont(ofSize: 38), .foregroundColor: NSColor.white]
        ("美咲" as NSString).draw(at: CGPoint(x: 65, y: 285), withAttributes: a)
        ("「おかえりなさい。今日は、少し遅かったね。」" as NSString).draw(at: CGPoint(x: 65, y: 205), withAttributes: a)
        ("窓の外には、夕焼けが静かに広がっていた。" as NSString).draw(at: CGPoint(x: 65, y: 125), withAttributes: a)
        NSGraphicsContext.restoreGraphicsState(); return ctx.makeImage()!
    }
}

@MainActor extension Diagnostics {
    static func screenTest(model: AppModel) async {
        let folder = outputFolder
        var report: [String: Any] = ["date": ISO8601DateFormatter().string(from: Date())]
        var demo: NSRunningApplication?
        do {
            let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/试读场景.app")
            demo = try await withCheckedThrowingContinuation { continuation in
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { app, error in
                    if let app { continuation.resume(returning: app) } else { continuation.resume(throwing: error ?? AppFailure("无法启动试读")) }
                }
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let w = content.windows.first(where: { $0.owningApplication?.bundleIdentifier == "app.kotonoha.fixture" }),
                  let screen = NSScreen.screens.first(where: { screen in
                      let top = NSScreen.screens[0].frame.maxY
                      return screen.frame.contains(CGPoint(x: w.frame.midX, y: top-w.frame.midY))
                  }), let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { throw AppFailure("无法定位试读窗口") }
            let top = NSScreen.screens[0].frame.maxY
            // The fixture's dialogue box is 50...210 pt above the content bottom.
            let frame = CGRect(x: w.frame.minX + 40, y: top - w.frame.maxY + 52, width: w.frame.width - 80, height: 155)
            let region = CaptureRegion(displayID: id, screenFrame: screen.frame, rect: frame, scale: screen.backingScaleFactor, displayName: screen.localizedName)
            do {
                let f: SCContentFilter
                if CommandLine.arguments.contains("--display-filter"), let display = content.displays.first(where: { $0.displayID == id }) {
                    f = SCContentFilter(display:display,excludingApplications:[],exceptingWindows:[])
                } else { f = SCContentFilter(desktopIndependentWindow:w) }
                report["windowContentRect"] = NSStringFromRect(f.contentRect)
                model.capture.authorize(f, for: region)
            }
            let windowRegion = try CaptureMode.window.region(for:SCContentFilter(desktopIndependentWindow:w),selected:nil)
            guard let fullDisplay = content.displays.first(where:{ $0.displayID == id }) else { throw AppFailure("显示器不可用") }
            let displayFilter = SCContentFilter(display:fullDisplay,excludingApplications:[],exceptingWindows:[])
            let fullRegion = try CaptureMode.fullScreen.region(for:displayFilter,selected:nil)
            let croppedRegion = try CaptureMode.region.region(for:displayFilter,selected:region)
            let modesCorrect = windowRegion.rect.size == w.frame.size && fullRegion.rect.size == screen.frame.size && croppedRegion.rect == region.rect
            report["threeCaptureModeGeometry"] = modesCorrect
            guard modesCorrect else { throw AppFailure("三种捕获模式范围不正确") }
            try await model.capture.prepare(region)
            let image = try await model.capture.image()
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("screen-before.png"))
            let lines = try await CaptureService.recognize(image, glossary: "")
            report["recognized"] = lines.map(\.text)
            guard !lines.isEmpty else { throw AppFailure("试读窗口截图中未识别到日文") }
            model.engine.load()
            for _ in 0..<240 { if model.engine.ready || !model.engine.loading { break }; try await Task.sleep(nanoseconds: 500_000_000) }
            let source = TextTools.signature(lines)
            let translated = try await model.engine.translate([source], context: [], glossary: "")
            let block = TranslationBlock(source: source, translated: translated[0], rect: lines.dropFirst().reduce(lines[0].rect) { $0.union($1.rect) })
            model.overlay.configure(region: region)
            model.overlay.show(blocks: [block], image: image, appearance: model.appearance)
            let rendered = model.overlay.renderedImage()
            if let rendered {
                let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
                ctx.draw(image, in: full); ctx.draw(rendered, in: full)
                try NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("translated-dialogue.png"))
                try NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("overlay-render.png")) }
            try await Task.sleep(nanoseconds: 500_000_000)
            let clean = try await model.capture.image()
            let cleanLines = try await CaptureService.recognize(clean, glossary: "")
            report["recognizedAfterOverlay"] = cleanLines.map(\.text)
            try NSBitmapImageRep(cgImage: clean).representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("capture-after-overlay.png"))
            report["captureExcludesOverlay"] = TextTools.signature(cleanLines) == source
            report["translation"] = translated
            report["overlayIgnoresMouse"] = model.overlay.ignoresMouse
            guard TextTools.signature(cleanLines) == source else { throw AppFailure("覆盖层污染了屏幕识别") }
            report["passed"] = true
        } catch { report["passed"] = false; report["error"] = error.localizedDescription }
        model.shutdown(); demo?.terminate()
        let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try? data?.write(to: folder.appendingPathComponent("screen-test.json"))
    }
}

@MainActor extension Diagnostics {
    static func pipelineTest(model: AppModel) async {
        let folder = outputFolder
        var report: [String: Any] = ["date": ISO8601DateFormatter().string(from: Date())]
        var demo: NSRunningApplication?
        do {
            model.engine.load()
            for _ in 0..<240 { if model.engine.ready || !model.engine.loading { break }; try await Task.sleep(nanoseconds: 500_000_000) }
            guard model.engine.ready else { throw AppFailure(model.engine.status) }
            let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/试读场景.app")
            demo = try await withCheckedThrowingContinuation { continuation in
                let config = NSWorkspace.OpenConfiguration(); config.arguments = CommandLine.arguments.contains("--fast-test") ? ["--test-sequence", "--fast-test"] : (CommandLine.arguments.contains("--jitter-test") ? ["--test-sequence", "--jitter-test"] : ["--test-sequence"]); config.createsNewApplicationInstance = true
                NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
                    if let app { continuation.resume(returning: app) } else { continuation.resume(throwing: error ?? AppFailure("无法启动试读")) }
                }
            }
            try await Task.sleep(nanoseconds: 800_000_000)
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let window = content.windows.first(where: { $0.owningApplication?.processID == demo?.processIdentifier }) else { throw AppFailure("试读窗口未就绪") }
            let top = NSScreen.screens[0].frame.maxY
            let rect = CGRect(x: window.frame.minX+40, y: top-window.frame.maxY+52, width: window.frame.width-80, height: 155)
            guard let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) }), let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { throw AppFailure("无法定位显示器") }
            model.region = CaptureRegion(displayID: id, screenFrame: screen.frame, rect: rect, scale: screen.backingScaleFactor, displayName: screen.localizedName)
            model.capture.authorize(SCContentFilter(desktopIndependentWindow: window), for: model.region!)
            model.start()
            let fast = CommandLine.arguments.contains("--fast-test")
            var firstSeen: [String: Double] = [:], firstVisible: [String: Double] = [:]
            var previousSource = "", previousVisible = false, dropouts = 0
            var holdStart: Double?, longestHold: Double = 0
            let started = ProcessInfo.processInfo.systemUptime
            for _ in 0..<(fast ? 540 : 420) {
                try await Task.sleep(nanoseconds: 50_000_000)
                if !model.running { throw AppFailure(model.error ?? "流程提前停止") }
                let key = OCRText.key(model.source.components(separatedBy:"\n").max(by: { $0.count < $1.count }) ?? ""), now = ProcessInfo.processInfo.systemUptime
                let covered = model.coveredSourceKeys.contains(key)
                if !key.isEmpty {
                    if firstSeen[key] == nil { firstSeen[key] = now }
                    if covered && firstVisible[key] == nil { firstVisible[key] = now }
                    if key == previousSource && previousVisible && !covered { dropouts += 1 }
                }
                if key == previousSource && covered {
                    if let holdStart { longestHold = max(longestHold, now-holdStart) } else { holdStart = now }
                } else { holdStart = nil }
                previousSource = key; previousVisible = covered
            }
            report["testDurationSeconds"] = ProcessInfo.processInfo.systemUptime-started
            report["fastSubtitleIntervalSeconds"] = fast ? 2.2 : (CommandLine.arguments.contains("--jitter-test") ? 8 : 5)
            report["observedSourceCount"] = firstSeen.count
            report["visibleSourceCount"] = firstVisible.count
            report["sameTextOverlayDropouts"] = dropouts
            report["longestContinuousOverlaySeconds"] = longestHold
            if CommandLine.arguments.contains("--jitter-test") {
                guard dropouts == 0, longestHold >= 5 else { throw AppFailure("识别抖动时译文未能持续显示") }
            }
            let delays = firstVisible.compactMap { key,time in firstSeen[key].map { time-$0 } }
            report["ocrToOverlaySeconds"] = delays
            report["timelyVisibleSourceCount"] = delays.filter { $0 < (fast ? 2.2 : 8) }.count
            if fast {
                guard delays.filter({ $0 < 2.2 }).count >= 10 else { throw AppFailure("快速字幕覆盖不足10句") }
                guard dropouts == 0 else { throw AppFailure("原文未变化时覆盖层意外消失") }
            }
            report["history"] = model.history.reversed().map { ["ja": $0.source, "zh": $0.translation, "translationSeconds": $0.seconds] as [String: Any] }
            report["completedDialogues"] = model.history.count
            guard model.history.count >= 3 else { throw AppFailure("自动翻页后完整译文不足三条") }
            model.stop()
            report["overlayRemovedOnStop"] = !model.overlay.isVisible
            guard !model.overlay.isVisible else { throw AppFailure("停止后覆盖层未消失") }
            report["passed"] = true
        } catch { report["passed"] = false; report["error"] = error.localizedDescription }
        model.shutdown(); demo?.terminate()
        let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try? data?.write(to: folder.appendingPathComponent(CommandLine.arguments.contains("--fast-test") ? "fast-subtitle-test.json" : (CommandLine.arguments.contains("--jitter-test") ? "jitter-test.json" : "pipeline-test.json")))
    }
}

@MainActor extension Diagnostics {
    static func layoutTest(model: AppModel) async {
        let folder = outputFolder
        var report: [String: Any] = [:]
        do {
            let size = CGSize(width: 800, height: 1600)
            let ctx = CGContext(data: nil, width: 800, height: 1600, bitsPerComponent: 8, bytesPerRow: 3200, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            NSColor(deviceRed: 0.34, green: 0.38, blue: 0.39, alpha: 1).setFill(); CGRect(origin: .zero, size: size).fill()
            for rect in [CGRect(x: 220,y:1070,width:540,height:90), CGRect(x:220,y:800,width:540,height:135), CGRect(x:220,y:510,width:540,height:90)] {
                NSColor.white.setFill(); NSBezierPath(roundedRect:rect,xRadius:22,yRadius:22).fill()
            }
            let rows: [(String, CGPoint, CGFloat, NSColor)] = [
                ("章節０",CGPoint(x:40,y:1450),30,.white), ("カナエ",CGPoint(x:655,y:1180),20,.white),
                ("入学試験で最下位のカナエさん。",CGPoint(x:245,y:1100),25,.black),
                ("カナエ",CGPoint(x:655,y:955),20,.white),
                ("歌も踊りもできない。",CGPoint(x:245,y:875),25,.black),
                ("転んで泥だらけになった。",CGPoint(x:245,y:837),25,.black),
                ("そんな彼女が笑顔で夢を追う。",CGPoint(x:245,y:540),25,.black)]
            for (text, point, size, color) in rows { (text as NSString).draw(at:point,withAttributes:[.font:NSFont(name:"HiraginoSans-W3",size:size)!, .foregroundColor:color]) }
            NSGraphicsContext.restoreGraphicsState()
            let image = ctx.makeImage()!
            let lines = try await CaptureService.recognize(image, glossary: "")
            let groups = TextLayout.groups(lines, canvas:size)
            report["ocrRows"] = lines.count; report["independentBlocks"] = groups.count
            guard groups.count >= 5, groups.allSatisfy({ $0.map(\.rect).reduce(CGRect.null) { $0.union($1) }.height < 0.12 }) else { throw AppFailure("分散文字被错误合并") }
            model.engine.load()
            for _ in 0..<240 { if model.engine.ready || !model.engine.loading { break }; try await Task.sleep(nanoseconds:500_000_000) }
            let sources = groups.map { $0.map(\.text).joined(separator:"\n") }
            let translations = try await model.engine.translate(sources, context:[], glossary:"")
            let blocks = groups.enumerated().map { i,g in TranslationBlock(source:sources[i],translated:translations[i],rect:g.map(\.rect).reduce(CGRect.null) { $0.union($1) }) }
            let region = CaptureRegion(displayID:0,screenFrame:CGRect(origin:.zero,size:size),rect:CGRect(origin:.zero,size:size),scale:1,displayName:"Test")
            model.overlay.configure(region:region); model.overlay.hidden = true
            model.overlay.show(blocks:blocks,image:image,appearance:model.appearance)
            if let overlay = model.overlay.renderedImage() {
                ctx.draw(overlay,in:CGRect(origin:.zero,size:size))
                try NSBitmapImageRep(cgImage:ctx.makeImage()!).representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("分散对白覆盖测试.png"))
            }
            report["passed"] = true
        } catch { report["passed"] = false; report["error"] = error.localizedDescription }
        model.shutdown()
        try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("layout-test.json"))
    }
}

@MainActor extension Diagnostics {
    static func presentationTest(model: AppModel) async {
        let folder = outputFolder
        var report: [String: Any] = [:]
        do {
            let files = ["work/video-review/first-recording-61.jpg", "work/video-review/first-recording-63.5.jpg"]
            let frames = try files.map { path -> CGImage in
                guard let image = NSImage(contentsOfFile:path)?.cgImage(forProposedRect:nil,context:nil,hints:nil) else { throw AppFailure("缺少录屏回归帧") }
                return image
            }
            let size = CGSize(width:875,height:404)
            let region = CaptureRegion(displayID:0,screenFrame:CGRect(origin:.zero,size:size),rect:CGRect(origin:.zero,size:size),scale:2,displayName:"Recorded regression")
            model.overlay.configure(region:region); model.overlay.hidden = true
            let observations = try await CaptureService.recognize(frames[0],glossary:"")
            let detected = TextLayout.groups(observations,canvas:size).max { a,b in a.map(\.text).joined().count < b.map(\.text).joined().count }
            guard let detected, let line = detected.first else { throw AppFailure("录屏原字幕未识别") }
            let sourceRect = detected.dropFirst().reduce(line.rect) { $0.union($1.rect) }
            let original = [TranslationBlock(source:detected.map(\.text).joined(),translated:"各位摄影工作人员，请多关照。",rect:sourceRect)]
            var settings = OverlayAppearance(); settings.style = .automatic
            model.overlay.show(blocks:original,image:frames[0],appearance:settings)
            let first = model.overlay.renderedImage()!
            let before = NSBitmapImageRep(cgImage:first).representation(using:.png,properties:[:])!
            var jittered = original
            jittered[0].rect = CGRect(x:sourceRect.minX+0.002,y:sourceRect.minY+0.001,width:sourceRect.width+0.02,height:sourceRect.height+0.014)
            model.overlay.show(blocks:jittered,image:frames[1],appearance:settings)
            let after = NSBitmapImageRep(cgImage:model.overlay.renderedImage()!).representation(using:.png,properties:[:])!
            report["sameSentencePixelIdenticalDespiteMovingBackgroundAndOCRBoxes"] = before == after
            guard before == after else { throw AppFailure("同句画面发生变化") }
            let different = original + [TranslationBlock(source:"はい。",translated:"好的。",rect:CGRect(x:0.4,y:0.6,width:0.1,height:0.03))]
            model.overlay.show(blocks:different,image:frames[1],appearance:settings)
            report["fontSizes"] = model.overlay.presentationFonts
            guard model.overlay.presentationFonts.allSatisfy({ $0 == settings.fontSize }) else { throw AppFailure("字号未统一") }
            let ctx = CGContext(data:nil,width:frames[0].width,height:frames[0].height,bitsPerComponent:8,bytesPerRow:frames[0].width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            let full = CGRect(x:0,y:0,width:frames[0].width,height:frames[0].height)
            ctx.draw(frames[0],in:full); ctx.draw(first,in:full)
            try NSBitmapImageRep(cgImage:ctx.makeImage()!).representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("录屏画面稳定覆盖预览.png"))
            report["passed"] = true
        } catch { report["passed"] = false; report["error"] = error.localizedDescription }
        model.shutdown()
        try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:folder.appendingPathComponent("presentation-test.json"))
    }
}

@MainActor extension Diagnostics {
    static func resizeTest(model: AppModel) async {
        var report: [String:Any] = [:]
        var demo: NSRunningApplication?
        do {
            let url=Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/试读场景.app")
            demo = try await withCheckedThrowingContinuation { continuation in
                let config=NSWorkspace.OpenConfiguration();config.arguments=["--resize-sequence"];config.createsNewApplicationInstance=true
                NSWorkspace.shared.openApplication(at:url,configuration:config) { app,error in
                    if let app { continuation.resume(returning:app) } else { continuation.resume(throwing:error ?? AppFailure("无法打开试读")) }
                }
            }
            try await Task.sleep(nanoseconds:500_000_000)
            func window() async throws -> SCWindow {
                let all=try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
                guard let w=all.windows.filter({$0.owningApplication?.processID == demo?.processIdentifier}).max(by:{$0.frame.width*$0.frame.height < $1.frame.width*$1.frame.height}) else { throw AppFailure("未找到试读窗口") };return w
            }
            let first=try await window()
            model.applySelection(SCContentFilter(desktopIndependentWindow:first),mode:.window,selected:nil,resume:false)
            for _ in 0..<150 { if !model.choosingScreen { break }; try await Task.sleep(nanoseconds:50_000_000) }
            guard let firstPreview=model.preview, let firstRegion=model.region, model.error == nil else { throw AppFailure(model.error ?? "首个预览缺失") }
            report["firstPreviewSize"]=NSStringFromSize(firstPreview.size)
            try await Task.sleep(nanoseconds:4_000_000_000)
            let second=try await window()
            guard second.frame.size != first.frame.size else { throw AppFailure("测试窗口未改变大小") }
            model.applySelection(SCContentFilter(desktopIndependentWindow:second),mode:.window,selected:nil,resume:false)
            report["oldPreviewClearedImmediately"]=model.preview == nil
            for _ in 0..<150 { if !model.choosingScreen { break }; try await Task.sleep(nanoseconds:50_000_000) }
            report["streamErrorDetail"] = model.capture.lastStartError
            report["newRegion"] = model.region.map { NSStringFromSize($0.rect.size) }
            guard let preview=model.preview, let region=model.region, model.error == nil else { throw AppFailure(model.error ?? "新预览缺失") }
            report["secondPreviewSize"]=NSStringFromSize(preview.size)
            let changed=region.rect.size != firstRegion.rect.size && preview.size == region.rect.size
            report["previewRefreshedWithoutRestart"]=changed
            guard changed else { throw AppFailure("预览仍使用旧尺寸") }
            report["passed"]=true
        } catch { report["passed"]=false;report["error"]=error.localizedDescription }
        model.shutdown();demo?.terminate()
        let output=outputFolder.appendingPathComponent("resize-test.json")
        try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:output)
    }
    static func visualTextTest(model: AppModel) async {
        var report:[String:Any]=[:]
        do {
            func frame(_ name:String) throws -> CGImage {
                guard let image=NSImage(contentsOfFile:"work/video-review/"+name)?.cgImage(forProposedRect:nil,context:nil,hints:nil) else { throw AppFailure("录屏帧缺失") };return image
            }
            let reference=try frame("frame-063.00.jpg")
            let lines=try await CaptureService.recognize(reference,glossary:"")
            guard let line=lines.max(by:{$0.text.count < $1.text.count}),let fingerprint=SubtitleFingerprint(image:reference,rect:line.rect) else { throw AppFailure("未提取到文字证据") }
            let same=try ["frame-063.50.jpg","frame-064.00.jpg","frame-064.50.jpg"].map { name in
                try SubtitleFingerprint(image:frame(name),rect:line.rect).map { fingerprint.matches($0) } ?? false
            }
            let changed=try ["frame-065.00.jpg","frame-069.00.jpg","frame-070.00.jpg"].map { name in
                try SubtitleFingerprint(image:frame(name),rect:line.rect).map { fingerprint.matches($0) } ?? false
            }
            report["sameGlyphsDespiteOCRErrors"]=same;report["differentSubtitlesMatched"]=changed
            guard same.allSatisfy({$0}),changed.allSatisfy({!$0}) else { throw AppFailure("文字图像区分失败") }
            let size=CGSize(width:875,height:404)
            let region=CaptureRegion(displayID:0,screenFrame:CGRect(origin:.zero,size:size),rect:CGRect(origin:.zero,size:size),scale:2,displayName:"Regression")
            model.overlay.configure(region:region);model.overlay.hidden=true
            let blocks=[TranslationBlock(source:line.text,translated:"多亏你为我制作的旅行手册。",rect:line.rect)]
            model.overlay.show(blocks:blocks,image:reference,appearance:OverlayAppearance())
            let before=NSBitmapImageRep(cgImage:model.overlay.renderedImage()!).representation(using:.png,properties:[:])!
            model.overlay.clear()
            model.overlay.show(blocks:blocks,image:reference,appearance:OverlayAppearance())
            let after=NSBitmapImageRep(cgImage:model.overlay.renderedImage()!).representation(using:.png,properties:[:])!
            report["sameTranslationRedrawnAfterClear"]=before == after
            guard before == after else { throw AppFailure("清除后同句未重绘") }
            try after.write(to:outputFolder.appendingPathComponent("自动背景取色预览.png"))
            report["passed"]=true
        } catch {report["passed"]=false;report["error"]=error.localizedDescription}
        model.shutdown()
        try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:outputFolder.appendingPathComponent("visual-text-test.json"))
    }
}

@MainActor extension Diagnostics {
    static func recordingReplayTest(model: AppModel) async {
        var report:[String:Any]=[:]
        do {
            func frame(_ name:String) throws -> CGImage {
                guard let image=NSImage(contentsOfFile:"work/video-review/"+name)?.cgImage(forProposedRect:nil,context:nil,hints:nil) else { throw AppFailure("缺少录屏帧") };return image
            }
            model.engine.load()
            for _ in 0..<240 { if model.engine.ready || !model.engine.loading { break };try await Task.sleep(nanoseconds:500_000_000) }
            guard model.engine.ready else {throw AppFailure(model.engine.status)}
            let reference=try frame("frame-063.00.jpg")
            let lines=try await CaptureService.recognize(reference,glossary:"")
            guard let body=lines.max(by:{$0.text.count < $1.text.count}) else { throw AppFailure("无主体字幕") }
            let size=CGSize(width:875,height:404)
            model.beginFrameReplay(region:CaptureRegion(displayID:0,screenFrame:CGRect(origin:.zero,size:size),rect:CGRect(origin:.zero,size:size),scale:2,displayName:"Recorded replay"))
            for _ in 0..<100 {
                model.acceptReplayFrame(lines,image:reference)
                if model.coveredSourceKeys.contains(OCRText.key(body.text)) { break }
                try await Task.sleep(nanoseconds:100_000_000)
            }
            report["firstTranslationError"] = model.error
            report["firstTranslationStatus"] = model.status
            report["coveredSources"] = Array(model.coveredSourceKeys)
            guard model.coveredSourceKeys.contains(OCRText.key(body.text)) else { throw AppFailure("首句未出现译文") }
            var covered:[Bool]=[]
            for name in ["frame-063.50.jpg","frame-064.00.jpg","frame-064.50.jpg"] {
                let image=try frame(name), next=try await CaptureService.recognize(image,glossary:"")
                guard let longest=next.max(by:{$0.text.count < $1.text.count}) else { throw AppFailure("回放字幕缺失") }
                model.acceptReplayFrame(next,image:image)
                covered.append(model.coveredSourceKeys.contains(OCRText.key(longest.text)))
                try await Task.sleep(nanoseconds:100_000_000)
            }
            report["actualRecordingOCRVariantsRemainTranslated"]=covered
            let newFrame=try frame("frame-065.00.jpg"), newLines=try await CaptureService.recognize(newFrame,glossary:"")
            model.acceptReplayFrame(newLines,image:newFrame)
            let staleGone = !model.coveredSourceKeys.contains(OCRText.key(body.text))
            report["oldTranslationClearedWhenGlyphsChange"]=staleGone
            guard covered.allSatisfy({$0}),staleGone else { throw AppFailure("录屏回放发生译文闪失或拖旧") }
            report["passed"]=true
        } catch {report["passed"]=false;report["error"]=error.localizedDescription}
        model.shutdown()
        try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:outputFolder.appendingPathComponent("recording-replay-test.json"))
    }
}


@MainActor extension Diagnostics {
    static func typewriterTest(model:AppModel) async {
        var report:[String:Any]=[:]
        let originalMode=model.timingMode
        defer { model.timingMode=originalMode }
        do {
            model.engine.load()
            for _ in 0..<240 { if model.engine.ready || !model.engine.loading {break}; try await Task.sleep(nanoseconds:500_000_000) }
            guard model.engine.ready else {throw AppFailure(model.engine.status)}
            var quality:[[String:Any]]=[]
            let examples=["食事中だから、\n話しかけないでくれる？", "はい。\nなら、これはひとりごとです。", "３人で一緒にラーメンを\n食べたことを、ふと思い出してしまって。", "……えっ？美鈴！？なんで！？", "本当は、一緒に行きたかったんだけど。", "別に怒ってるわけじゃない。ただ、少し驚いただけ。", "まだ何も決まっていないんです。だから、少し待ってもらえますか。"]
            for source in examples {
                let start=ProcessInfo.processInfo.systemUptime
                let result=try await model.engine.translate([source],context:[],glossary:"")
                quality.append(["ja":source,"zh":result[0],"seconds":ProcessInfo.processInfo.systemUptime-start])
            }
            report["qualitySamples"]=quality
            func image(_ text:String)->CGImage {
                let ctx=CGContext(data:nil,width:1400,height:300,bitsPerComponent:8,bytesPerRow:5600,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
                NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:ctx,flipped:false)
                NSColor.white.setFill();CGRect(x:0,y:0,width:1400,height:300).fill()
                let attrs:[NSAttributedString.Key:Any]=[.font:NSFont(name:"HiraginoSans-W3",size:38)!, .foregroundColor:NSColor.black]
                for (i,row) in text.components(separatedBy:"\n").enumerated() { (row as NSString).draw(at:CGPoint(x:55,y:200-i*52),withAttributes:attrs) }
                NSGraphicsContext.restoreGraphicsState();return ctx.makeImage()!
            }
            model.timingMode = .automatic
            report["timingMode"]="automatic"
            let size=CGSize(width:700,height:150)
            model.beginFrameReplay(region:CaptureRegion(displayID:0,screenFrame:CGRect(origin:.zero,size:size),rect:CGRect(origin:.zero,size:size),scale:2,displayName:"Typewriter regression"))
            let prefix="３人で一緒にラーメンを"
            let first=image(prefix), firstLines=try await CaptureService.recognize(first,glossary:"")
            for _ in 0..<100 {
                model.acceptReplayFrame(firstLines,image:first)
                if !model.coveredSourceKeys.isEmpty {break}
                try await Task.sleep(nanoseconds:100_000_000)
            }
            guard !model.coveredSourceKeys.isEmpty else {throw AppFailure("前半句测试准备失败")}
            report["prefixTranslation"]=model.translation
            let before=model.history.count
            let tail="食べたことを、ふと思い出してしまって。"
            var finalImage=first,finalLines=firstLines
            var earlyFullTranslations=0
            for count in stride(from:2,through:tail.count,by:2) {
                let partial=prefix+"\n"+String(tail.prefix(count))
                finalImage=image(partial);finalLines=try await CaptureService.recognize(finalImage,glossary:"")
                model.acceptReplayFrame(finalLines,image:finalImage)
                try await Task.sleep(nanoseconds:100_000_000)
                earlyFullTranslations=max(earlyFullTranslations,model.history.count-before)
            }
            finalImage=image(prefix+"\n"+tail);finalLines=try await CaptureService.recognize(finalImage,glossary:"")
            let began=ProcessInfo.processInfo.systemUptime
            for _ in 0..<120 {
                model.acceptReplayFrame(finalLines,image:finalImage)
                if model.history.count>before && model.translation.contains("拉面") && (model.translation.contains("想起") || model.translation.contains("记起")) {break}
                try await Task.sleep(nanoseconds:100_000_000)
            }
            report["earlyRequestsDuringGrowth"]=earlyFullTranslations
            report["finalOCR"]=finalLines.map(\.text)
            report["completeTranslation"]=model.translation
            report["afterFinalCharacterSeconds"]=ProcessInfo.processInfo.systemUptime-began
            report["history"]=model.history.map {["ja":$0.source,"zh":$0.translation]}
            guard earlyFullTranslations==0,model.history.count>before,model.translation.contains("拉面"),model.translation.contains("三"),model.translation.contains("想起") || model.translation.contains("记起") else {throw AppFailure("逐字对白未得到完整译文")}
            let held=model.translation
            for _ in 0..<20 {model.acceptReplayFrame(finalLines,image:finalImage);try await Task.sleep(nanoseconds:100_000_000)}
            guard model.translation==held else {throw AppFailure("完整对白译文意外消失")}
            report["heldForTwoSeconds"]=true;report["passed"]=true
        } catch {report["passed"]=false;report["error"]=error.localizedDescription}
        model.shutdown()
        try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:outputFolder.appendingPathComponent("typewriter-test.json"))
    }
}
