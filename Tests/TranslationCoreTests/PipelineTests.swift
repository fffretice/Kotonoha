import XCTest
@testable import TranslationCore
final class PipelineTests: XCTestCase {
    func testTypingAndStaleResults() {
        var gate = StabilityGate()
        XCTAssertTrue(gate.observe("こんにちは", at: 0))
        let first = gate.revision
        XCTAssertFalse(gate.ready(at: 0.8, delay: 0.5))
        gate.observe("こんにちは", at: 0.8)
        XCTAssertTrue(gate.ready(at: 0.8, delay: 0.5))
        gate.observe("こんにちは、先生", at: 0.9)
        XCTAssertNotEqual(gate.revision, first)
        XCTAssertFalse(gate.ready(at: 1.0, delay: 0.5))
        gate.observe("", at: 2)
        gate.observe("", at: 3)
        XCTAssertFalse(gate.ready(at: 3, delay: 0.5))
    }
    func testCoordinateMappingAcrossDisplays() {
        let r = TextTools.appKitRect(CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.1), in: CGRect(x: -1440, y: -200, width: 1000, height: 500))
        XCTAssertEqual(r, CGRect(x: -1340, y: -100, width: 500, height: 50))
    }
    func testCacheEvictionAndReplacement() {
        var c = TranslationCache(capacity: 2)
        c.put("甲", for: "a"); c.put("乙", for: "b"); c.put("丙", for: "a"); c.put("丁", for: "c")
        XCTAssertEqual(c["a"], "丙"); XCTAssertNil(c["b"])
        c.clear(); XCTAssertNil(c["a"])
    }
    func testJapaneseAndThinkingCleanup() {
        XCTAssertTrue(TextTools.containsJapanese("放課後"))
        XCTAssertFalse(TextTools.containsJapanese("123 FPS"))
        XCTAssertEqual(TextTools.cleanTranslation("<think>reason\nmore</think>\n放学后"), "放学后")
    }
}
