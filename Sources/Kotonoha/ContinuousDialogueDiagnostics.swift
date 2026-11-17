import AppKit
import TranslationCore

@MainActor extension Diagnostics {
    static func continuousDialogueTest(model: AppModel) async {
        var report: [String:Any] = [:], pages: [[String:Any]] = []
        let saved = model.engine.modelPath, mode = model.timingMode
        defer { model.shutdown(); model.engine.modelPath = saved; model.timingMode = mode }
        do {
            let directory = ProcessInfo.processInfo.environment["KOTONOHA_MODELS_DIR"] ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Codex/model").path
            model.engine.modelPath = URL(fileURLWithPath:directory).appendingPathComponent("sakura-1.5b-qwen2.5-v1.0-fp16.gguf").path
            model.engine.load()
            for _ in 0..<240 { if model.engine.ready || !model.engine.loading { break }; try await Task.sleep(nanoseconds:500_000_000) }
            guard model.engine.ready else { throw AppFailure(model.engine.status) }
            model.timingMode = .automatic
            let size = CGSize(width:414,height:918)
            model.beginFrameReplay(region:CaptureRegion(displayID:0,screenFrame:CGRect(origin:.zero,size:size),rect:CGRect(origin:.zero,size:size),scale:2,displayName:"Continuous dialogue"))
            let texts = ["今日は一緒に昼ごはんを食べませんか？","うーん……。","そうじゃなくて、お弁当のことを聞いているんです。","いいから、食べながら話を聞こうよ。","あっそ……別にいいけど。","それって……何の話？","明日は図書館で待ち合わせしましょう。","私のことをもっと知ってほしいんです。","あ、気づいた？妹が作ってくれたんだ。","彼女は人前では照れてしまうんです。","約束を忘れないでくださいね。","雨がやむまでここで待っていてね。"]
            var oversizedFrames = 0, observedFrames = 0
            func present(_ body: String, index: Int) {
                let canvas = CGRect(x:0,y:0,width:828,height:1836)
                let ctx = CGContext(data:nil,width:828,height:1836,bitsPerComponent:8,bytesPerRow:3312,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
                NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext:ctx,flipped:false)
                NSColor.white.setFill(); canvas.fill()
                let lines = [RecognizedLine(text:"どんな関係なんですか？",rect:CGRect(x:0.06,y:0.86,width:0.75,height:0.025),confidence:1),
                             RecognizedLine(text:index % 2 == 0 ? "星南" : "手毬",rect:CGRect(x:0.12,y:0.255,width:0.09,height:0.022),confidence:1),
                             RecognizedLine(text:body,rect:CGRect(x:0.14,y:0.20,width:0.78,height:0.034),confidence:1),
                             RecognizedLine(text:"表情log",rect:CGRect(x:0.32,y:0.07,width:0.15,height:0.025),confidence:1)]
                for line in lines { (line.text as NSString).draw(at:CGPoint(x:line.rect.minX*828,y:line.rect.minY*1836),withAttributes:[.font:NSFont.systemFont(ofSize:22),.foregroundColor:NSColor.black]) }
                NSGraphicsContext.restoreGraphicsState()
                model.acceptReplayFrame(lines,image:ctx.makeImage()!)
                observedFrames += 1
                if model.overlay.presentationRects.contains(where: { $0.height > 110 }) { oversizedFrames += 1 }
            }
            // Keep one session and its model history across all pages, names and persistent controls.
            for (index,text) in texts.enumerated() {
                if index % 3 != 0 {
                    for length in stride(from:2,to:text.count,by:3) {
                        present(String(text.prefix(length)),index:index)
                        try await Task.sleep(nanoseconds:70_000_000)
                    }
                }
                let began = ProcessInfo.processInfo.systemUptime
                var covered = false, dropped = false, firstVisible: Double?
                for _ in 0..<24 {
                    present(text,index:index)
                    let keys = model.overlay.presentationSources.map(OCRText.key)
                    let rects = model.overlay.presentationRects
                    let expected = TextTools.appKitRect(CGRect(x:0.14,y:0.20,width:0.78,height:0.034),in:CGRect(origin:.zero,size:size))
                    var nowCovered = false
                    if let index = keys.firstIndex(of:OCRText.key(text)), index < rects.count {
                        let actual = rects[index], intersection = actual.intersection(expected)
                        let aligned = !intersection.isNull && intersection.width*intersection.height >= expected.width*expected.height*0.5
                        let obstructed = rects.indices.contains { other in
                            guard other > index else { return false }
                            let overlap = rects[other].intersection(actual)
                            return !overlap.isNull && overlap.width*overlap.height > actual.width*actual.height*0.15
                        }
                        nowCovered = aligned && !obstructed
                    }
                    if nowCovered && firstVisible == nil { firstVisible = ProcessInfo.processInfo.systemUptime-began }
                    if covered && !nowCovered { dropped = true }
                    covered = covered || nowCovered
                    try await Task.sleep(nanoseconds:50_000_000)
                }
                pages.append(["source":text,"coveredWithinHold":covered,"sameSourceDropped":dropped,"secondsToFirstOverlay":firstVisible ?? -1])
            }
            report["pages"] = pages; report["observedFrames"] = observedFrames; report["oversizedOverlayFrames"] = oversizedFrames
            report["completedPages"] = pages.filter { $0["coveredWithinHold"] as? Bool == true }.count
            report["unexpectedControlTranslations"] = model.history.filter { ["表情log","星南","手毬"].contains($0.source) }.map { ["source":$0.source,"translation":$0.translation] }
            report["translations"] = model.history.map { ["source":$0.source,"translation":$0.translation] }
            report["passed"] = report["completedPages"] as? Int == texts.count && oversizedFrames == 0 && model.history.allSatisfy { !["表情log","星南","手毬"].contains($0.source) } && !pages.contains { $0["sameSourceDropped"] as? Bool == true }
        } catch { report["passed"] = false; report["error"] = error.localizedDescription }
        try? JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:outputFolder.appendingPathComponent("continuous-dialogue-test.json"))
    }
}
