import Foundation
import CoreGraphics

public enum DialogueText {
    public static func isLabelOrControl(_ line: RecognizedLine, among lines: [RecognizedLine]) -> Bool {
        let text = line.text.trimmingCharacters(in:.whitespacesAndNewlines)
        let key = OCRText.key(text).lowercased()
        let controls: Set<String> = ["表情log","表情iog","表情1og","表情lo9","表情ログ","早送り","スキップ","ログ","オート","skip","auto"]
        if line.rect.maxY < 0.2 && controls.contains(key) { return true }
        let kana = text.unicodeScalars.contains { (0x3040...0x30ff).contains($0.value) }
        let punctuation = text.contains { "。！？!?、，…「」（）()".contains($0) }
        guard !kana, !punctuation, key.count <= 6 else { return false }
        // A short kanji name immediately above dialogue remains in the original game typography.
        return lines.contains { body in
            let gap = line.rect.minY-body.rect.maxY
            let hasKana = body.text.unicodeScalars.contains { (0x3040...0x30ff).contains($0.value) }
            let nameGeometry = line.rect.height < body.rect.height*0.87 || gap > line.rect.height*0.65
            return hasKana && nameGeometry && gap >= -line.rect.height*0.4 && gap < max(0.035,line.rect.height*3) &&
                abs(body.rect.minX-line.rect.minX) < max(0.1,line.rect.height*4)
        }
    }
}
