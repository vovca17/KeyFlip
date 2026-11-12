import Foundation

/// Frequent words shorter than four letters. The spell checker cannot judge
/// them reliably, so only listed words are corrected automatically.
public enum ShortWords {
    public static let russian: Set<String> = words("""
    я и в к с у о а
    не на но он вы ты да по за из от до же ли бы ко со то их ее её им ей уж ну ой ах эх ок
    нет вот так как что кто где все всё уже еще ещё тут там мне мой моя мои мое моё наш ваш его она они оно
    для без при про под над или чем тем кем чей раз два три сам том той тот эта это эти эту
    вам нам вас нас них ним ней был ага иди дай мол лет год ура щас чё зря имя
    """)

    public static let english: Set<String> = words("""
    i a
    is it on to of at as be by do go he if me my no or so up us we am an ok hi
    the and for you are not but all can get has had was his her how now new one our out see she two way who why
    yes yet its did let use any ask got may say too off own hey bye lol thx pls app bug fix run web api url
    """)

    /// Never converted automatically: abbreviations that collide with a mistyped word.
    /// «мы» (vs), «во» (dj) and «in» (шт) are left out of the lists for the same reason.
    public static let russianKeep: Set<String> = words("шт гг мм км кг см рф тд тп др")
    public static let englishKeep: Set<String> = words("vs dj")

    private static func words(_ text: String) -> Set<String> {
        Set(text.split(whereSeparator: \.isWhitespace).map(String.init))
    }

    /// Returns the word in the other layout when it is a listed short word.
    /// Single letters are ambiguous on their own; allow them only with context.
    public static func candidate(_ word: String, allowSingle: Bool = false) -> String? {
        let length = word.count
        guard length >= (allowSingle ? 1 : 2), length <= 3 else { return nil }
        let russian = Layout.isRussian(word)
        let own = word.lowercased()
        if russian ? (Self.russian.contains(own) || russianKeep.contains(own))
                   : (english.contains(own) || englishKeep.contains(own)) { return nil }
        let converted = Layout.convert(word)
        guard converted != word, converted.allSatisfy(\.isLetter) else { return nil }
        return (russian ? english : Self.russian).contains(converted.lowercased()) ? converted : nil
    }
}

extension Layout {
    /// Caps Lock typing: «пРИВЕТ» → «Привет». Needs a lowercase first letter
    /// and at least two uppercase letters after it, nothing in lowercase.
    public static func fixInvertedCase(_ word: String) -> String? {
        let letters = word.filter(\.isLetter)
        guard let first = letters.first, first.isLowercase,
              letters.dropFirst().count >= 2, letters.dropFirst().allSatisfy(\.isUppercase) else { return nil }
        var done = false
        return String(word.map { character -> Character in
            guard character.isLetter else { return character }
            defer { done = true }
            return Character(done ? character.lowercased() : character.uppercased())
        })
    }

    /// Extends `range` (a word) to the left over words on the same line that `accept` approves.
    public static func extendLeft(_ range: NSRange, in text: String, limit: Int = 20, accept: (String) -> Bool) -> NSRange {
        let value = text as NSString
        var start = range.location
        for _ in 0..<limit {
            var gapStart = start
            while gapStart > 0 {
                let c = value.character(at: gapStart - 1)
                guard c == 0x20 || c == 0x09 || c == 0xA0 else { break }
                gapStart -= 1
            }
            guard gapStart < start, gapStart > 0 else { break }
            var wordStart = gapStart
            while wordStart > 0, let scalar = Unicode.Scalar(value.character(at: wordStart - 1)),
                  !CharacterSet.whitespacesAndNewlines.contains(scalar) { wordStart -= 1 }
            let word = value.substring(with: NSRange(location: wordStart, length: gapStart - wordStart))
            guard accept(word) else { break }
            start = wordStart
        }
        return NSRange(location: start, length: NSMaxRange(range) - start)
    }

    /// Converts every word in `text`, keeping the separators.
    public static func convertWords(_ text: String) -> String {
        text.split(separator: " ", omittingEmptySubsequences: false).map { convert(String($0)) }.joined(separator: " ")
    }
}
