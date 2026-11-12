/// Track a standalone press; any chord, click or focus change cancels it.
public struct RightOptionGesture {
    private var armed = false
    private let keyCode: Int64
    public init(keyCode: Int64 = 61) { self.keyCode = keyCode }
    public mutating func cancel() { armed = false }
    public mutating func changed(keyCode: Int64, rightDown: Bool, otherModifiers: Bool) -> Bool {
        guard keyCode == self.keyCode else { cancel(); return false }
        if rightDown { armed = !otherModifiers; return false }
        let trigger = armed && !otherModifiers
        armed = false
        return trigger
    }
}
