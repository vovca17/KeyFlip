import XCTest
@testable import SwitcherCore

final class LayoutTests: XCTestCase {
    func testRequiredWordsOverrideRecognitionAndPreserveCase() {
        let words: Set<String> = ["крч", "foobar"]
        XCTAssertEqual(RequiredWords.candidate("rhx", spellings: words), "крч")
        XCTAssertEqual(RequiredWords.candidate("Rhx", spellings: words), "Крч")
        XCTAssertEqual(RequiredWords.candidate("RHX", spellings: words), "КРЧ")
        XCTAssertEqual(RequiredWords.candidate("ащщифк", spellings: words), "foobar")
        XCTAssertNil(RequiredWords.candidate("крч", spellings: words))
        XCTAssertNil(RequiredWords.candidate("КРЧ", spellings: words))
        XCTAssertNil(RequiredWords.candidate("foobar", spellings: words))
        XCTAssertNil(RequiredWords.candidate("rhx", spellings: []))
        XCTAssertNil(RequiredWords.candidate("rhx", spellings: ["крч", "rhx"]))
    }
    func testRequiredWordsValidation() {
        XCTAssertEqual(RequiredWords.normalized("КРЧ"), "крч")
        XCTAssertEqual(RequiredWords.normalized("FooBar"), "foobar")
        XCTAssertNil(RequiredWords.normalized(""))
        XCTAssertNil(RequiredWords.normalized("два слова"))
        XCTAssertNil(RequiredWords.normalized("test123"))
        XCTAssertNil(RequiredWords.normalized("testмир"))
        XCTAssertNil(RequiredWords.normalized(String(repeating: "x", count: 41)))
    }
    func testConfigurableModifierGesture() {
        for choice in Shortcut.choices {
            var gesture = RightOptionGesture(keyCode: choice.keyCode)
            XCTAssertFalse(gesture.changed(keyCode: choice.keyCode, rightDown: true, otherModifiers: false))
            XCTAssertTrue(gesture.changed(keyCode: choice.keyCode, rightDown: false, otherModifiers: false))
            XCTAssertFalse(gesture.changed(keyCode: choice.keyCode, rightDown: true, otherModifiers: false))
            gesture.cancel()
            XCTAssertFalse(gesture.changed(keyCode: choice.keyCode, rightDown: false, otherModifiers: false))
        }
    }
    func testRepeatedAutomaticUndoAndExceptions() {
        var tracker = MistakeTracker()
        XCTAssertNil(tracker.recordAutomaticUndo("ghbdtn"))
        XCTAssertNil(tracker.recordAutomaticUndo("GHBDTN"))
        XCTAssertEqual(tracker.recordAutomaticUndo("ghbdtn"), "ghbdtn")
        XCTAssertNil(tracker.recordAutomaticUndo("ghbdtn"))
        XCTAssertNil(tracker.recordAutomaticUndo("other"))
        XCTAssertTrue(MistakeTracker.isExcluded("GHBDTN", in: ["ghbdtn"]))
        XCTAssertFalse(MistakeTracker.isExcluded("hello", in: ["ghbdtn"]))
        XCTAssertNil(tracker.recordAutomaticUndo("two words"))
    }
    func testRightOptionAloneAndChords() {
        var gesture = RightOptionGesture()
        XCTAssertFalse(gesture.changed(keyCode: 61, rightDown: true, otherModifiers: false))
        XCTAssertTrue(gesture.changed(keyCode: 61, rightDown: false, otherModifiers: false))
        XCTAssertFalse(gesture.changed(keyCode: 61, rightDown: false, otherModifiers: false))
        XCTAssertFalse(gesture.changed(keyCode: 58, rightDown: false, otherModifiers: false))
        XCTAssertFalse(gesture.changed(keyCode: 61, rightDown: true, otherModifiers: false))
        gesture.cancel() // another key or mouse click while Option is held
        XCTAssertFalse(gesture.changed(keyCode: 61, rightDown: false, otherModifiers: false))
        XCTAssertFalse(gesture.changed(keyCode: 61, rightDown: true, otherModifiers: true))
        XCTAssertFalse(gesture.changed(keyCode: 61, rightDown: false, otherModifiers: false))
        XCTAssertFalse(gesture.changed(keyCode: 61, rightDown: true, otherModifiers: false))
        XCTAssertFalse(gesture.changed(keyCode: 56, rightDown: true, otherModifiers: true))
        XCTAssertFalse(gesture.changed(keyCode: 61, rightDown: false, otherModifiers: false))
    }
    func testNamesInBothLayouts() {
        XCTAssertEqual(Names.candidate("мдфвшьшк"), "vladimir")
        XCTAssertEqual(Names.candidate("dkflbvbh"), "владимир")
        XCTAssertEqual(Names.candidate("Мдфвшьшк"), "Vladimir")
        XCTAssertEqual(Names.candidate("DKFLBVBH"), "ВЛАДИМИР")
        XCTAssertNil(Names.candidate("vladimir"))
        XCTAssertNil(Names.candidate("владимир"))
        XCTAssertNil(Names.candidate("hello"))
        XCTAssertNil(Names.candidate("test123"))
        XCTAssertNil(Names.candidate("ыукуку"))
        XCTAssertEqual(Names.candidate("ыукуку", additional: ["Serere"]), "serere")
    }
    func testEmailInWrongLayout() {
        XCTAssertEqual(Layout.emailCandidate("мдфвшьшкюыфнфзшту\"пьфшдюсщь"), "vladimir.sayapine@gmail.com")
        XCTAssertEqual(Layout.emailCandidate("еуые123\"пьфшдюсщь"), "test123@gmail.com")
        XCTAssertEqual(Layout.emailCandidate("еуые@пьфшдюсщь"), "test@gmail.com")
        XCTAssertNil(Layout.emailCandidate("vladimir.sayapine@gmail.com"))
        XCTAssertNil(Layout.emailCandidate("привет\"мир"))
        XCTAssertNil(Layout.emailCandidate("еуые\"\"пьфшдюсщь"))
        XCTAssertNil(Layout.emailCandidate("еуые\"пьфшд"))
        XCTAssertNil(Layout.emailCandidate("еуые\"-пьфшдюсщь"))
    }
    func testConversion() {
        XCTAssertEqual(Layout.convert("ghbdtn"), "привет")
        XCTAssertEqual(Layout.convert("руддщ"), "hello")
        XCTAssertEqual(Layout.convert("Ghbdtn!"), "Привет!")
        XCTAssertEqual(Layout.convert("ёжик"), "`;br")
        XCTAssertEqual(Layout.convert("hello\nworld 123 😀"), "руддщ\nцщкдв 123 😀")
        XCTAssertEqual(Layout.convert(Layout.convert("Привет, мир!")), "Привет, мир!")
    }
    func testConservativeCandidates() {
        XCTAssertNil(Layout.autoCandidate("gh"))
        XCTAssertNil(Layout.autoCandidate("user_id"))
        XCTAssertNil(Layout.autoCandidate("test123"))
        XCTAssertNil(Layout.autoCandidate("helloмир"))
        XCTAssertEqual(Layout.autoCandidate("ghbdtn"), "привет")
        XCTAssertEqual(Layout.autoCandidate("руддщ"), "hello")
    }
    func testWordRangesUseUTF16AndKeepWhitespace() {
        let text = "😀 ghbdtn  "
        XCTAssertEqual(Layout.lastWord(in: text, before: (text as NSString).length), NSRange(location: 3, length: 6))
        XCTAssertNil(Layout.lastWord(in: "  ", before: 2))
        XCTAssertNil(Layout.lastWord(in: "abc", before: -1))
        XCTAssertEqual(Layout.lastWord(in: "one two", before: 3), NSRange(location: 0, length: 3))
    }
}

final class TypedWordTests: XCTestCase {
    func testFindsWordWithoutTail() {
        XCTAssertEqual(TypedWord.range(of: "ghbdtn", tail: "", in: "ok ghbdtn ", caret: 10), NSRange(location: 3, length: 6))
    }
    func testFindsWordWhenTypingContinued() {
        XCTAssertEqual(TypedWord.range(of: "ghbdtn", tail: "rfr", in: "ghbdtn rfr", caret: 10), NSRange(location: 0, length: 6))
    }
    func testFieldLaggingBehindKeyboard() {
        XCTAssertEqual(TypedWord.range(of: "ghbdtn", tail: "rfr", in: "ghbdtn r", caret: 8), NSRange(location: 0, length: 6))
    }
    func testRejectsPartOfLongerWordAndChangedText() {
        XCTAssertNil(TypedWord.range(of: "ghbdtn", tail: "", in: "xghbdtn ", caret: 8))
        XCTAssertNil(TypedWord.range(of: "ghbdtn", tail: "rfr", in: "ghbdtn rfx", caret: 10))
        XCTAssertNil(TypedWord.range(of: "ghbdtn", tail: "", in: "ghbdtn", caret: 6))
    }
    func testCaretInMiddleOfText() {
        XCTAssertEqual(TypedWord.range(of: "ghbdtn", tail: "", in: "ghbdtn end", caret: 7), NSRange(location: 0, length: 6))
    }
}

final class ShortWordTests: XCTestCase {
    func testCommonShortWords() {
        XCTAssertEqual(ShortWords.candidate("rfr"), "как")
        XCTAssertEqual(ShortWords.candidate("yt"), "не")
        XCTAssertEqual(ShortWords.candidate("Xnj"), "Что")
        XCTAssertEqual(ShortWords.candidate("еру"), "the")
        XCTAssertEqual(ShortWords.candidate(";t"), "же")
        XCTAssertNil(ShortWords.candidate("z"))
        XCTAssertEqual(ShortWords.candidate("z", allowSingle: true), "я")
        XCTAssertNil(ShortWords.candidate("как"))
        XCTAssertNil(ShortWords.candidate("the"))
        XCTAssertNil(ShortWords.candidate("vs"))
        XCTAssertNil(ShortWords.candidate("шт"))
    }
    /// A listed word must never look like a real word of the other language.
    func testListsDoNotCollide() {
        for word in ShortWords.russian {
            let typed = Layout.convert(word)
            XCTAssertFalse(ShortWords.english.contains(typed) || ShortWords.englishKeep.contains(typed), "\(word) ↔ \(typed)")
        }
        for word in ShortWords.english {
            let typed = Layout.convert(word)
            XCTAssertFalse(ShortWords.russian.contains(typed) || ShortWords.russianKeep.contains(typed), "\(word) ↔ \(typed)")
        }
    }
    func testInvertedCase() {
        XCTAssertEqual(Layout.fixInvertedCase("пРИВЕТ"), "Привет")
        XCTAssertEqual(Layout.fixInvertedCase("hELLO"), "Hello")
        XCTAssertEqual(Layout.fixInvertedCase(Layout.convert("gHBDTN")), "Привет")
        XCTAssertNil(Layout.fixInvertedCase("ПРИВЕТ"))
        XCTAssertNil(Layout.fixInvertedCase("привет"))
        XCTAssertNil(Layout.fixInvertedCase("iPhone"))
        XCTAssertNil(Layout.fixInvertedCase("пР"))
    }
    func testExtendLeftStopsAtKnownWordAndLine() {
        let text = "hello z rfr ltkf"
        let last = NSRange(location: 12, length: 4)
        let range = Layout.extendLeft(last, in: text) { $0 != "hello" }
        XCTAssertEqual((text as NSString).substring(with: range), "z rfr ltkf")
        XCTAssertEqual(Layout.convertWords("z rfr ltkf"), "я как дела")
        let lines = "rfr\nltkf"
        XCTAssertEqual(Layout.extendLeft(NSRange(location: 4, length: 4), in: lines) { _ in true }, NSRange(location: 4, length: 4))
    }
}
