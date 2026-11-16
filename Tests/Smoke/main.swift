import Foundation
import CoreGraphics
import TranslationCore
var failures = 0
var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { failures += 1; print("FAIL: \(message)") }
}
var gate = StabilityGate()
expect(gate.observe("こんにちは", at: 0), "new text changes revision")
let old = gate.revision
expect(!gate.ready(at: 0.8, delay: 0.5), "one observation never considered stable")
gate.observe("こんにちは", at: 0.8)
expect(gate.ready(at: 0.8, delay: 0.5), "quiet repeated text becomes ready")
gate.observe("こんにちは、先生", at: 0.9)
expect(gate.revision != old, "typing invalidates in-flight translation")
expect(!gate.ready(at: 1, delay: 0.5), "typing resets quiet interval")
gate.observe("", at: 2); gate.observe("", at: 3)
expect(!gate.ready(at: 3, delay: 0.5), "blank frames never translate")
var cache = TranslationCache(capacity: 2)
cache.put("甲", for: "a"); cache.put("乙", for: "b"); cache.put("丙", for: "a"); cache.put("丁", for: "c")
expect(cache["a"] == "丙", "cache replacement preserves newest value")
expect(cache["b"] == nil, "cache evicts oldest")
cache.clear(); expect(cache["a"] == nil, "glossary change can clear cached translations")
expect(TextTools.containsJapanese("放課後"), "kanji-only text is recognized")
expect(TextTools.containsJapanese("ｺﾝﾆﾁﾊ"), "halfwidth katakana is recognized")
expect(!TextTools.containsJapanese("123 FPS"), "numeric HUD is ignored")
expect(TextTools.cleanTranslation("<think>reason\nmore</think>\n放学后") == "放学后", "reasoning does not leak into overlay")
let r = TextTools.appKitRect(CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.1), in: CGRect(x: -1440, y: -200, width: 1000, height: 500))
expect(r == CGRect(x: -1340, y: -100, width: 500, height: 50), "negative-coordinate secondary display geometry")
let full = TextTools.appKitRect(CGRect(x: 0, y: 0, width: 1, height: 1), in: CGRect(x: 100, y: 100, width: 500, height: 300))
expect(full == CGRect(x: 100, y: 100, width: 500, height: 300), "full region geometry")
func row(_ text: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> RecognizedLine {
    RecognizedLine(text: text, rect: CGRect(x: x/800, y: y/1600, width: w/800, height: h/1600), confidence: 1)
}
let chat = [row("章節0",40,1450,160,30), row("カナエ",660,1120,85,20),
    row("入学試験で最後だったカナエさん。",250,1040,470,28),
    row("カナエ",660,900,85,20), row("歌も踊りもできない。",250,830,430,28),
    row("転んで泥だらけになった。",250,792,440,28),
    row("そんな彼女が笑顔で夢を追う。",250,500,440,28)]
let groups = TextLayout.groups(chat, canvas: CGSize(width:800,height:1600))
expect(groups.count == 6, "chat bubbles, chapter title, and names stay independent")
expect(groups.contains { $0.count == 2 }, "adjacent wrapped dialogue rows stay together")
expect(groups.allSatisfy { g in g.map(\.rect).reduce(CGRect.null) { $0.union($1) }.height * 1600 < 100 }, "no block bridges distant text across the screen")
expect(TextLayout.groups(chat, canvas: CGSize(width:800,height:1600), separateLines:true).count == 7, "manual per-line mode remains available")
let columns = [row("左の選択肢",40,800,200,28), row("右の選択肢",400,800,220,28)]
expect(TextLayout.groups(columns,canvas:CGSize(width:800,height:1600)).count == 2, "same-baseline columns never merge")
expect(OCRText.key("お嬢様、ご休憩です。") == OCRText.key("お嬢様 ご休憩です"), "punctuation noise does not invalidate translations")
expect(OCRText.key("行かない") != OCRText.key("行く"), "negation stays meaningful")
var independent = RegionReadiness()
let caption = row("お嬢様、ご休憩です。お茶をどうぞ。",40,400,650,30)
_ = independent.observe([caption,row("名前",650,300,80,20)],at:0,delay:0.18)
let readyIndependent = independent.observe([caption,row("別名",650,300,80,20)],at:0.2,delay:0.18)
expect(readyIndependent[0], "name changes never reset the subtitle gate")
var typing = RegionReadiness()
_ = typing.observe([row("お嬢様",40,400,650,30)],at:0,delay:0.18)
_ = typing.observe([row("お嬢様、ご休憩",40,400,650,30)],at:0.15,delay:0.18)
_ = typing.observe([row("お嬢様、ご休憩です",40,400,650,30)],at:0.3,delay:0.18)
expect(!typing.observe([caption],at:0.46,delay:0.18)[0], "typing growth must not trigger a premature translation")
expect(typing.observe([caption],at:0.95,delay:0.18)[0], "complete typed sentence becomes ready after a quiet interval")
expect(OverlayContinuity.keep(previous:"お嬢様ご休憩ですお茶をどうぞお願いします", current:"お嬢様ご休憩ですお茶をどうぞお願いしまし",age:0.2), "one character OCR glitch keeps visible text briefly")
expect(!OverlayContinuity.keep(previous:"お嬢様ご休憩ですお茶をどうぞお願いします", current:"明日は図書館で待っています",age:0.1), "new subtitle immediately removes old overlay")
expect(!OverlayContinuity.keep(previous:"お嬢様ご休憩ですお茶をどうぞお願いします", current:nil,age:0.9), "missing subtitles do not leave stale overlays")
expect(OverlayContinuity.keep(previous:"お茶をどうぞ",current:nil,age:0.5), "a missed OCR sample does not flash the overlay off")
let fragments = [row("お嬢様、ご休憩です。",40,800,300,28), row("お茶をどうぞ。",355,800,220,28)]
expect(TextLayout.groups(fragments,canvas:CGSize(width:800,height:1600)).count == 1,"nearby same-row OCR fragments form one subtitle")
expect(OverlayContinuity.keep(previous:"撮影スタッフの皆様よろしくお願いいたします",current:"スタッフの皆様よろしくお願いいたします",age:0.3), "temporarily missing OCR fragment does not erase the subtitle")
expect(!OCRText.mayReuseTranslation("３人で一緒にラーメンを", "３人で一緒にラーメンを食べたことを、ふと思い出してしまって。"), "prefix translation cannot poison the complete paragraph cache")
expect(!OCRText.mayReuseTranslation("えっ", "えっ美鈴なんで"), "short prefix cannot become full dialogue translation")
expect(OCRText.mayReuseTranslation("香名加が行ってくれた旅の素のおかげですわ", "香加が作ってくれた旅の薬のおかげですわ"), "small OCR errors still require and permit glyph evidence")
let paragraph = [row("はい。",40,800,70,28),row("なら、これはひとりごとです。",40,762,470,28)]
expect(TextLayout.groups(paragraph,canvas:CGSize(width:800,height:1600)).count == 1, "short dialogue acknowledgement joins its next sentence instead of becoming a speaker label")
var explicitTyping = RegionReadiness()
_ = explicitTyping.observe([caption],at:0,delay:0.12,mode:.typewriter)
expect(!explicitTyping.observe([caption],at:0.2,delay:0.12,mode:.typewriter)[0], "typewriter mode waits for full sentence")
expect(explicitTyping.observe([caption],at:0.5,delay:0.12,mode:.typewriter)[0], "typewriter mode eventually translates completed text")
var responsiveTyping = RegionReadiness()
_ = responsiveTyping.observe([caption],at:0,delay:0.12,mode:.typewriter)
expect(!responsiveTyping.observe([caption],at:0.25,delay:0.12,mode:.typewriter)[0], "a brief pause must not submit an unfinished typed sentence")
expect(responsiveTyping.observe([caption],at:0.31,delay:0.12,mode:.typewriter)[0], "completed typewriter text needs no extra 0.45 second delay")
var deliberateTyping = RegionReadiness()
_ = deliberateTyping.observe([caption],at:0,delay:0.6,mode:.typewriter)
expect(!deliberateTyping.observe([caption],at:0.4,delay:0.6,mode:.typewriter)[0], "user selected longer quiet wait still applies")
expect(DialogueContinuity.isAppending(previous:"通信魔法みたいなもので、",current:"通信魔法みたいなもので、思考を読み取られているとか。"), "same dialogue grows on the original row")
expect(DialogueContinuity.isAppending(previous:"通信魔法にいなもので、",current:"通魔法りいなもので、思考を読み取られているとか。\n体内に、音を拾うマジックアイテムを"), "recording OCR prefix noise does not erase an appended dialogue")
expect(!DialogueContinuity.isAppending(previous:"通信魔法みたいなもので、",current:"内通者……なるほどなぁ。"), "new speaker dialogue is a page replacement")
expect(!DialogueContinuity.isAppending(previous:"通信魔法みたいなもので、",current:"通信魔法"), "a cleared page restarting with a short fragment is not an append")
expect(!OCRText.mayReuseTranslation("通信魔法にいなもので", "通信魔法みにいなもので思"), "OCR-noisy append cannot cache the prefix as a full translation")
print("\(checks) checks, \(failures) failures")
exit(failures == 0 ? 0 : 1)
