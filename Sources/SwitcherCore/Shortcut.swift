public struct Shortcut: Equatable, Sendable {
    public let id: String
    public let title: String
    public let keyCode: Int64
    public let deviceMask: UInt64
    public let modifierMask: UInt64
    public static let choices: [Shortcut] = [
        .init(id: "rightOption", title: "Правый Option", keyCode: 61, deviceMask: 0x40, modifierMask: 1 << 19),
        .init(id: "leftOption", title: "Левый Option", keyCode: 58, deviceMask: 0x20, modifierMask: 1 << 19),
        .init(id: "rightCommand", title: "Правый Command", keyCode: 54, deviceMask: 0x10, modifierMask: 1 << 20),
        .init(id: "leftCommand", title: "Левый Command", keyCode: 55, deviceMask: 0x8, modifierMask: 1 << 20),
        .init(id: "rightControl", title: "Правый Control", keyCode: 62, deviceMask: 0x2000, modifierMask: 1 << 18),
        .init(id: "leftControl", title: "Левый Control", keyCode: 59, deviceMask: 0x1, modifierMask: 1 << 18)
    ]
}

public struct MistakeTracker {
    private var counts: [String: Int] = [:]
    private var offered: Set<String> = []
    public init() {}
    public mutating func recordAutomaticUndo(_ word: String) -> String? {
        let key = word.lowercased()
        guard !key.isEmpty, key.count <= 254, !key.contains(where: \.isWhitespace), !offered.contains(key) else { return nil }
        // Keep a bounded session-only history, never a typing log.
        if counts.count >= 100, counts[key] == nil { counts.removeAll() }
        counts[key, default: 0] += 1
        guard counts[key, default: 0] >= 3 else { return nil }
        offered.insert(key)
        return key
    }
    public static func isExcluded(_ word: String, in words: Set<String>) -> Bool {
        words.contains(word.lowercased())
    }
}
