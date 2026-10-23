import AVFAudio

/// Whether macOS lets tällmi use the microphone, and asking for it.
public enum MicrophonePermission {
    /// True when allowed, false when refused, nil when macOS hasn't asked yet.
    public static var isAllowed: Bool? {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: true
        case .denied: false
        default: nil
        }
    }

    /// Shows macOS's question the first time; afterwards answers with what you chose.
    public static func request() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }
}
