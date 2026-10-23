import Config
import Domain
import Foundation
import Persistence
import TestSupport
import Testing

@testable import AppComposition

@Suite("The first launch in the assembled app")
struct OnboardingEnvironmentTests {
    private func makeEnvironment() throws -> (AppEnvironment, AppPaths, TemporaryDirectory, TemporaryDirectory) {
        let home = try TemporaryDirectory()
        let scratch = try TemporaryDirectory()
        let paths = AppPaths(root: home.url)
        let environment = try AppEnvironment(
            paths: paths, engines: ["fake_engine": { _, _ in FakeTranscriber() }],
            recorder: FakeRecorder(folder: scratch.url))
        _ = try Seeder(database: environment.database).apply(SeedBundle.bundled())
        return (environment, paths, home, scratch)
    }

    @Test("the voice step lists every model the seeds download, with its size, until it is verified on this Mac")
    func voiceDownloads() throws {
        let (environment, paths, home, scratch) = try makeEnvironment()
        defer { withExtendedLifetime((home, scratch)) {} }
        let downloads = try environment.voiceSetup().downloads
        #expect(downloads.map(\.role) == [.transcription, .embed])
        #expect(downloads.allSatisfy { !$0.isInstalled && $0.bytes > 100_000_000 })

        let speech = try #require(try ModelResolver.assigned(.transcription, in: environment.database))
        try ModelInstallation(root: paths.models).markVerified(speech)
        #expect(try environment.voiceSetup().downloads.map(\.isInstalled) == [true, false])
    }

    @Test("the roles that run on what macOS brings come from config too")
    func voiceBuiltIn() throws {
        let (environment, _, home, scratch) = try makeEnvironment()
        defer { withExtendedLifetime((home, scratch)) {} }
        #expect(try environment.voiceSetup().builtIn == [.liveTranscription, .summary, .entities])
    }

    @Test("a fresh tällmi opens the onboarding")
    func opensWhenFresh() async throws {
        let (environment, _, home, scratch) = try makeEnvironment()
        defer { withExtendedLifetime((home, scratch)) {} }
        #expect(await environment.shouldOpenOnboarding())
    }

    @Test("a tällmi with thoughts doesn't open it, and remembers that")
    func notWithThoughts() async throws {
        let (environment, _, home, scratch) = try makeEnvironment()
        defer { withExtendedLifetime((home, scratch)) {} }
        _ = try await environment.journal.addTypedEntry("Erster Gedanke, getippt.")
        #expect(await !environment.shouldOpenOnboarding())
        #expect(try SettingsStore(database: environment.database).bool(SettingKeys.onboardingCompleted))
    }

    @Test("finishing the onboarding is remembered")
    func finishing() async throws {
        let (environment, _, home, scratch) = try makeEnvironment()
        defer { withExtendedLifetime((home, scratch)) {} }
        try environment.finishOnboarding()
        #expect(await !environment.shouldOpenOnboarding())
    }
}
