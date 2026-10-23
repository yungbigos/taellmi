import Observation

/// "open tällmi at login" in settings › general. macOS keeps the setting (System Settings › General › Login
/// Items); this shows what it says and changes it.
@Observable
public final class OpenAtLoginModel {
    public private(set) var isOn = false
    @ObservationIgnored private let read: () -> Bool
    @ObservationIgnored private let write: (Bool) -> Bool

    /// - Parameter set: changes it and returns what macOS really did.
    public init(isOn: @escaping () -> Bool, set: @escaping (Bool) -> Bool) {
        read = isOn
        write = set
    }

    public func load() {
        isOn = read()
    }

    public func set(_ on: Bool) {
        isOn = write(on)
    }
}
