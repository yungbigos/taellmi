import CoreGraphics
import Domain
import Features
import Foundation
import Testing

/// tälli's attention settings as shipped in the Config seeds.
private func shippedTokens() throws -> BrandTokens {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../Sources/Config/Resources/Seeds/brand.json").standardizedFileURL
    return try BrandTokens(json: try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url)))
}

private func shippedAttention() throws -> BrandTokens.Motion.Attention {
    try #require(try shippedTokens().motion.attention)
}

private func length(_ vector: CGVector) -> Double { hypot(vector.dx, vector.dy) }

@MainActor
@Suite("tälli watching the cursor")
struct TalliAttentionTests {
    @Test("looks towards the cursor: right and up when the cursor is right and above")
    func looksTowardsCursor() throws {
        var attention = TalliAttention(tokens: try shippedAttention())
        attention.see(cursor: CGVector(dx: 120, dy: -80), at: 0)
        let gaze = try #require(attention.gaze(at: 0.1))
        #expect(gaze.dx > 0)
        #expect(gaze.dy < 0)
    }

    @Test("looks further the further away the cursor is, all the way at the reach distance and beyond")
    func gazeGrowsThenSaturates() throws {
        let tokens = try shippedAttention()
        var attention = TalliAttention(tokens: tokens)
        attention.see(cursor: CGVector(dx: tokens.reachPt / 4, dy: 0), at: 0)
        let near = try #require(attention.gaze(at: 0))
        attention.see(cursor: CGVector(dx: tokens.reachPt, dy: 0), at: 0.1)
        let atReach = try #require(attention.gaze(at: 0.1))
        attention.see(cursor: CGVector(dx: 0, dy: tokens.reachPt * 5), at: 0.2)
        let far = try #require(attention.gaze(at: 0.2))
        #expect(abs(length(near) - 0.25) < 0.01)
        #expect(abs(length(atReach) - 1) < 0.001)
        #expect(abs(length(far) - 1) < 0.001)
    }

    @Test("stops following a cursor that stands still, and looks again once it moves")
    func followsOnlyWhileMoving() throws {
        let tokens = try shippedAttention()
        var attention = TalliAttention(tokens: tokens)
        attention.see(cursor: CGVector(dx: 100, dy: 0), at: 0)
        attention.see(cursor: CGVector(dx: 100, dy: 0), at: tokens.followForS + 0.1)
        #expect(attention.gaze(at: tokens.followForS + 0.1) == nil)
        attention.see(cursor: CGVector(dx: 90, dy: 10), at: tokens.followForS + 0.2)
        #expect(attention.gaze(at: tokens.followForS + 0.2) != nil)
    }

    @Test(
        "notices the cursor coming close: nothing far away, fully perked up close by",
        arguments: [(1.5, 0.0), (0.0, 1.0)])
    func proximity(distanceFactor: Double, expected: Double) throws {
        let tokens = try shippedAttention()
        var attention = TalliAttention(tokens: tokens)
        let distance = distanceFactor == 0 ? tokens.closePt / 2 : tokens.nearPt * distanceFactor
        attention.see(cursor: CGVector(dx: 0, dy: distance), at: 0)
        #expect(attention.proximity == expected)
    }

    @Test("between near and close it perks up part of the way")
    func proximityInBetween() throws {
        let tokens = try shippedAttention()
        var attention = TalliAttention(tokens: tokens)
        attention.see(cursor: CGVector(dx: (tokens.nearPt + tokens.closePt) / 2, dy: 0), at: 0)
        #expect(abs(attention.proximity - 0.5) < 0.001)
    }

    @Test("rests after a while with nothing happening, and wakes when the cursor moves")
    func restsAndWakes() throws {
        let tokens = try shippedAttention()
        var attention = TalliAttention(tokens: tokens)
        attention.see(cursor: CGVector(dx: 300, dy: 0), at: 0)
        #expect(!attention.isResting(at: tokens.restAfterS - 0.1))
        attention.see(cursor: CGVector(dx: 300, dy: 0), at: tokens.restAfterS + 0.1)
        #expect(attention.isResting(at: tokens.restAfterS + 0.1))
        attention.see(cursor: CGVector(dx: 280, dy: 0), at: tokens.restAfterS + 0.2)
        #expect(!attention.isResting(at: tokens.restAfterS + 0.2))
    }

    @Test("without ever seeing the cursor it neither looks anywhere nor rests")
    func blindByDefault() throws {
        let attention = TalliAttention(tokens: try shippedAttention())
        #expect(attention.gaze(at: 100) == nil)
        #expect(attention.proximity == 0)
        #expect(!attention.isResting(at: 100))
    }

    @Test("a poke is remembered for as long as tälli reacts to it")
    func pokeAge() throws {
        let tokens = try shippedAttention()
        var attention = TalliAttention(tokens: tokens)
        attention.poke(at: 10)
        #expect(abs((attention.pokeAge(at: 10.2) ?? 0) - 0.2) < 1e-9)
        #expect(attention.pokeAge(at: 10 + tokens.pokeDuration + 0.1) == nil)
    }

    @Test("three quick pokes and it squeezes its eyes shut for a moment")
    func squeezes() throws {
        let tokens = try shippedAttention()
        var attention = TalliAttention(tokens: tokens)
        let gap = tokens.squeezeWithinS / Double(tokens.squeezePokes)
        for index in 0..<tokens.squeezePokes { attention.poke(at: Double(index) * gap) }
        let last = Double(tokens.squeezePokes - 1) * gap
        #expect(attention.isSqueezing(at: last + 0.1))
        #expect(!attention.isSqueezing(at: last + tokens.squeezeHoldS + 0.1))
    }

    @Test("slow pokes, or too few, don't make it squeeze")
    func slowPokesDont() throws {
        let tokens = try shippedAttention()
        var attention = TalliAttention(tokens: tokens)
        for index in 0..<tokens.squeezePokes { attention.poke(at: Double(index) * tokens.squeezeWithinS) }
        #expect(!attention.isSqueezing(at: Double(tokens.squeezePokes) * tokens.squeezeWithinS))
        var fewer = TalliAttention(tokens: tokens)
        for index in 0..<(tokens.squeezePokes - 1) { fewer.poke(at: Double(index) * 0.1) }
        #expect(!fewer.isSqueezing(at: 0.5))
    }

    @Test("a poke wakes a resting tälli")
    func pokeWakes() throws {
        let tokens = try shippedAttention()
        var attention = TalliAttention(tokens: tokens)
        attention.see(cursor: CGVector(dx: 300, dy: 0), at: 0)
        attention.poke(at: tokens.restAfterS + 1)
        #expect(!attention.isResting(at: tokens.restAfterS + 1.1))
    }
}

/// Runs tälli's motion for `seconds` in 1/60 s steps with the cursor at `cursor`, and returns the last pose.
@MainActor
private func watch(
    _ motion: TalliMotion, cursor: CGVector?, mood: TalliMood = .idle, for seconds: Double, from start: Double = 0,
    reduceMotion: Bool = false, jitter: Bool = true
) -> TalliPose {
    var time = start
    var step = 0
    func frame() -> TalliPose {
        // A cursor that trembles by a fraction of a point counts as moving, like a hand on a mouse.
        let wobble = jitter && step % 2 == 0 ? 0.5 : 0
        motion.see(cursor: cursor.map { CGVector(dx: $0.dx + wobble, dy: $0.dy) }, at: time)
        return motion.pose(mood: mood, at: time, reduceMotion: reduceMotion, hour: 14)
    }
    var pose = frame()
    while time < start + seconds {
        time += 1.0 / 60
        step += 1
        pose = frame()
    }
    return pose
}

@MainActor
@Suite("How tälli reacts while it sits still")
struct TalliReactionTests {
    private func motion() throws -> TalliMotion {
        TalliMotion(tokens: try shippedTokens(), entrance: nil, random: { 0.5 })
    }

    @Test("the eyes turn to the cursor")
    func eyesFollow() throws {
        let pose = watch(try motion(), cursor: CGVector(dx: 400, dy: 0), for: 1.5)
        #expect(pose.eyes.dx > 0.8)
        #expect(abs(pose.eyes.dy) < 0.05)
    }

    @Test("close by it perks up: a little bigger, with wider eyes")
    func perksUp() throws {
        let tokens = try shippedTokens()
        let attention = try #require(tokens.motion.attention)
        let far = watch(try motion(), cursor: CGVector(dx: attention.nearPt * 2, dy: 0), for: 1.5)
        let close = watch(try motion(), cursor: CGVector(dx: attention.closePt / 2, dy: 0), for: 1.5)
        #expect(close.scale > far.scale + attention.perkScale * 0.8)
        #expect(close.dotScale > far.dotScale + attention.widenDots * 0.8)
    }

    @Test("a poke squishes it wide and flat with its eyes shut, then it springs back")
    func pokeSquishes() throws {
        let tokens = try shippedTokens()
        let attention = try #require(tokens.motion.attention)
        let talli = try motion()
        _ = watch(talli, cursor: CGVector(dx: 300, dy: 0), for: 0.5)
        talli.poke(at: 0.6)
        let squished = watch(talli, cursor: CGVector(dx: 300, dy: 0), for: 0.02, from: 0.6)
        #expect(squished.stretch > 1.05)
        #expect(squished.squash < 0.95)
        #expect(squished.lid > 0.8)
        let after = watch(talli, cursor: CGVector(dx: 300, dy: 0), for: attention.pokeDuration, from: 0.62)
        #expect(abs(after.stretch - 1) < 0.01)
        #expect(abs(after.squash - 1) < 0.01)
    }

    @Test("with nothing happening its lids droop as it rests, and it opens them when the cursor moves")
    func rests() throws {
        let tokens = try shippedTokens()
        let attention = try #require(tokens.motion.attention)
        let talli = try motion()
        let resting = watch(
            talli, cursor: CGVector(dx: 300, dy: 0), for: attention.restAfterS + 5, jitter: false)
        #expect(resting.lid > attention.restLid * 0.9)
        let start = attention.restAfterS + 5.1
        let awake = watch(talli, cursor: CGVector(dx: 200, dy: 40), for: 1.5, from: start)
        #expect(awake.lid < 0.1)
    }

    @Test("it never dozes off while you talk to it")
    func noRestWhileListening() throws {
        let tokens = try shippedTokens()
        let attention = try #require(tokens.motion.attention)
        let pose = watch(
            try motion(), cursor: CGVector(dx: 300, dy: 0), mood: .listening(level: 0.6), for: attention.restAfterS + 5,
            jitter: false)
        #expect(pose.lid < 0.2)
    }

    @Test("three quick pokes and it squeezes its eyes shut")
    func squeezes() throws {
        let tokens = try shippedTokens()
        let attention = try #require(tokens.motion.attention)
        let talli = try motion()
        _ = watch(talli, cursor: CGVector(dx: 300, dy: 0), for: 0.2)
        for index in 0..<attention.squeezePokes { talli.poke(at: 0.3 + Double(index) * 0.2) }
        let squeezing = watch(talli, cursor: CGVector(dx: 300, dy: 0), for: 0.4, from: 0.9)
        #expect(squeezing.lid >= attention.squeezeLid)
    }

    @Test("under Reduce Motion it keeps a still face and a poke only dims the dots")
    func reduceMotion() throws {
        let tokens = try shippedTokens()
        let attention = try #require(tokens.motion.attention)
        let talli = try motion()
        let watched = watch(talli, cursor: CGVector(dx: attention.closePt / 2, dy: 0), for: 1, reduceMotion: true)
        #expect(watched.eyes == .zero)
        #expect(watched.scale == 1)
        #expect(watched.dotScale == 1)
        talli.poke(at: 1.1)
        let poked = watch(
            talli, cursor: CGVector(dx: attention.closePt / 2, dy: 0), for: 0.02, from: 1.1, reduceMotion: true)
        #expect(poked.stretch == 1)
        #expect(poked.dotOpacity == attention.pokeReduceMotionDim)
    }

    @Test("a tälli that is never shown the cursor behaves as before")
    func unwatched() throws {
        let talli = try motion()
        var time = 0.0
        var pose = talli.pose(mood: .idle, at: time, reduceMotion: false, hour: 14)
        while time < 12 {
            time += 1.0 / 60
            pose = talli.pose(mood: .idle, at: time, reduceMotion: false, hour: 14)
        }
        #expect(pose.eyes == .zero)
        #expect(pose.lid < 0.2)
    }
}

@MainActor
@Suite("tälli noticing sudden moves and activity")
struct TalliStartleTests {
    @Test("a sudden fast move startles it, for a moment")
    func startles() throws {
        let tokens = try shippedAttention()
        var attention = TalliAttention(tokens: tokens)
        attention.see(cursor: CGVector(dx: 100, dy: 0), at: 0)
        attention.see(cursor: CGVector(dx: 400, dy: 0), at: 1.0 / 60)
        #expect(attention.startleAge(at: 0.02) != nil)
        #expect(attention.startleAge(at: 1.0 / 60 + tokens.startleDuration + 0.01) == nil)
    }

    @Test("slow moves don't startle it")
    func slowMovesDont() throws {
        var attention = TalliAttention(tokens: try shippedAttention())
        attention.see(cursor: CGVector(dx: 100, dy: 0), at: 0)
        attention.see(cursor: CGVector(dx: 102, dy: 0), at: 1.0 / 60)
        #expect(attention.startleAge(at: 0.02) == nil)
    }

    @Test("typing or carrying tälli counts as something happening, so it doesn't doze off")
    func stirKeepsAwake() throws {
        let tokens = try shippedAttention()
        var attention = TalliAttention(tokens: tokens)
        attention.see(cursor: CGVector(dx: 300, dy: 0), at: 0)
        attention.stir(at: tokens.restAfterS - 1)
        #expect(!attention.isResting(at: tokens.restAfterS + 1))
    }
}

/// The pose over `seconds` with the cursor resting at `cursor`, every frame.
@MainActor
private func poses(
    _ motion: TalliMotion, cursor: CGVector, for seconds: Double, from start: Double, jitter: Bool
) -> [TalliPose] {
    var result: [TalliPose] = []
    var time = start
    var step = 0
    while time < start + seconds {
        let wobble = jitter && step % 2 == 0 ? 0.5 : 0
        motion.see(cursor: CGVector(dx: cursor.dx + wobble, dy: cursor.dy), at: time)
        result.append(motion.pose(mood: .idle, at: time, reduceMotion: false, hour: 14))
        time += 1.0 / 60
        step += 1
    }
    return result
}

@MainActor
@Suite("How lively tälli is while it watches")
struct TalliLivelinessTests {
    private func motion() throws -> TalliMotion {
        TalliMotion(tokens: try shippedTokens(), entrance: nil, random: { 0.5 })
    }

    private func attention() throws -> BrandTokens.Motion.Attention { try shippedAttention() }

    @Test("its eyes look further than their usual reach when it watches you")
    func eyesLookFurther() throws {
        let pose = watch(try motion(), cursor: CGVector(dx: 600, dy: 0), for: 1.5)
        #expect(pose.eyes.dx > 1.2)
    }

    @Test("its eyes keep up with the cursor quickly")
    func eyesKeepUp() throws {
        let gain = try attention().gazeGain
        let pose = watch(try motion(), cursor: CGVector(dx: 600, dy: 0), for: 0.4)
        #expect(pose.eyes.dx > gain * 0.9)
    }

    @Test("it turns its body towards where it looks", arguments: [1.0, -1.0])
    func leans(side: Double) throws {
        let pose = watch(try motion(), cursor: CGVector(dx: 600 * side, dy: 0), for: 1.5)
        #expect(pose.offset.width * side > 0.03)
        #expect(pose.rotation * side > 0.03)
    }

    @Test("a sudden move makes it start: a little hop, eyes wide")
    func startlePose() throws {
        let talli = try motion()
        let before = watch(talli, cursor: CGVector(dx: 600, dy: 0), for: 0.5)
        let after = watch(talli, cursor: CGVector(dx: 1000, dy: 0), for: 0.1, from: 0.52)
        #expect(after.offset.height < -0.02)
        #expect(after.dotScale > before.dotScale + 0.15)
    }

    @Test("a poke makes it hop")
    func pokeHops() throws {
        let talli = try motion()
        _ = watch(talli, cursor: CGVector(dx: 600, dy: 0), for: 0.5)
        talli.poke(at: 0.52)
        let hopping = watch(talli, cursor: CGVector(dx: 600, dy: 0), for: 0.15, from: 0.52)
        #expect(hopping.offset.height < -0.05)
    }

    @Test("resting, its breath slows down")
    func breathSlowsWhileResting() throws {
        let rest = try attention().restAfterS
        func peaks(_ poses: [TalliPose]) -> Int {
            (1..<(poses.count - 1)).filter {
                poses[$0].scale > poses[$0 - 1].scale && poses[$0].scale >= poses[$0 + 1].scale
            }
            .count
        }
        let awake = poses(try motion(), cursor: CGVector(dx: 600, dy: 0), for: 27, from: 0, jitter: true)
        let sleeper = try motion()
        _ = poses(sleeper, cursor: CGVector(dx: 600, dy: 0), for: rest + 5, from: 0, jitter: false)
        let resting = poses(sleeper, cursor: CGVector(dx: 600, dy: 0), for: 27, from: rest + 5, jitter: false)
        #expect(peaks(resting) < peaks(awake))
    }

    @Test("resting, it looks down a little and doesn't blink")
    func restingLooksDownWithoutBlinking() throws {
        let tokens = try attention()
        let sleeper = try motion()
        _ = poses(sleeper, cursor: CGVector(dx: 600, dy: 0), for: tokens.restAfterS + 5, from: 0, jitter: false)
        let resting = poses(
            sleeper, cursor: CGVector(dx: 600, dy: 0), for: 20, from: tokens.restAfterS + 5, jitter: false)
        #expect((resting.last?.eyes.dy ?? 0) > 0.2)
        #expect((resting.map(\.lid).max() ?? 1) <= tokens.restLid + 0.02)
    }

    @Test("waking up starts with a blink")
    func wakesWithABlink() throws {
        let tokens = try attention()
        let sleeper = try motion()
        let start = tokens.restAfterS + 5
        _ = poses(sleeper, cursor: CGVector(dx: 600, dy: 0), for: start, from: 0, jitter: false)
        let waking = poses(sleeper, cursor: CGVector(dx: 580, dy: 20), for: 0.17, from: start, jitter: true)
        #expect((waking.map(\.lid).max() ?? 0) > 0.9)
    }

    @Test("squeezing its eyes shut, it looks away from the cursor")
    func squeezeLooksAway() throws {
        let tokens = try attention()
        let talli = try motion()
        _ = watch(talli, cursor: CGVector(dx: 300, dy: 0), for: 0.5)
        for index in 0..<tokens.squeezePokes { talli.poke(at: 0.6 + Double(index) * 0.1) }
        let squeezing = watch(talli, cursor: CGVector(dx: 300, dy: 0), for: 0.6, from: 0.9)
        #expect(squeezing.eyes.dx < 0)
    }
}
