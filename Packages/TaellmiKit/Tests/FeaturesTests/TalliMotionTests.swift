import Domain
import Features
import Foundation
import Testing

/// The brand tokens as shipped in the Config seeds.
private func shippedTokens() throws -> BrandTokens {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../Sources/Config/Resources/Seeds/brand.json").standardizedFileURL
    return try BrandTokens(json: try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url)))
}

/// Runs tälli's motion for `seconds` in 1/60 s steps and returns the last pose.
@MainActor
private func run(
    _ motion: TalliMotion, mood: TalliMood, for seconds: Double, from start: Double = 0, reduceMotion: Bool = false,
    hour: Double = 14
) -> TalliPose {
    var pose = motion.pose(mood: mood, at: start, reduceMotion: reduceMotion, hour: hour)
    var time = start
    while time < start + seconds {
        time += 1.0 / 60
        pose = motion.pose(mood: mood, at: time, reduceMotion: reduceMotion, hour: hour)
    }
    return pose
}

@MainActor
@Suite("How tälli moves")
struct TalliMotionTests {
    @Test("rising in at the cursor: starts small and low with closed eyes, ends at rest with open eyes")
    func risesIn() throws {
        let tokens = try shippedTokens()
        let motion = TalliMotion(tokens: tokens, entrance: .rise, random: { 0.5 })
        let first = motion.pose(mood: .idle, at: 0, reduceMotion: false, hour: 14)
        #expect(first.scale < 0.7)
        #expect(first.offset.height > 0)
        #expect(first.lid == 1)
        let rested = run(motion, mood: .idle, for: tokens.motion.appearCursor.duration + 0.1)
        #expect(abs(rested.scale - 1) < 0.05)
        #expect(abs(rested.offset.height) < 0.01)
        #expect(rested.lid < 0.05)
    }

    @Test("the eyes open only after the body has landed")
    func eyesOpenLast() throws {
        let tokens = try shippedTokens()
        let motion = TalliMotion(tokens: tokens, entrance: .rise, random: { 0.5 })
        let beforeOpen = run(motion, mood: .idle, for: tokens.motion.appearCursor.eyesOpenAt - 0.02)
        #expect(beforeOpen.lid == 1)
    }

    @Test("rolling in at launch comes from the side, turned, and ends upright")
    func rollsIn() throws {
        let motion = TalliMotion(tokens: try shippedTokens(), entrance: .roll, random: { 0.5 })
        let first = motion.pose(mood: .idle, at: 0, reduceMotion: false, hour: 14)
        #expect(first.offset.width < 0)
        #expect(first.rotation < 0)
        let rested = run(motion, mood: .idle, for: 1.3)
        #expect(abs(rested.rotation) < 0.01)
    }

    @Test("listening swells with the voice")
    func swellsWithVoice() throws {
        let tokens = try shippedTokens()
        let quiet = run(
            TalliMotion(tokens: tokens, entrance: nil, random: { 0.5 }), mood: .listening(level: 0), for: 0.5)
        let loud = run(
            TalliMotion(tokens: tokens, entrance: nil, random: { 0.5 }), mood: .listening(level: 1), for: 0.5)
        #expect(loud.scale > quiet.scale + 0.05)
        #expect(loud.dotScale > quiet.dotScale)
    }

    @Test("when you pause while it listens, the eyes start to drift and wait")
    func pauseDrifts() throws {
        let tokens = try shippedTokens()
        let motion = TalliMotion(tokens: tokens, entrance: nil, random: { 0.9 })
        let talking = run(motion, mood: .listening(level: 0.8), for: 1)
        #expect(!talking.isPausing)
        let paused = run(motion, mood: .listening(level: 0), for: 2.5, from: 1)
        #expect(paused.isPausing)
        #expect(abs(paused.eyes.dx) > 0.1)
    }

    @Test("thinking grows the äh: h first, then m's, never more than the maximum")
    func thinkingGrowsLetters() throws {
        let tokens = try shippedTokens()
        let motion = TalliMotion(tokens: tokens, entrance: nil, random: { 0.3 })
        let early = run(motion, mood: .thinking, for: tokens.motion.thinking.firstLetterAfter - 0.1)
        #expect(early.letters.isEmpty)
        let late = run(motion, mood: .thinking, for: 30, from: tokens.motion.thinking.firstLetterAfter - 0.1)
        let text = String(late.letters.map(\.character))
        #expect(text.first == "h")
        #expect(text.count == tokens.talli.letters.max)
        #expect(!text.drop { $0 == "h" }.contains("h"), "after the first m only m's follow: \(text)")
        #expect(late.eyes.dy < 0, "it looks up while thinking")
    }

    @Test("when thinking ends the letters fold back into the ä")
    func lettersFoldBack() throws {
        let tokens = try shippedTokens()
        let motion = TalliMotion(tokens: tokens, entrance: nil, random: { 0.3 })
        _ = run(motion, mood: .thinking, for: 6)
        let after = run(motion, mood: .idle, for: tokens.motion.thinking.letterOut + 0.1, from: 6)
        #expect(after.letters.isEmpty)
    }

    @Test("saved: a small settle, a blink, and the mouth opens to say it")
    func savedSettles() throws {
        let tokens = try shippedTokens()
        let motion = TalliMotion(tokens: tokens, entrance: nil, random: { 0.5 })
        _ = run(motion, mood: .idle, for: 1)
        let settling = run(motion, mood: .saved, for: tokens.motion.saving.settle / 2, from: 1)
        let breathing = TalliMotion(tokens: tokens, entrance: nil, random: { 0.5 })
        _ = run(breathing, mood: .idle, for: 1)
        let unsettled = run(breathing, mood: .idle, for: tokens.motion.saving.settle / 2, from: 1)
        #expect(settling.scale < unsettled.scale - 0.01, "it dips below its breathing size")
        let saying = run(motion, mood: .saved, for: 0.6, from: 1 + tokens.motion.saving.settle / 2)
        #expect(saying.mouth > 0.5)
    }

    @Test("it breathes slower at night than in the afternoon")
    func sleepyAtNight() throws {
        let tokens = try shippedTokens()
        let motion = TalliMotion(tokens: tokens, entrance: nil, random: { 0.5 })
        #expect(motion.breathPeriod(hour: 3) > motion.breathPeriod(hour: 14) * 1.3)
        #expect(motion.breathPeriod(hour: 8) < motion.breathPeriod(hour: 14))
    }

    @Test("with Reduce Motion tälli is a still face: no entrance motion, no swell, eyes still")
    func reduceMotionIsStill() throws {
        let motion = TalliMotion(tokens: try shippedTokens(), entrance: .roll, random: { 0.9 })
        let first = motion.pose(mood: .idle, at: 0, reduceMotion: true, hour: 14)
        #expect(first.offset == .zero)
        #expect(first.rotation == 0)
        let loud = run(motion, mood: .listening(level: 1), for: 2, reduceMotion: true)
        #expect(loud.scale == 1)
        #expect(loud.eyes == .zero)
        #expect(loud.dotOpacity > 0.9, "the dots brighten with the voice instead of moving")
    }
}
