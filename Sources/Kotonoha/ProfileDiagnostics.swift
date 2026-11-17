import AppKit
import TranslationCore

@MainActor extension Diagnostics {
    static func profileTimingTest(model: AppModel) async {
        var report: [String:Any] = [:], runs: [[String:Any]] = []
        let savedPath = model.engine.modelPath, savedMode = model.timingMode
        defer { model.shutdown(); model.engine.modelPath = savedPath; model.timingMode = savedMode }
        func frame(_ texts: [String], offset: Int = 0) -> (CGImage,[RecognizedLine]) {
            let ctx = CGContext(data:nil,width:1200,height:600,bitsPerComponent:8,bytesPerRow:4800,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext:ctx,flipped:false)
            NSColor.white.setFill(); CGRect(x:0,y:0,width:1200,height:600).fill()
            var lines: [RecognizedLine] = []
            for (i,text) in texts.enumerated() {
                let y = 440-i*150+offset
                (text as NSString).draw(at:CGPoint(x:50,y:y),withAttributes:[.font:NSFont.systemFont(ofSize:30),.foregroundColor:NSColor.black])
                lines.append(RecognizedLine(text:text,rect:CGRect(x:0.04,y:Double(y)/600,width:0.88,height:0.07),confidence:1))
            }
            NSGraphicsContext.restoreGraphicsState(); return (ctx.makeImage()!,lines)
        }
        let canvas = CGSize(width:600,height:300)
        func reset() { model.beginFrameReplay(region:CaptureRegion(displayID:0,screenFrame:CGRect(origin:.zero,size:canvas),rect:CGRect(origin:.zero,size:canvas),scale:2,displayName:"Profile timing test")) }
        func waitFor(_ text: String, frame f: (CGImage,[RecognizedLine])) async throws -> Double {
            let began = ProcessInfo.processInfo.systemUptime
            for _ in 0..<160 {
                model.acceptReplayFrame(f.1,image:f.0)
                if model.coveredSourceKeys.contains(OCRText.key(text)) { return ProcessInfo.processInfo.systemUptime-began }
                try await Task.sleep(nanoseconds:50_000_000)
            }
            throw AppFailure("Overlay deadline exceeded: \(text)")
        }
        do {
            model.timingMode = .automatic
            for filename in ["sakura-1.5b-qwen2.5-v1.0-fp16.gguf","Galtransl-v4-4B-2601-Q5_K_S.gguf","Hy-MT2-1.8B-Q4_K_M.gguf","Qwen3-8B-Q4_K_M.gguf"] {
                model.stop(); model.engine.unload()
                let directory = ProcessInfo.processInfo.environment["KOTONOHA_MODELS_DIR"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Codex/model").path
                model.engine.modelPath = URL(fileURLWithPath:directory).appendingPathComponent(filename).path
                model.engine.load()
                for _ in 0..<240 { if model.engine.ready || !model.engine.loading { break }; try await Task.sleep(nanoseconds:500_000_000) }
                guard model.engine.ready else { throw AppFailure(model.engine.status) }
                var run: [String:Any] = ["model":filename], samples: [[String:Any]] = []
                for source in ["３人で一緒にラーメンを食べたことを、ふと思い出してしまって。","彼女に一時間も待たされた。","雨がやむまで、ここで待っていて。迎えに来るから、絶対に一人で帰らないでね。"] {
                    let began = ProcessInfo.processInfo.systemUptime
                    let output = try await model.engine.translate([source],context:[],glossary:"")
                    samples.append(["source":source,"translation":output[0],"seconds":ProcessInfo.processInfo.systemUptime-began])
                }
                run["translations"] = samples
                let recordedPath = "work/review1117/gal/work/video-review/frame-077.89.jpg"
                if let recorded = NSImage(contentsOfFile:recordedPath)?.cgImage(forProposedRect:nil,context:nil,hints:nil) {
                    let began = ProcessInfo.processInfo.systemUptime
                    let recognized = try await CaptureService.recognize(recorded,glossary:"").filter { $0.rect.midX < 0.28 && $0.rect.midY < 0.3 }
                    run["recordingOCRSeconds"] = ProcessInfo.processInfo.systemUptime-began
                    let groups = TextLayout.groups(recognized,canvas:CGSize(width:recorded.width,height:recorded.height))
                    let body = groups.map { $0.map(\.text).joined(separator:"\n") }.max { $0.count < $1.count }
                    guard let body, body.count > 8 else { throw AppFailure("Recorded Japanese body missing") }
                    reset()
                    run["recordingSource"] = body
                    run["recordingOCRObservationToOverlay"] = try await waitFor(body,frame:(recorded,recognized))
                    run["recordingTranslation"] = model.translation
                }
                reset()
                let caption = "あなたとふたり、電車で新しい思い出。", body = "そのことを、とても、うれしく思うんです。"
                _ = try await waitFor(body,frame:frame([caption,body]))
                guard !model.coveredSourceKeys.contains(OCRText.key(caption)) else { throw AppFailure("Static caption delayed new dialogue") }
                run["newDialoguePrecedesStaticCaption"] = true
                reset()
                let full = "お嬢様、ご休憩です。お茶をどうぞ。", fixed = frame([full])
                run["wholeSentenceObservationToOverlay"] = try await waitFor(full,frame:fixed)
                let before = model.translation
                for _ in 0..<12 { model.acceptReplayFrame(fixed.1,image:fixed.0); try await Task.sleep(nanoseconds:50_000_000) }
                guard model.translation == before else { throw AppFailure("Stable sentence changed its overlay") }
                run["stableSentenceHeld"] = true

                // A missed OCR result must not create a one-frame flash.
                model.acceptReplayFrame([],image:fixed.0)
                guard model.translation == before else { throw AppFailure("One missing OCR sample cleared the translation") }
                model.acceptReplayFrame(fixed.1,image:fixed.0)
                run["singleMissingOCRHeld"] = true

                reset()
                let prefix = "今日はここで待っていて。", tail = "迎えに来るから、一人で帰らないでね。"
                let first = frame([prefix])
                _ = try await waitFor(prefix,frame:first)
                var dropouts = 0
                for count in 1...tail.count {
                    let text = prefix+String(tail.prefix(count)), next = frame([text])
                    model.acceptReplayFrame(next.1,image:next.0)
                    if model.translation.isEmpty { dropouts += 1 }
                    try await Task.sleep(nanoseconds:60_000_000)
                }
                guard dropouts == 0 else { throw AppFailure("Growing dialogue dropped the translated prefix") }
                run["typewriterAppendDropouts"] = dropouts
                _ = try await waitFor(prefix+tail,frame:frame([prefix+tail]))
                let replaced = frame(["図書館で美鈴に会いました。"])
                model.acceptReplayFrame(replaced.1,image:replaced.0)
                guard model.translation.isEmpty else { throw AppFailure("Replaced dialogue kept the old page") }
                run["replacedPageCleared"] = true
                _ = try await waitFor(replaced.1[0].text,frame:replaced)

                reset()
                let old = "明日は一緒に図書館へ行きましょう。", newest = "はい、約束ですよ。忘れないでくださいね。"
                _ = try await waitFor(old,frame:frame([old]))
                let bubbles = frame([old,newest])
                _ = try await waitFor(newest,frame:bubbles)
                guard model.coveredSourceKeys.contains(OCRText.key(old)) else { throw AppFailure("New chat bubble erased the earlier bubble") }
                run["independentChatBubblesBothCovered"] = true
                let scrolled = frame([old,newest],offset:60)
                model.acceptReplayFrame(scrolled.1,image:scrolled.0)
                guard model.overlay.presentationRects.count == 2 else { throw AppFailure("Scrolling chat left duplicate old covers") }
                run["scrollingChatHasNoDuplicateCovers"] = true
                reset()
                let obsolete = frame([String(repeating:"雨が降っているので、ここで待っています。",count:20)])
                model.acceptReplayFrame(obsolete.1,image:obsolete.0)
                try await Task.sleep(nanoseconds:50_000_000)
                let replacement = "図書館で友達と待ち合わせしています。", replacementFrame = frame([replacement])
                run["obsoleteRequestToReplacementOverlay"] = try await waitFor(replacement,frame:replacementFrame)
                guard model.coveredSourceKeys == [OCRText.key(replacement)] else { throw AppFailure("Obsolete page painted over the replacement") }
                run["obsoletePageNotPainted"] = true
                reset()
                let oversized = String(repeating:"翻訳",count:1000)+"。", small = "はい、約束ですよ。忘れないでくださいね。"
                let failedFrame = frame([oversized])
                model.acceptReplayFrame(failedFrame.1,image:failedFrame.0)
                try await Task.sleep(nanoseconds:50_000_000)
                run["failedRegionToOtherBubbleOverlay"] = try await waitFor(small,frame:frame([oversized,small]))
                run["failedRegionDoesNotBlockOtherBubble"] = true
                run["passed"] = true; runs.append(run)
            }
            report["passed"] = true
        } catch { report["passed"] = false; report["error"] = error.localizedDescription }
        report["runs"] = runs
        try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:outputFolder.appendingPathComponent("profile-timing-test.json"))
    }
}
