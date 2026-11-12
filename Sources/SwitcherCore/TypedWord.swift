import Foundation

/// Locates a word that was finished with a space while the user may already
/// have typed more text after it (`tail`). The field can lag behind the
/// keyboard, so any prefix of the tail is accepted, longest first.
public enum TypedWord {
    public static func range(of word: String, tail: String, in text: String, caret: Int) -> NSRange? {
        let value = text as NSString
        guard !word.isEmpty, caret >= 0, caret <= value.length else { return nil }
        let before = value.substring(to: caret)
        let wordLength = (word as NSString).length
        var tails = [Substring]()
        var index = tail.endIndex
        while true {
            tails.append(tail[..<index])
            if index == tail.startIndex { break }
            index = tail.index(before: index)
        }
        for typed in tails {
            let suffix = word + " " + typed
            guard before.hasSuffix(suffix) else { continue }
            let start = caret - (suffix as NSString).length
            if start > 0 {
                let previous = value.substring(with: NSRange(location: start - 1, length: 1))
                guard previous.rangeOfCharacter(from: .whitespacesAndNewlines) != nil else { continue }
            }
            return NSRange(location: start, length: wordLength)
        }
        return nil
    }
}
