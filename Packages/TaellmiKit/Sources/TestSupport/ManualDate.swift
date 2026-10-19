import Foundation
import Synchronization

/// A wall clock that only moves when a test says so.
public final class ManualDate: Sendable {
    private let current: Mutex<Date>

    public init(_ start: Date = sampleDate) {
        current = Mutex(start)
    }

    public func now() -> Date { current.withLock { $0 } }

    public func advance(by seconds: TimeInterval) {
        current.withLock { $0 = $0.addingTimeInterval(seconds) }
    }
}
