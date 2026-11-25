import Foundation

/// Own only a deliberate horizontal precision gesture. Ownership includes momentum,
/// even if the modifiers are released, so that it cannot leak into the underlying app.
struct ScrollGesture {
    private var owned = false
    private var rejected = false
    private var lastEvent: TimeInterval = 0
    /// A keyboard or menu selection ends browsing; the rest of the gesture is swallowed without moving the strip.
    private(set) var isSuppressed = false
    init() {}
    mutating func reset() { owned = false; rejected = false; isSuppressed = false; lastEvent = 0 }
    mutating func suppress() { if owned { isSuppressed = true } }
    mutating func consume(x: Double, y: Double, precise: Bool, modifiers: Bool,
                                 eligible: Bool, begins: Bool, momentum: Bool,
                                 cancelled: Bool, finishesMomentum: Bool, now: TimeInterval) -> Bool {
        if begins || (!momentum && now - lastEvent > 0.3) { owned = false; rejected = false; isSuppressed = false }
        // Eligibility is decided when the gesture starts; crossing onto another display keeps it owned.
        if !precise || !x.isFinite || !y.isFinite || (!eligible && !owned) { reset(); return false }
        if !owned && !rejected && !momentum && (x != 0 || y != 0) {
            owned = modifiers && abs(x) > abs(y)
            rejected = !owned
        }
        lastEvent = now
        let consume = owned
        if cancelled || finishesMomentum { owned = false; rejected = false }
        return consume
    }
}
