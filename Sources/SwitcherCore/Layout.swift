import Foundation

public enum Layout {
    private static let en = Array("`qwertyuiop[]asdfghjkl;'zxcvbnm,./~QWERTYUIOP{}ASDFGHJKL:\"ZXCVBNM<>?")
    private static let ru = Array("ёйцукенгшщзхъфывапролджэячсмитьбю.ЁЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,")
    private static let toRussian = Dictionary(uniqueKeysWithValues: zip(en, ru))
    private static let toEnglish = Dictionary(uniqueKeysWithValues: zip(ru, en))

    public static func isRussian(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x0400...0x04ff).contains($0.value) }
    }

    public static func convert(_ text: String) -> String {
        let map = isRussian(text) ? toEnglish : toRussian
        return String(text.map { map[$0] ?? $0 })
    }

    /// Recognize a whole mistyped RU-layout email; quotes elsewhere stay untouched.
    public static func emailCandidate(_ text: String) -> String? {
        guard isRussian(text), text.count <= 254 else { return nil }
        let candidate = convert(text).replacingOccurrences(of: "\"", with: "@")
        let parts = candidate.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[0].count <= 64,
              !parts[0].hasPrefix("."), !parts[0].hasSuffix("."), !parts[0].contains(".."),
              parts[0].utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || "._%+-".utf8.contains($0) }) else { return nil }
        let labels = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ label in
            !label.isEmpty && label.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-") &&
            label.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
        }), let tld = labels.last, tld.count >= 2,
              tld.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) }) else { return nil }
        return candidate
    }

    /// Auto mode deliberately ignores numbers, identifiers, mixed scripts and short words.
    public static func autoCandidate(_ text: String) -> String? {
        guard text.count >= 4, text.count <= 40 else { return nil }
        let latin = text.unicodeScalars.contains { (65...90).contains($0.value) || (97...122).contains($0.value) }
        guard !(latin && isRussian(text)),
              text.allSatisfy({ $0.isLetter || "[];',.`".contains($0) }) else { return nil }
        let converted = convert(text)
        guard converted != text, converted.allSatisfy(\.isLetter) else { return nil }
        return converted
    }

    /// UTF-16 offsets match the Accessibility API, including emoji before the word.
    public static func lastWord(in text: String, before caret: Int) -> NSRange? {
        let value = text as NSString
        guard caret >= 0, caret <= value.length else { return nil }
        let prefix = value.substring(to: caret) as NSString
        guard let regex = try? NSRegularExpression(pattern: "[^\\s]+(?=\\s*$)") else { return nil }
        return regex.matches(in: prefix as String, range: NSRange(location: 0, length: prefix.length)).last?.range
    }
}
