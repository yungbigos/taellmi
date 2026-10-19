import Domain
import FluidAudio

/// Engine options read from a model's `params` in config, so new Parakeet releases are a config change.
public struct ParakeetOptions: Sendable {
    public enum Error: Swift.Error, Equatable {
        case missingParam(String)
        case unknownVersion(String)
        case unknownPrecision(String)
    }

    private static let versions: [String: AsrModelVersion] = [
        "v2": .v2, "v3": .v3, "redux": .redux, "ultra": .ultra, "phonon2": .phonon2,
        "tdt_ctc_110m": .tdtCtc110m, "tdt_ja": .tdtJa,
    ]

    let version: AsrModelVersion
    let precision: ParakeetEncoderPrecision
    public let versionName: String
    public var precisionName: String { precision.rawValue }

    public init(params: [String: JSONValue]) throws {
        guard let versionName = params["version"]?.stringValue else { throw Error.missingParam("version") }
        self.versionName = versionName
        guard let version = Self.versions[versionName] else { throw Error.unknownVersion(versionName) }
        self.version = version
        guard let precisionName = params["encoder_precision"]?.stringValue else {
            throw Error.missingParam("encoder_precision")
        }
        guard let precision = ParakeetEncoderPrecision(rawValue: precisionName) else {
            throw Error.unknownPrecision(precisionName)
        }
        self.precision = precision
    }
}
