import Foundation

public enum TranslationProfile: String, Sendable {
    case general, sakura, galTransl, hy
    public static func detect(path: String) -> Self {
        let name = URL(fileURLWithPath:path).lastPathComponent.lowercased()
        if name.contains("galtransl") { return .galTransl }
        if name.contains("sakura") { return .sakura }
        if name.contains("hy-mt") || name.contains("hy_mt") { return .hy }
        return .general
    }
    public var usesPlainText: Bool { self != .general }
    public func messages(source: String, context: [(String,String)], glossary: String) -> [[String:String]] {
        let source = source.replacingOccurrences(of:"\n",with:"")
        let terms = String(glossary.prefix(1200)).trimmingCharacters(in:.whitespacesAndNewlines)
        if self == .hy {
            var user = terms.isEmpty ? "" : "参考术语表：\n\(terms)\n\n"
            if !context.isEmpty {
                let history: [String] = context.suffix(2).map { pair in
                    let ja = String(pair.0.prefix(200)), zh = String(pair.1.prefix(200))
                    return ja + "\n" + zh
                }
                user += "参考上文：\n" + history.joined(separator:"\n") + "\n\n"
            }
            user += "将以下日文准确翻译成自然的简体中文。保留人物关系、否定和时态，区分使役与被动的主语、宾语。不要添加人物或事实，只输出译文：\n\n" + source
            return [["role":"user","content":user]]
        }
        let system = "你是一个视觉小说翻译模型，可以通顺地使用给定的术语表将日文翻译成简体中文，并联系上下文正确使用人称代词，注意不要混淆使役态和被动态的主语和宾语，不要擅自添加原文中没有的事实、人物和特殊符号。只输出当前原文的完整译文。"
        var user = context.isEmpty ? "" : "历史翻译：\n" + context.suffix(2).map { String($0.1.prefix(200)) }.joined(separator:"\n") + "\n\n"
        if !terms.isEmpty { user += "参考以下术语表：\n\(terms)\n\n" }
        user += "将下面的文本从日文翻译成简体中文：\n" + source
        return [["role":"system","content":system],["role":"user","content":user]]
    }
    public static func isUsable(_ translation: String, source: String) -> Bool {
        let clean = translation.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !clean.isEmpty else { return false }
        let kana = clean.unicodeScalars.filter { (0x3040...0x30ff).contains($0.value) }.count
        // Names may retain kana, but copying most of a Japanese sentence is not a translation.
        if clean.count > 12 && kana >= 4 && Double(kana)/Double(clean.count) > 0.22 { return false }
        for leak in ["previous_dialogue", "texts 数组", "只翻译 texts", "具体人物和食物以本句为准", "条目数必须完全一致"] {
            if clean.contains(leak) && !source.contains(leak) { return false }
        }
        return true
    }
}
