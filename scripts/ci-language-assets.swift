// Fetches Apple's German NaturalLanguage data (names and word classes) on a fresh CI runner.
// A Mac has it once German is one of its languages; the word classifier's tests need it.
//   swift scripts/ci-language-assets.swift
import NaturalLanguage

for scheme in [NLTagScheme.nameType, .lexicalClass] {
    let result = try await NLTagger.requestAssets(for: .german, tagScheme: scheme)
    guard result == .available else {
        fatalError("✘ German \(scheme.rawValue) data is not available (result \(result.rawValue))")
    }
    print("▸ German \(scheme.rawValue) data available")
}
