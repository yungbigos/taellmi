import CoreGraphics
import Domain

/// What tälli notices while it sits still: where the cursor is, whether it moves, how close it comes, and
/// pokes. Positions are points relative to tälli's centre with y pointing down; times are seconds on any
/// monotonic clock, passed in so tests control them.
public struct TalliAttention: Sendable {
    private let tokens: BrandTokens.Motion.Attention
    private var cursor: CGVector?
    private var lastStirred: Double?
    private var lastSeen: Double?
    private var lastStartle: Double?
    private var lastPoke: Double?
    private var recentPokes: [Double] = []
    private var squeezeUntil: Double?

    public init(tokens: BrandTokens.Motion.Attention) {
        self.tokens = tokens
    }

    /// The cursor as of `time`; `nil` when tälli can't know where it is. Any change counts as movement.
    public mutating func see(cursor newCursor: CGVector?, at time: Double) {
        if let newCursor, newCursor != cursor {
            lastStirred = time
            if let cursor, let lastSeen, time > lastSeen {
                let speed = hypot(newCursor.dx - cursor.dx, newCursor.dy - cursor.dy) / (time - lastSeen)
                if speed > tokens.startleSpeedPtS { lastStartle = time }
            }
        }
        cursor = newCursor
        lastSeen = time
    }

    /// Something happened that isn't the cursor moving relative to tälli (you type, or carry tälli around).
    public mutating func stir(at time: Double) {
        lastStirred = time
    }

    public mutating func poke(at time: Double) {
        lastPoke = time
        lastStirred = time
        recentPokes = recentPokes.filter { time - $0 < tokens.squeezeWithinS } + [time]
        if recentPokes.count >= tokens.squeezePokes {
            squeezeUntil = time + tokens.squeezeHoldS
            recentPokes = []
        }
    }

    /// Where the eyes should look, each axis −1…1, or `nil` when the cursor hasn't moved for a while.
    public func gaze(at time: Double) -> CGVector? {
        guard let cursor, let lastStirred, time - lastStirred < tokens.followForS else { return nil }
        let distance = hypot(cursor.dx, cursor.dy)
        guard distance > 0 else { return .zero }
        let strength = min(1, distance / tokens.reachPt) / distance
        return CGVector(dx: cursor.dx * strength, dy: cursor.dy * strength)
    }

    /// 0 while the cursor is farther than `nearPt` … 1 once it is within `closePt`.
    public var proximity: Double {
        guard let cursor else { return 0 }
        let distance = hypot(cursor.dx, cursor.dy)
        return min(1, max(0, (tokens.nearPt - distance) / max(1, tokens.nearPt - tokens.closePt)))
    }

    public func isResting(at time: Double) -> Bool {
        guard let lastStirred else { return false }
        return time - lastStirred > tokens.restAfterS
    }

    /// Seconds since the last poke, while tälli still reacts to it.
    public func pokeAge(at time: Double) -> Double? {
        guard let lastPoke, time - lastPoke < tokens.pokeDuration else { return nil }
        return max(0, time - lastPoke)
    }

    /// Seconds since a sudden fast move, while tälli still reacts to it.
    public func startleAge(at time: Double) -> Double? {
        guard let lastStartle, time - lastStartle < tokens.startleDuration else { return nil }
        return max(0, time - lastStartle)
    }

    /// −1 when the cursor is to tälli's left, otherwise 1.
    public var cursorSide: Double {
        (cursor?.dx ?? 0) < 0 ? -1 : 1
    }

    public func isSqueezing(at time: Double) -> Bool {
        squeezeUntil.map { time < $0 } ?? false
    }
}
