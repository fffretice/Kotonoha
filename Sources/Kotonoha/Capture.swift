import AppKit
import ScreenCaptureKit
import Vision
import CoreImage
import CoreMedia
import TranslationCore

struct CaptureRegion {
    var displayID: CGDirectDisplayID
    var screenFrame: CGRect
    var rect: CGRect // AppKit global, bottom-left origin
    var scale: CGFloat
    var displayName: String
    var description: String { "\(displayName) · \(Int(rect.width)) × \(Int(rect.height))" }
    var sourceRect: CGRect { CGRect(x: rect.minX - screenFrame.minX, y: screenFrame.maxY - rect.maxY, width: rect.width, height: rect.height) }
}

@MainActor final class CaptureService {
    var lastStartError: String?
    private var stopping: Task<Void,Never>?
    private var stream: SCStream?
    private var receiver: CaptureFrames?
    private var filter: SCContentFilter?
    private var region: CaptureRegion?
    private var authorizedFilter: SCContentFilter?
    private var authorizedSourceRect: CGRect?
    private var authorizedDisplay: CGDirectDisplayID?
    func authorize(_ filter: SCContentFilter, for region: CaptureRegion) {
        authorizedFilter = filter; authorizedDisplay = region.displayID
    }
    func hasAuthorization(for region: CaptureRegion) -> Bool {
        authorizedFilter != nil && authorizedDisplay == region.displayID
    }
    func prepare(_ region: CaptureRegion) async throws {
        if stream != nil, receiver?.failure == nil, let existing = self.region,
           existing.rect == region.rect, existing.scale == region.scale, filter === authorizedFilter { return }
        if let authorizedFilter, authorizedDisplay == region.displayID {
            let top = NSScreen.screens[0].frame.maxY
            let global = CGRect(x: region.rect.minX, y: top - region.rect.maxY, width: region.rect.width, height: region.rect.height)
            let content = authorizedFilter.contentRect
            guard content.insetBy(dx: -2, dy: -2).contains(global) else {
                self.authorizedFilter = nil; authorizedSourceRect = nil
                throw AppFailure("框选区域不在所选共享内容内，请选择框选区域所在的屏幕或窗口。")
            }
            authorizedSourceRect = global.offsetBy(dx: -content.minX, dy: -content.minY)
            filter = authorizedFilter; self.region = region
            try await beginStream(); return
        }
        throw AppFailure("请先点击「选择游戏窗口」，通过系统选择器建立共享会话")
    }
    private func beginStream() async throws {
        guard let filter, let region else { throw AppFailure("请先框选区域") }
        guard NSScreen.screens.contains(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == region.displayID }) else { throw AppFailure("显示器已断开，请重新框选") }
        let c = SCStreamConfiguration()
        c.sourceRect = authorizedSourceRect ?? region.sourceRect
        // Retina sampling for small glyphs; cap huge full-screen captures to 3200 px.
        let scale = min(region.scale, 3200 / max(region.rect.width, region.rect.height))
        c.width = max(2, Int(region.rect.width * scale)); c.height = max(2, Int(region.rect.height * scale))
        c.showsCursor = false; c.capturesAudio = false
        c.minimumFrameInterval = CMTime(value: 1, timescale: 10)
        c.queueDepth = 3
        let frames = CaptureFrames()
        let stream = SCStream(filter: filter, configuration: c, delegate: frames)
        try stream.addStreamOutput(frames, type: .screen, sampleHandlerQueue: DispatchQueue(label: "app.kotonoha.frames", qos: .userInitiated))
        stop(clearConsent: false)
        await stopping?.value
        try Task.checkCancellation()
        stopping = nil
        self.receiver = frames; self.stream = stream
        do {
            try await stream.startCapture()
            try Task.checkCancellation()
        } catch {
            let detail = error as NSError
            lastStartError = "\(detail.domain) / \(detail.code) / \(detail.userInfo)"
            try? await stream.stopCapture()
            if self.stream === stream { self.stream = nil; receiver = nil }
            throw error
        }
    }
    func image() async throws -> CGImage {
        guard let receiver else { throw AppFailure("屏幕共享尚未开始，请选择游戏窗口") }
        for _ in 0..<60 {
            try Task.checkCancellation()
            if let error = receiver.failure { throw error }
            if let image = receiver.image { return image }
            try await Task.sleep(nanoseconds: 80_000_000)
        }
        throw AppFailure("未收到共享窗口的画面，请确认窗口未最小化，再重新选择游戏窗口")
    }
    func stop(clearConsent: Bool = true) {
        if clearConsent { authorizedFilter = nil; authorizedDisplay = nil; authorizedSourceRect = nil }
        let old = stream; stream = nil; receiver = nil
        if let old {
            let prior = stopping
            stopping = Task { await prior?.value; try? await old.stopCapture() }
        }
    }
    static func recognize(_ image: CGImage, glossary: String) async throws -> [RecognizedLine] {
        try await Task.detached(priority: .userInitiated) {
            let r = VNRecognizeTextRequest(); r.recognitionLevel = .accurate
            let supported = try r.supportedRecognitionLanguages()
            guard supported.contains("ja-JP") else { throw AppFailure("当前系统 OCR 不支持日文，请更新 macOS") }
            r.recognitionLanguages = ["ja-JP", "en-US"]; r.usesLanguageCorrection = true
            r.minimumTextHeight = 0.006
            r.customWords = glossary.split(separator: "\n").map { String($0.split(separator: "=").first ?? $0) }.filter { !$0.isEmpty }
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([r])
            return (r.results ?? []).compactMap { observation -> RecognizedLine? in
                guard let c = observation.topCandidates(1).first, c.confidence >= 0.25,
                    TextTools.containsJapanese(c.string) else { return nil }
                return RecognizedLine(text: c.string, rect: observation.boundingBox, confidence: c.confidence)
            }.sorted {
                if abs($0.rect.midY - $1.rect.midY) > min($0.rect.height, $1.rect.height) * 0.5 { return $0.rect.midY > $1.rect.midY }
                return $0.rect.minX < $1.rect.minX
            }
        }.value
    }
}

@MainActor final class RegionSelector {
    private var windows: [NSWindow] = []
    private var completion: ((CaptureRegion?) -> Void)?
    func begin(completion: @escaping (CaptureRegion?) -> Void) {
        cancel(); self.completion = completion
        NSApp.activate(ignoringOtherApps: true)
        for screen in NSScreen.screens {
            let w = SelectionWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false; w.level = .screenSaver; w.backgroundColor = .clear; w.isOpaque = false
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; w.hasShadow = false
            let view = SelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.onCancel = { [weak self] in self?.finish(nil) }
            view.onSelect = { [weak self] local in
                guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return }
                self?.finish(CaptureRegion(displayID: id, screenFrame: screen.frame, rect: local.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY), scale: screen.backingScaleFactor, displayName: screen.localizedName))
            }
            w.contentView = view; w.makeKeyAndOrderFront(nil); w.makeFirstResponder(view); windows.append(w)
        }
    }
    func cancel() { windows.forEach { $0.close() }; windows = []; completion = nil }
    private func finish(_ region: CaptureRegion?) { let callback = completion; cancel(); callback?(region) }
}
private final class SelectionWindow: NSWindow { override var canBecomeKey: Bool { true } }
private final class SelectionView: NSView {
    var onSelect: ((CGRect) -> Void)?; var onCancel: (() -> Void)?
    var start: CGPoint?; var selection: CGRect = .zero
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { onCancel?() } }
    override func mouseDown(with event: NSEvent) { start = convert(event.locationInWindow, from: nil); selection = .zero; needsDisplay = true }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }; let p = convert(event.locationInWindow, from: nil)
        selection = CGRect(x: min(p.x, start.x), y: min(p.y, start.y), width: abs(p.x-start.x), height: abs(p.y-start.y)).intersection(bounds)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        mouseDragged(with: event)
        if selection.width >= 40 && selection.height >= 20 { onSelect?(selection) }
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.46).setFill(); bounds.fill()
        if !selection.isEmpty {
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current?.compositingOperation = .copy
            NSColor.clear.setFill(); selection.fill(); NSGraphicsContext.restoreGraphicsState()
            NSColor.systemMint.setStroke(); let p = NSBezierPath(rect: selection); p.lineWidth = 2; p.stroke()
            let size = "\(Int(selection.width)) × \(Int(selection.height))"
            (size as NSString).draw(at: CGPoint(x: selection.minX, y: max(10, selection.minY - 28)), withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.white])
        }
        let text = "拖动框选日文对话区域   ·   Esc 取消"
        let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 20, weight: .medium), .foregroundColor: NSColor.white]
        let s = (text as NSString).size(withAttributes: a)
        (text as NSString).draw(at: CGPoint(x: (bounds.width-s.width)/2, y: bounds.height-100), withAttributes: a)
    }
}

/// Only SCStream consumes the system picker's session consent. No screenshot API is used.
private final class CaptureFrames: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var storedImage: CGImage?
    private var storedError: Error?
    private let context = CIContext(options: [.cacheIntermediates: false])
    var image: CGImage? { lock.lock(); defer { lock.unlock() }; return storedImage }
    var failure: Error? { lock.lock(); defer { lock.unlock() }; return storedError }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.lock(); storedError = error; storedImage = nil; lock.unlock()
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }
        if let attachment = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let raw = attachment.first?[.status] as? Int, raw != SCFrameStatus.complete.rawValue {
            if raw == SCFrameStatus.blank.rawValue || raw == SCFrameStatus.suspended.rawValue {
                lock.lock(); storedImage = nil; lock.unlock()
            }
            return
        }
        guard let buffer = sampleBuffer.imageBuffer else { return }
        let image = CIImage(cvPixelBuffer: buffer)
        guard let cg = context.createCGImage(image, from: image.extent) else { return }
        lock.lock(); storedImage = cg; lock.unlock()
    }
}
