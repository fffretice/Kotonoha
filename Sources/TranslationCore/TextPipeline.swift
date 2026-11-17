import Foundation
import CoreGraphics

public struct RecognizedLine: Equatable, Sendable {
    public var text: String
    /// Normalized bottom-left Vision coordinates.
    public var rect: CGRect
    public var confidence: Float
    public init(text: String, rect: CGRect, confidence: Float) {
        self.text = text; self.rect = rect; self.confidence = confidence
    }
}

public enum TextTools {
    public static func signature(_ lines: [RecognizedLine]) -> String {
        lines.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.joined(separator: "\n")
    }
    public static func containsJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3040...0x30ff).contains($0.value) || (0x3400...0x9fff).contains($0.value) || (0xff66...0xff9f).contains($0.value) }
    }
    public static func cleanTranslation(_ text: String) -> String {
        let pattern = "(?s)<think>.*?</think>"
        return text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            .replacingOccurrences(of: "```(?:json)?\\s*|```", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public static func appKitRect(_ normalized: CGRect, in region: CGRect) -> CGRect {
        CGRect(x: region.minX + normalized.minX * region.width,
               y: region.minY + normalized.minY * region.height,
               width: normalized.width * region.width, height: normalized.height * region.height)
    }
}

/// Requires a quiet interval AND two observations; old results are invalidated immediately.
public struct StabilityGate: Sendable {
    public private(set) var current = ""
    public private(set) var revision: UInt64 = 0
    private var changedAt: TimeInterval = 0
    private var observations = 0
    public init() {}
    @discardableResult public mutating func observe(_ signature: String, at time: TimeInterval) -> Bool {
        if signature != current {
            current = signature; changedAt = time; observations = 1; revision &+= 1
            return true
        }
        observations += 1
        return false
    }
    public func ready(at time: TimeInterval, delay: TimeInterval) -> Bool {
        !current.isEmpty && observations >= 2 && time - changedAt >= delay
    }
}

public struct TranslationCache: Sendable {
    private var entries: [String: String] = [:]
    private var order: [String] = []
    public var capacity: Int
    public init(capacity: Int = 300) { self.capacity = max(1, capacity) }
    public subscript(key: String) -> String? { entries[key] }
    public mutating func put(_ value: String, for key: String) {
        order.removeAll { $0 == key }; order.append(key); entries[key] = value
        while order.count > capacity { entries.removeValue(forKey: order.removeFirst()) }
    }
    public mutating func clear() { entries = [:]; order = [] }
}

/// Joins only nearby, aligned text rows. Independent bubbles and labels retain their own bounds.
public enum TextLayout {
    public static func groups(_ lines: [RecognizedLine], canvas: CGSize, separateLines: Bool = false) -> [[RecognizedLine]] {
        guard !separateLines else { return lines.map { [$0] } }
        let sorted = lines.sorted {
            if abs($0.rect.midY - $1.rect.midY) > min($0.rect.height, $1.rect.height) * 0.5 { return $0.rect.midY > $1.rect.midY }
            return $0.rect.minX < $1.rect.minX
        }
        var rows: [RecognizedLine] = []
        for line in sorted {
            if let i = rows.indices.last(where: { index in
                let previous = TextTools.appKitRect(rows[index].rect,in:CGRect(origin:.zero,size:canvas))
                let current = TextTools.appKitRect(line.rect,in:CGRect(origin:.zero,size:canvas))
                let h = min(previous.height,current.height)
                let gap = current.minX-previous.maxX
                return abs(previous.midY-current.midY) < h*0.4 && gap >= -h*0.2 && gap <= h*1.5
            }) {
                rows[i].text += line.text
                rows[i].rect = rows[i].rect.union(line.rect)
                rows[i].confidence = min(rows[i].confidence,line.confidence)
            } else { rows.append(line) }
        }
        var result: [[RecognizedLine]] = []
        for line in rows {
            let r = TextTools.appKitRect(line.rect, in: CGRect(origin: .zero, size: canvas))
            var match: Int?
            for i in result.indices.reversed() {
                guard let last = result[i].last, result[i].count < 6 else { continue }
                let previous = TextTools.appKitRect(last.rect, in: CGRect(origin: .zero, size: canvas))
                let height = min(previous.height, r.height)
                let gap = previous.minY - r.maxY
                let ratio = max(previous.height, r.height) / max(1, height)
                let hasHiragana = last.text.unicodeScalars.contains { (0x3040...0x309f).contains($0.value) }
                let hasSentenceMark = last.text.contains { "。！？!?、，…「」".contains($0) }
                let shortLabel = result[i].count == 1 && last.text.count <= 8 && !hasHiragana && !hasSentenceMark && previous.width < previous.height * 4.5 && r.width > r.height * 7
                if height > 0 && gap >= -height * 0.15 && gap <= height * 0.65 &&
                    abs(previous.minX - r.minX) <= height * 0.8 && ratio < 1.45 && !shortLabel {
                    match = i; break
                }
            }
            if let match { result[match].append(line) } else { result.append([line]) }
        }
        return result
    }
}

public enum OCRText {
    /// Ignore layout and punctuation noise, but retain every letter/number (including negations).
    public static func key(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }
    public static func isExtension(_ previous: String, _ current: String) -> Bool {
        let a = key(previous), b = key(current)
        return !a.isEmpty && b.count > a.count && b.hasPrefix(a)
    }
    public static func mayReuseTranslation(_ previous: String, _ current: String) -> Bool {
        let a=key(previous), b=key(current)
        if a == b { return true }
        // Keeping a translated prefix visible is different from caching it as the full sentence.
        if DialogueContinuity.isAppending(previous:a,current:b) || DialogueContinuity.isAppending(previous:b,current:a) { return false }
        guard !a.isEmpty,!b.isEmpty,!a.hasPrefix(b),!b.hasPrefix(a),
              abs(a.count-b.count) <= max(2,min(a.count,b.count)/10) else { return false }
        return sameGrowingPhrase(a,b)
    }
    public static func sameGrowingPhrase(_ a: String, _ b: String) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a.hasPrefix(b) || b.hasPrefix(a) { return true }
        let x = Array(a.prefix(500)), y = Array(b.prefix(500))
        return withinEdits(x,y,limit:Int(Double(max(x.count,y.count))*0.35))
    }
    /// Banded distance bounds OCR matching work when long dialogue pages keep growing.
    static func withinEdits(_ x: [Character], _ y: [Character], limit: Int) -> Bool {
        guard abs(x.count-y.count) <= limit else { return false }
        let infinity = limit+1
        var previous = Array(repeating:infinity,count:y.count+1)
        for j in 0...min(y.count,limit) { previous[j] = j }
        if x.isEmpty { return y.count <= limit }
        for i in 1...x.count {
            var next = Array(repeating:infinity,count:y.count+1)
            if i <= limit { next[0] = i }
            let lower = max(1,i-limit), upper = min(y.count,i+limit)
            var best = next[0]
            if lower <= upper {
                for j in lower...upper {
                    next[j] = min(next[j-1]+1,previous[j]+1,previous[j-1]+(x[i-1] == y[j-1] ? 0:1))
                    best = min(best,next[j])
                }
            }
            if best > limit { return false }
            previous = next
        }
        return previous[y.count] <= limit
    }
}

/// A dialogue page may append rows for many seconds. This never authorizes reusing a prefix as a full translation.
public enum DialogueContinuity {
    public static func isAppending(previous: String, current: String) -> Bool {
        let a=Array(OCRText.key(previous)), b=Array(OCRText.key(current))
        guard !a.isEmpty, b.count > a.count else { return false }
        if b.starts(with:a) { return true }
        // OCR can change one or two existing glyphs when the next row appears.
        guard a.count >= 10 else { return false }
        let tolerance=min(3,max(2,a.count/20))
        for length in max(1,a.count-tolerance)...min(b.count-1,a.count+tolerance) {
            let prefix=Array(b.prefix(length))
            if OCRText.withinEdits(a,prefix,limit:tolerance) { return true }
        }
        return false
    }
}

/// Independent text regions cannot reset one another's waiting interval.
public enum TextTimingMode: String, CaseIterable, Sendable {
    case automatic, subtitles, typewriter
    public var title: String {
        switch self { case .automatic:return "自动识别";case .subtitles:return "实时字幕";case .typewriter:return "逐字对白" }
    }
}

public struct RegionReadiness {
    private struct Track {
        var rect: CGRect; var key: String; var first: Double; var quiet: Double; var last: Double; var samples: Int; var longest: Int; var lastGrowth: Double; var typing: Bool
    }
    private var tracks: [Track] = []
    public init() {}
    public mutating func observe(_ lines: [RecognizedLine], at time: Double, delay: Double, mode: TextTimingMode = .automatic) -> [Bool] {
        tracks.removeAll { time - $0.last > 0.8 }
        var used = Set<Int>()
        return lines.map { line in
            let key = OCRText.key(line.text)
            let match = tracks.indices.filter { !used.contains($0) }.max { lhs,rhs in
                score(tracks[lhs], line.rect, key) < score(tracks[rhs], line.rect, key)
            }
            let index: Int
            if let match, score(tracks[match],line.rect,key) > 0.3 {
                index = match
                var track = tracks[index]
                if track.key != key {
                    if !OCRText.sameGrowingPhrase(track.key,key) {
                        track.first = time; track.samples = 0; track.longest = key.count; track.typing = false; track.lastGrowth = time
                    } else if key.count > track.longest {
                        track.longest = key.count; track.lastGrowth = time
                        if key.hasPrefix(track.key) || key.count-track.key.count >= 2 { track.typing = true }
                    }
                    track.quiet = time
                }
                track.key = key; track.rect = line.rect; track.samples += 1; track.last = time; tracks[index] = track
            } else {
                tracks.append(Track(rect:line.rect,key:key,first:time,quiet:time,last:time,samples:1,longest:key.count,lastGrowth:time,typing:false)); index = tracks.count-1
            }
            used.insert(index)
            let track = tracks[index]
            let typing = mode == .typewriter || (mode == .automatic && track.typing)
            // A confidently recognized complete sentence can start before another expensive OCR pass.
            if mode != .typewriter && delay <= 0.12 && line.confidence >= 0.85 && key.count >= 8 && TextReadiness.endsSentence(line.text) { return true }
            if typing {
                return !key.isEmpty && track.samples >= 2 && (time-track.quiet >= max(TextReadiness.endsSentence(line.text) ? 0.12 : 0.30,delay) || time-track.lastGrowth >= 1.0)
            }
            return !key.isEmpty && track.samples >= 2 && (time-track.quiet >= delay || time-track.first >= max(0.45, delay))
        }
    }
    private func score(_ track: Track, _ rect: CGRect, _ key: String) -> Double {
        let intersection = track.rect.intersection(rect)
        let overlap = intersection.isNull ? 0 : intersection.width * intersection.height / max(0.000001,min(track.rect.width*track.rect.height, rect.width*rect.height))
        return Double(overlap) + (track.key == key && overlap > 0 ? 1 : 0)
    }
}

public enum OverlayContinuity {
    /// Short OCR glitches get a bounded grace period. Unrelated new subtitles clear immediately.
    public static func keep(previous: String, current: String?, age: Double) -> Bool {
        guard age >= 0, age <= 0.8 else { return false }
        guard let current, !current.isEmpty else { return true }
        let a = OCRText.key(previous), b = OCRText.key(current)
        if a == b { return true }
        if min(a.count,b.count) >= 12 && Double(min(a.count,b.count))/Double(max(a.count,b.count)) >= 0.6 && (a.contains(b) || b.contains(a)) { return true }
        guard min(a.count,b.count) >= 16, abs(a.count-b.count) <= 1 else { return false }
        let x = Array(a), y = Array(b)
        var i=0,j=0,edits=0
        while i<x.count && j<y.count {
            if x[i] == y[j] { i+=1;j+=1;continue }
            edits+=1; if edits>1 { return false }
            if x.count >= y.count { i+=1 }; if y.count >= x.count { j+=1 }
        }
        return edits + (x.count-i) + (y.count-j) <= 1
    }
}

/// A terminal mark can shorten the quiet interval without guessing an unfinished clause.
public enum TextReadiness {
    public static func endsSentence(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn:"」』）)\"")))
        guard let last = trimmed.last else { return false }
        return "。！？!?".contains(last)
    }
}
