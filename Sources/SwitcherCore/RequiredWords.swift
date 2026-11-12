/// User-approved spellings override dictionary recognition, never the user's exclusions.
public enum RequiredWords {
    public static func normalized(_ word: String) -> String? {
        guard (1...40).contains(word.count), word.unicodeScalars.allSatisfy({
            (65...90).contains($0.value) || (97...122).contains($0.value) ||
            (0x410...0x44f).contains($0.value) || $0.value == 0x401 || $0.value == 0x451
        }) else { return nil }
        let russian = Layout.isRussian(word)
        guard !russian || !word.unicodeScalars.contains(where: { (65...90).contains($0.value) || (97...122).contains($0.value) }) else { return nil }
        return word.lowercased()
    }

    public static func candidate(_ word: String, spellings: Set<String>) -> String? {
        guard !spellings.contains(word.lowercased()) else { return nil }
        let converted = Layout.convert(word)
        guard converted != word, normalized(converted) != nil,
              spellings.contains(converted.lowercased()) else { return nil }
        return converted
    }
}
