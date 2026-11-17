import AppKit
import SwiftUI
import ScreenCaptureKit
import TranslationCore

struct HistoryEntry: Identifiable {
    let id = UUID()
    let source: String
    let translation: String
    let seconds: Double
    let time = Date()
}

@MainActor final class AppModel: ObservableObject {
    let engine = LocalEngine()
    let selector = RegionSelector()
    let capture = CaptureService()
    let screenAuthorization = ScreenAuthorization()
    @Published var needsScreenAuthorization = false
    @Published var choosingScreen = false
    let overlay = OverlayController()
    @Published var captureMode: CaptureMode = .region
    @Published var region: CaptureRegion?
    @Published var running = false
    @Published var status = "框选游戏中的日文对话区域"
    @Published var error: String?
    @Published var source = ""
    @Published var translation = ""
    @Published var history: [HistoryEntry] = []
    @Published var preview: NSImage?
    @Published var latency = "—"
    @Published var peek = false { didSet { overlay.hidden = peek } }
    @Published var separateLines = false { didSet { invalidateTranslation() } }
    @Published var glossary: String = UserDefaults.standard.string(forKey: "glossary") ?? "" {
        didSet { UserDefaults.standard.set(glossary, forKey: "glossary"); invalidateTranslation() }
    }
    @Published var style: CoverStyle = CoverStyle(rawValue: UserDefaults.standard.string(forKey:"coverStyle") ?? "") ?? .automatic { didSet { updateAppearance() } }
    @Published var fontSize: Double = 20 { didSet { updateAppearance() } }
    @Published var opacity: Double = 1 { didSet { updateAppearance() } }
    @Published var padding: Double = 6 { didSet { updateAppearance() } }
    @Published var timingMode: TextTimingMode = TextTimingMode(rawValue:UserDefaults.standard.string(forKey:"timingMode") ?? "") ?? .automatic {
        didSet { UserDefaults.standard.set(timingMode.rawValue,forKey:"timingMode"); invalidateTranslation() }
    }
    @Published var stabilityDelay: Double = 0.12
    private var captureTask: Task<Void, Never>?
    private var selectionTask: Task<Void,Never>?
    private var translationTask: Task<Void, Never>?
    private var readiness = RegionReadiness()
    private var cache = TranslationCache()
    private struct DialogueMemory { var source: String; var translation: String; var rect: CGRect }
    private var context: [DialogueMemory] = []
    private var generation = UUID()
    private var currentLines: [RecognizedLine] = []
    private struct VisualTranslation {
        var source:String; var text:String; var rect:CGRect; var fingerprint:SubtitleFingerprint
    }
    private var visualTranslations: [VisualTranslation] = []
    private var shownBlocks: [TranslationBlock] = []
    private var confirmedAt: [String: Double] = [:]
    private var lastPreviewTime: Double = 0
    private var latestImage: CGImage?
    private var retryAfter: TimeInterval = 0
    private var activeModelPath = ""
    private var firstSeen: [String:Double] = [:]
    private var failedUntil: [String:Double] = [:]
    private var inFlight: [TranslationBlock] = []
    private var obsoleteSince: Double?

    var appearance: OverlayAppearance { OverlayAppearance(style: style, opacity: opacity, fontSize: fontSize, padding: padding) }
    var coveredSourceKeys: Set<String> { Set(shownBlocks.map { OCRText.key($0.source) }) }
    var regionLabel: String { region?.description ?? "尚未选择" }
    func updateAppearance() {
        UserDefaults.standard.set(style.rawValue,forKey:"coverStyle")
        overlay.update(appearance)
    }
    private func resetSelectionContent() {
        preview = nil; latestImage = nil; currentLines = []; source = ""; translation = ""
        lastPreviewTime = 0; readiness = RegionReadiness(); visualTranslations = []
        overlay.close()
    }
    func chooseRegion() {
        stop(); resetSelectionContent(); captureMode = .region; error = nil
        selector.begin { [weak self] selected in
            guard let self, let selected else { return }
            region = selected; status = "区域已选好，可以开始翻译"; overlay.configure(region: selected)
        }
    }
    func selectFullScreen() {
        let resume = running
        stop(); resetSelectionContent(); captureMode = .fullScreen; region = nil; authorizeScreen(resumeAfterSelection:resume)
    }
    func selectWindow() {
        let resume = running
        stop(); resetSelectionContent(); captureMode = .window; region = nil; authorizeScreen(resumeAfterSelection:resume)
    }
    func toggle() { if running { stop() } else { start() } }
    func start() {
        guard !running, !choosingScreen else { return }
        guard let region else { if captureMode == .region { chooseRegion() } else { authorizeScreen() }; return }
        guard engine.ready else { error = "先加载本地模型，再开始翻译"; engine.load(); return }
        if !capture.hasAuthorization(for: region) {
            authorizeScreen(); return
        }
        error = nil; needsScreenAuthorization = false; running = true; peek = false
        generation = UUID(); let run = generation
        readiness = RegionReadiness(); retryAfter = 0
        overlay.configure(region: region); status = "正在连接屏幕…"
        captureTask = Task {
            do {
                try await capture.prepare(region)
                guard running, run == generation else { return }
                while !Task.isCancelled && running && run == generation {
                    let cycleBegan = ProcessInfo.processInfo.systemUptime
                    let image = try await capture.image()
                    let lines = try await CaptureService.recognize(image, glossary: glossary)
                    guard !Task.isCancelled, running, run == generation else { return }
                    latestImage = image; currentLines = lines
                    let now = ProcessInfo.processInfo.systemUptime
                    if now-lastPreviewTime >= 0.5 { preview = NSImage(cgImage:image,size:region.rect.size); lastPreviewTime = now }
                    processObservation(lines, image: image, run: run)
                    // OCR work counts toward the sampling interval; do not add another fixed pause.
                    let remaining = max(0.01, 0.1 - (ProcessInfo.processInfo.systemUptime-cycleBegan))
                    try await Task.sleep(nanoseconds: UInt64(remaining*1_000_000_000))
                }
            } catch {
                guard !Task.isCancelled, run == generation else { return }
                stop()
                let ns = error as NSError
                if ns.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain" && ns.code == -3801 {
                    needsScreenAuthorization = true
                    self.error = "共享会话未能建立。点击「选择游戏窗口」，在系统选择器中选择框选区域所在的游戏窗口。"
                    status = "需要选择游戏窗口"
                } else {
                    self.error = "屏幕识别未能继续：\(error.localizedDescription)"; status = "已暂停，可重新尝试"
                }
            }
        }
    }
    func authorizeScreen(resumeAfterSelection: Bool? = nil) {
        guard !choosingScreen else { return }
        if captureMode == .region && region == nil { chooseRegion(); return }
        let selected = region, mode = captureMode
        let resume = resumeAfterSelection ?? engine.ready
        stop(); resetSelectionContent(); choosingScreen = true; error = nil; status = mode.instruction
        let token = generation
        screenAuthorization.present(mode:mode) { [weak self] result in
            guard let self, generation == token else { return }
            switch result {
            case .success(let filter):
                self.applySelection(filter,mode:mode,selected:selected,resume:resume)
            case .failure(let error):
                choosingScreen = false; self.error = error.localizedDescription; status = "尚未选择共享内容"
            }
        }
    }
    func applySelection(_ filter: SCContentFilter, mode: CaptureMode, selected: CaptureRegion?, resume: Bool) {
        stop(); resetSelectionContent(); captureMode = mode; choosingScreen = true
        let token = generation
        self.selectionTask = Task { [self] in
                    do {
                        let target = try mode.region(for:filter,selected:selected)
                        self.region = target; self.capture.authorize(filter,for:target); self.needsScreenAuthorization = false
                        self.overlay.configure(region:target)
                        try await self.capture.prepare(target)
                        let frame = try await self.capture.image()
                        guard !Task.isCancelled, self.generation == token else { return }
                        self.preview = NSImage(cgImage:frame,size:target.rect.size); self.latestImage = frame
                        self.lastPreviewTime = ProcessInfo.processInfo.systemUptime
                        self.choosingScreen = false; self.selectionTask = nil
                        if resume && self.engine.ready { self.start() } else { self.status = "预览已刷新，点击开始翻译" }
                    } catch {
                        guard !Task.isCancelled, self.generation == token else { return }
                        self.choosingScreen = false; self.selectionTask = nil; self.capture.stop()
                        self.error = error.localizedDescription
                    }
                }
    }
    func stop() {
        running = false; generation = UUID()
        selectionTask?.cancel(); selectionTask = nil; choosingScreen = false
        captureTask?.cancel(); captureTask = nil; translationTask?.cancel(); translationTask = nil
        capture.stop()
        shownBlocks = []; confirmedAt = [:]; firstSeen = [:]; failedUntil = [:]; inFlight = []; obsoleteSince = nil
        overlay.clear(); status = "已暂停 · 原画面已恢复"
    }
    func retryFromUI() {
        if needsScreenAuthorization { authorizeScreen(); return }
        if !running && region != nil && engine.ready { start(); return }
        retry()
    }
    func retry() {
        translationTask?.cancel(); translationTask = nil
        retryAfter = 0; cache.clear(); error = nil; failedUntil = [:]; inFlight = []; obsoleteSince = nil
    }
    func resetContext() { context = []; cache.clear(); retry(); status = "对话记忆已清空" }
    private func invalidateTranslation() { cache.clear(); context = []; visualTranslations = []; shownBlocks = []; confirmedAt = [:]; readiness = RegionReadiness(); retry(); overlay.clear() }
    private func blocks(for lines: [RecognizedLine]) -> [TranslationBlock] {
        let canvas = region?.rect.size ?? CGSize(width: 1000, height: 1000)
        let dialogue = lines.filter { !DialogueText.isLabelOrControl($0,among:lines) }
        return TextLayout.groups(dialogue, canvas: canvas, separateLines: separateLines).compactMap { group in
            guard let first = group.first else { return nil }
            return TranslationBlock(source: group.map(\.text).joined(separator: "\n"), translated: "",
                rect: group.dropFirst().reduce(first.rect) { $0.union($1.rect) })
        }
    }
    private func processObservation(_ lines: [RecognizedLine], image: CGImage, run: UUID) {
        let now = ProcessInfo.processInfo.systemUptime
        if activeModelPath != engine.modelPath {
            activeModelPath = engine.modelPath; invalidateTranslation(); firstSeen = [:]
        }
        let latestSource = TextTools.signature(lines)
        if source != latestSource { source = latestSource }
        let current = blocks(for: lines)
        let candidates = current.map { block in
            let confidence = lines.filter { $0.rect.intersects(block.rect) }.map(\.confidence).min() ?? 0
            return RecognizedLine(text:block.source,rect:block.rect,confidence:confidence)
        }
        let ready = readiness.observe(candidates, at:now, delay:stabilityDelay, mode:timingMode)
        for block in current where firstSeen[cacheKey(block.source)] == nil { firstSeen[cacheKey(block.source)] = now }
        // Only an actually replaced page cancels work. Growth and chat scrolling can still use the result.
        if translationTask != nil {
            let useful = current.contains { live in inFlight.contains { old in
                OCRText.key(old.source) == OCRText.key(live.source) ||
                DialogueContinuity.isAppending(previous:old.source,current:live.source) ||
                DialogueContinuity.isAppending(previous:live.source,current:old.source) ||
                OCRText.mayReuseTranslation(old.source,live.source)
            }}
            if useful { obsoleteSince = nil }
            else if let since = obsoleteSince, now-since >= (current.isEmpty ? 0.8 : 0.15) {
                translationTask?.cancel(); translationTask = nil; inFlight = []; obsoleteSince = nil
            } else if obsoleteSince == nil { obsoleteSince = now }
        }
        renderCurrent()
        guard !current.isEmpty else { status = "等待日文对话…"; return }
        // One request finishes even if another OCR region changes; only the latest missing text is queued.
        guard translationTask == nil else { if status != "正在本地翻译…" { status = "正在本地翻译…" }; return }
        guard now >= retryAfter else { return }
        let pending = current.enumerated().filter {
            ready[$0.offset] && cache[cacheKey($0.element.source)] == nil && now >= (failedUntil[cacheKey($0.element.source)] ?? 0)
        }.map(\.element).sorted {
            // Dialogue takes precedence over short labels; newest bubbles precede static chapter text.
            let aBody = $0.source.count > 8, bBody = $1.source.count > 8
            if aBody != bBody { return aBody }
            let a = firstSeen[cacheKey($0.source)] ?? 0, b = firstSeen[cacheKey($1.source)] ?? 0
            if abs(a-b) > 0.05 { return a > b }
            return $0.rect.midY < $1.rect.midY
        }
        guard !pending.isEmpty else {
            status = current.allSatisfy { cache[cacheKey($0.source)] != nil } ? "译文已覆盖 · 等待下一句" : "正在识别新文字…"
            return
        }
        let batch = Array(pending.prefix(1))
        inFlight = batch; obsoleteSince = nil
        let evidence = batch.map { SubtitleFingerprint(image:image,rect:$0.rect) }
        status = "正在本地翻译…"
        translationTask = Task {
            let began = ProcessInfo.processInfo.systemUptime
            do {
                let memory = context.filter { record in
                    let rect = batch[0].rect
                    return record.rect.intersects(rect) || abs(record.rect.midY-rect.midY) < max(record.rect.height,rect.height)*2
                }.map { ($0.source,$0.translation) }
                let results = try await engine.translate(batch.map(\.source), context:memory, glossary:glossary)
                guard !Task.isCancelled, running, run == generation else { return }
                let seconds = ProcessInfo.processInfo.systemUptime-began
                for (i,pair) in zip(batch,results).enumerated() {
                    let (block,text) = pair
                    if let fingerprint = evidence[i] {
                        visualTranslations.insert(VisualTranslation(source:block.source,text:text,rect:block.rect,fingerprint:fingerprint),at:0)
                    }
                    cache.put(text,for:cacheKey(block.source))
                    let superseded = blocks(for:currentLines).contains { isAppended(block,to:$0) }
                    if superseded {
                        // A completed request still covers its own original text, even if more text has arrived.
                        // Do not put this prefix translation under the longer source's cache key.
                        var completed=block; completed.translated=text
                        shownBlocks.removeAll { isAppended($0,to:completed) }
                        if !shownBlocks.contains(where: { $0.rect.intersects(completed.rect) }) { shownBlocks.append(completed) }
                    }
                    let stillPresent = blocks(for:currentLines).contains { OCRText.key($0.source) == OCRText.key(block.source) }
                    if !superseded && stillPresent {
                        if OCRText.key(block.source).count > 6 {
                            context.removeAll { OCRText.isExtension($0.source,block.source) }
                            context.append(DialogueMemory(source:block.source,translation:text,rect:block.rect))
                        }
                        history.insert(HistoryEntry(source:block.source,translation:text,seconds:seconds),at:0)
                    }
                }
                visualTranslations = Array(visualTranslations.prefix(80))
                if context.count > 4 { context.removeFirst(context.count-4) }
                if history.count > 100 { history.removeLast(history.count-100) }
                latency = String(format:"%.2f 秒",seconds)
                error = nil; translationTask = nil; inFlight = []; obsoleteSince = nil
                // Draw only translations whose source still matches the current screen.
                renderCurrent()
                status = "译文已更新 · 继续识别字幕"
            } catch {
                guard !Task.isCancelled, running, run == generation else { return }
                translationTask = nil; inFlight = []; obsoleteSince = nil
                for block in batch { failedUntil[cacheKey(block.source)] = ProcessInfo.processInfo.systemUptime+5 }
                self.error = error.localizedDescription; status = "翻译暂未完成，稍后重试"
            }
        }
    }
    private func cacheKey(_ text: String) -> String { glossary + "\u{0}" + OCRText.key(text) }
    private func isAppended(_ previous:TranslationBlock,to current:TranslationBlock) -> Bool {
        previous.rect.intersects(current.rect) &&
        abs(previous.rect.maxY-current.rect.maxY) <= max(0.015,previous.rect.height*0.35) &&
        DialogueContinuity.isAppending(previous:previous.source,current:current.source)
    }
    private func renderCurrent() {
        guard let image = latestImage else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let current = blocks(for:currentLines)
        var visible = current.compactMap { block -> TranslationBlock? in
            if cache[cacheKey(block.source)] == nil,
               let record = visualTranslations.first(where: { record in
                   guard record.rect.intersects(block.rect), OCRText.mayReuseTranslation(record.source,block.source),
                         block.rect.width <= record.rect.width*1.18, block.rect.height <= record.rect.height*1.18,
                         let current = SubtitleFingerprint(image:image,rect:record.rect) else { return false }
                   return record.fingerprint.matches(current)
               }) { cache.put(record.text,for:cacheKey(block.source)) }
            guard let translated = cache[cacheKey(block.source)] else { return nil }
            confirmedAt[cacheKey(block.source)] = now
            var b = block; b.translated = translated; return b
        }
        for previous in shownBlocks {
            // A scrolling chat bubble is painted at its current position, never at both positions.
            if visible.contains(where: { $0.rect.intersects(previous.rect) || OCRText.key($0.source) == OCRText.key(previous.source) }) { continue }
            let nearest = current.filter { $0.rect.intersects(previous.rect) }.max { a,b in
                a.rect.intersection(previous.rect).width < b.rect.intersection(previous.rect).width
            }
            let age = now - (confirmedAt[cacheKey(previous.source)] ?? 0)
            let stillGrowing = nearest.map { isAppended(previous,to:$0) } ?? false
            if stillGrowing {
                // The same dialogue page is growing. Keep the existing translation at its frozen position
                // until a longer completed translation replaces it or the source page actually changes.
                visible.append(previous)
                continue
            }
            let visuallyUnchanged = !stillGrowing && (visualTranslations.first(where: { $0.text == previous.translated && $0.rect.intersects(previous.rect) }).map { record in
                SubtitleFingerprint(image:image,rect:record.rect).map { record.fingerprint.matches($0) } ?? false
            } ?? false)
            if !stillGrowing && (visuallyUnchanged || OverlayContinuity.keep(previous:previous.source,current:nearest?.source,age:age)) {
                visible.append(previous)
            }
        }
        shownBlocks = visible
        confirmedAt = confirmedAt.filter { now - $0.value < 3 }

        let updated = visible.map(\.translated).joined(separator:"\n")
        if translation != updated { translation = updated }
        if visible.isEmpty { overlay.clear() }
        else { overlay.show(blocks:visible,image:image,appearance:appearance) }
    }
    func beginFrameReplay(region: CaptureRegion) {
        stop(); resetSelectionContent(); self.region = region; generation = UUID(); running = true
        readiness = RegionReadiness(); retryAfter = 0; cache.clear()
        overlay.configure(region:region); overlay.hidden = true
    }
    func acceptReplayFrame(_ lines: [RecognizedLine], image: CGImage) {
        latestImage = image; currentLines = lines
        processObservation(lines,image:image,run:generation)
    }
    func openDemo() {
        let demo = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/试读场景.app")
        NSWorkspace.shared.openApplication(at: demo, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { Task { @MainActor in self.error = error.localizedDescription } }
        }
    }
    func shutdown() { stop(); selector.cancel(); overlay.close(); engine.unload() }
}
