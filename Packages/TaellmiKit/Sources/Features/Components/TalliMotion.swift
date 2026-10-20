import CoreGraphics
import Domain
import Foundation

/// What tälli is doing right now. Every place that shows tälli passes one of these.
public enum TalliMood: Sendable, Equatable {
    /// Calm, breathing slowly.
    case idle
    /// Listening; swells with the voice level (0…1). Silence turns into the "äh" pause.
    case listening(level: Float)
    /// The app is working on your thoughts; the ä grows "hmmm" letters.
    case thinking
    /// Just saved something.
    case saved
}

/// How tälli comes alive when it first appears.
public enum TalliEntrance: Sendable, Equatable {
    /// Rises a little and grows in: next to the cursor.
    case rise
    /// Rolls in from the side and settles upright: when the window launches.
    case roll
}

/// One letter of the thinking "ähmmm".
public struct TalliLetter: Sendable, Equatable {
    public var character: Character
    public var opacity: Double
}

/// Everything needed to draw one frame of tälli. Lengths are fractions of tälli's size.
public struct TalliPose: Sendable, Equatable {
    public var opacity: Double = 1
    public var scale: Double = 1
    /// Extra vertical squash while the voice is loud (1 = none).
    public var squash: Double = 1
    public var offset: CGSize = .zero
    /// Radians.
    public var rotation: Double = 0
    /// Where the eyes look, each axis −1…1.
    public var eyes: CGVector = .zero
    /// 0 open … 1 closed.
    public var lid: Double = 0
    public var dotScale: Double = 1
    public var dotOpacity: Double = 1
    /// 0…1: one dot briefly stretches into a raised brow.
    public var brow: Double = 0
    /// 0 closed … 1 open.
    public var mouth: Double = 0
    public var letters: [TalliLetter] = []
    public var isPausing = false
}

/// tälli's behaviour over time, as numbers. All timings and amounts come from the brand tokens; the view
/// only draws the pose. Keeps state between frames (voice smoothing, blinks, letters), so one instance
/// belongs to one visible tälli.
@MainActor
public final class TalliMotion {
    private let tokens: BrandTokens
    private let entrance: TalliEntrance?
    private let random: () -> Double

    private var start: Double?
    private var lastTime: Double?
    private var mood: TalliMood = .idle
    private var moodStart: Double = 0
    private var level: Double = 0
    private var silence: Double = 0
    private var eye = (x: 0.0, y: 0.0, vx: 0.0, vy: 0.0)
    private var drift = (x: 0.0, y: 0.0, next: 0.0)
    private var nextBlink: Double?
    private var blinkStart: Double?
    private var letters: [(character: Character, born: Double, gone: Double?)] = []
    private var nextLetter: Double = 0
    private var browAt: Double?
    private var mouth: Double = 0

    /// - Parameter random: 0…1, injected so tests are deterministic.
    public init(tokens: BrandTokens, entrance: TalliEntrance?, random: @escaping () -> Double) {
        self.tokens = tokens
        self.entrance = entrance
        self.random = random
    }

    /// The breathing period at a given hour: slower and sleepier at night, livelier in the morning.
    public func breathPeriod(hour: Double) -> Double {
        let breath = tokens.motion.breath
        return breath.period * (1 + breath.nightSlower * sleepiness(hour) - breath.morningFaster * morningness(hour))
    }

    /// The pose at `time` (seconds, any monotonic clock) for `mood`.
    public func pose(mood newMood: TalliMood, at time: Double, reduceMotion: Bool, hour: Double) -> TalliPose {
        let motion = tokens.motion
        if start == nil {
            start = time
            moodStart = time
            mood = newMood
            if newMood == .thinking { nextLetter = time + motion.thinking.firstLetterAfter }
            nextBlink = time + interval(motion.blink.everyMin, motion.blink.everyMax)
        }
        let dt = min(0.05, max(0, time - (lastTime ?? time)))
        lastTime = time
        if !sameKind(newMood, mood) { changeMood(to: newMood, at: time) }
        mood = newMood

        var pose = TalliPose()
        let sinceStart = time - (start ?? time)
        let sleepy = sleepiness(hour)

        // Voice: fast attack, slower release.
        let target = Double(listeningLevel)
        let tau = target > level ? motion.voice.attack : motion.voice.release
        level += (target - level) * (1 - exp(-dt / tau))
        if case .listening = mood {
            silence = target < motion.voice.silenceBelow ? silence + dt : 0
        } else {
            silence = 0
        }
        pose.isPausing = isListening && silence > motion.pause.afterSilence

        // Body.
        let entered = entrancePose(sinceStart, reduceMotion: reduceMotion)
        pose.opacity = entered.opacity
        pose.offset = entered.offset
        pose.rotation = entered.rotation
        if reduceMotion {
            pose.scale = 1
        } else {
            let breath = motion.breath.amplitude * sin(time * 2 * .pi / breathPeriod(hour: hour))
            let swell = motion.voice.swellMax * level
            var settle = 0.0
            if mood == .saved {
                let progress = min(1, (time - moodStart) / motion.saving.settle)
                settle = -motion.saving.settleDepth * sin(.pi * curve("soft", progress))
            }
            pose.scale = (1 + breath + swell + settle) * entered.scale
            pose.squash = 1 - motion.voice.squash * level
        }

        // Eyes.
        var look = (x: 0.0, y: 0.0)
        if mood == .thinking {
            look = (
                motion.thinking.look[0] + motion.thinking.lookSway * sin(time * motion.thinking.lookSwaySpeed),
                motion.thinking.look[1]
            )
        }
        if pose.isPausing {
            if time > drift.next {
                drift = (
                    (random() * 2 - 1) * motion.pause.driftX, (random() * 2 - 1) * motion.pause.driftY,
                    time + interval(motion.pause.driftEveryMin, motion.pause.driftEveryMax)
                )
            }
            look = (drift.x, drift.y)
        }
        if let lookAside = entered.look { look = lookAside }
        if reduceMotion {
            let holdsGaze = mood == .thinking || pose.isPausing
            eye = holdsGaze ? (look.x, look.y, 0, 0) : (0, 0, 0, 0)
        } else {
            followCriticallyDamped(to: look, dt: dt)
        }
        pose.eyes = CGVector(dx: eye.x, dy: eye.y)

        // Lids: blinks, the saving blink, sleepiness at night, and closed eyes during an entrance.
        if !reduceMotion {
            if case .saved = mood, time - moodStart >= motion.saving.blinkAt, blinkStart ?? -1 < moodStart {
                blinkStart = time
            }
            if mood != .saved, let next = nextBlink, time > next {
                blinkStart = time
                nextBlink =
                    time + interval(motion.blink.everyMin, motion.blink.everyMax)
                    * (1 - motion.blink.morningMore * morningness(hour))
            }
            let duration = motion.blink.duration * (1 + motion.blink.nightLonger * sleepy)
            if let began = blinkStart, time - began < duration { pose.lid = sin(.pi * (time - began) / duration) }
            pose.lid = max(pose.lid, motion.blink.nightLid * sleepy)
        }
        pose.lid = max(pose.lid, entered.lid)

        // Dots follow the voice: they pulse, or under Reduce Motion they brighten instead.
        pose.dotScale = reduceMotion ? 1 : 1 + motion.voice.dotPulseMax * level
        let dim = motion.voice.reduceMotionDim
        pose.dotOpacity = reduceMotion && isListening ? dim + (1 - dim) * level : 1

        // The rare raised brow while thinking.
        if mood == .thinking && !reduceMotion {
            if browAt == nil { browAt = time + interval(motion.thinking.browEveryMin, motion.thinking.browEveryMax) }
            if let at = browAt, time >= at {
                let progress = (time - at) / motion.thinking.browDuration
                if progress < 1 { pose.brow = sin(.pi * progress) } else { browAt = nil }
            }
        }

        // The mouth opens only to say something.
        let says = mood == .saved && time - moodStart >= motion.saving.sayAt
        mouth += ((says ? 1 : 0) - mouth) * (1 - exp(-dt / motion.saving.mouthResponse))
        pose.mouth = mouth

        pose.letters = thinkingLetters(at: time, reduceMotion: reduceMotion)
        return pose
    }

    // MARK: - Pieces

    private var listeningLevel: Float {
        if case .listening(let level) = mood { return min(1, max(0, level)) }
        return 0
    }

    private var isListening: Bool {
        if case .listening = mood { return true }
        return false
    }

    private func sameKind(_ a: TalliMood, _ b: TalliMood) -> Bool {
        switch (a, b) {
        case (.idle, .idle), (.listening, .listening), (.thinking, .thinking), (.saved, .saved): true
        default: false
        }
    }

    private func changeMood(to newMood: TalliMood, at time: Double) {
        if mood == .thinking {
            for index in letters.indices where letters[index].gone == nil { letters[index].gone = time }
        }
        if newMood == .thinking { nextLetter = time + tokens.motion.thinking.firstLetterAfter }
        moodStart = time
    }

    private func thinkingLetters(at time: Double, reduceMotion: Bool) -> [TalliLetter] {
        let thinking = tokens.motion.thinking
        let living = letters.filter { $0.gone == nil }
        if mood == .thinking, time >= nextLetter, living.count < tokens.talli.letters.max {
            let hasM = living.contains { $0.character == "m" }
            let character: Character =
                living.isEmpty ? "h" : hasM ? "m" : (living.count < 3 && random() < 0.5 ? "h" : "m")
            letters.append((character, time, nil))
            nextLetter = time + interval(thinking.letterEveryMin, thinking.letterEveryMax)
        }
        letters.removeAll { letter in letter.gone.map { time - $0 > thinking.letterOut } ?? false }
        return letters.map { letter in
            var opacity = reduceMotion ? 1 : curve("enter", min(1, (time - letter.born) / thinking.letterIn))
            if let gone = letter.gone {
                opacity = reduceMotion ? 0 : opacity * (1 - min(1, (time - gone) / thinking.letterOut))
            }
            return TalliLetter(character: letter.character, opacity: opacity)
        }
    }

    private struct Entered {
        var opacity = 1.0
        var scale = 1.0
        var offset = CGSize.zero
        var rotation = 0.0
        var lid = 0.0
        var look: (x: Double, y: Double)?
    }

    private func entrancePose(_ t: Double, reduceMotion: Bool) -> Entered {
        guard let entrance else { return Entered() }
        let appear = entrance == .rise ? tokens.motion.appearCursor : tokens.motion.appearLaunch
        if reduceMotion { return Entered(opacity: min(1, t / appear.fadeIn)) }
        guard t < appear.duration else { return Entered() }
        let spring = spring(t, named: appear.easing)
        var pose = Entered(opacity: min(1, t / appear.fadeIn))
        pose.scale = appear.fromScale + (1 - appear.fromScale) * spring
        pose.offset = CGSize(width: (appear.fromX ?? 0) * (1 - spring), height: (appear.rise ?? 0) * (1 - spring))
        pose.rotation = (appear.fromRotationRad ?? 0) * (1 - spring)
        let opening = appear.eyesOpenFor
        pose.lid = t < appear.eyesOpenAt ? 1 : 1 - curve("soft", min(1, (t - appear.eyesOpenAt) / opening))
        if let lookAt = appear.lookAtYouAt, let aside = appear.lookAside, t < lookAt {
            pose.look = (aside[0], aside[1])
        }
        return pose
    }

    /// A spring step from 0 to 1 as configured (one soft overshoot, then still). A spring missing from the
    /// config means no animation: the step is already done.
    private func spring(_ t: Double, named name: String) -> Double {
        guard let response = tokens.easing[name]?.response, let ratio = tokens.easing[name]?.damping else { return 1 }
        let damping = min(0.999, ratio)
        let omega = 2 * .pi / response
        let damped = omega * sqrt(1 - damping * damping)
        return 1 - exp(-damping * omega * t)
            * (cos(damped * t) + damping / sqrt(1 - damping * damping) * sin(damped * t))
    }

    /// The eyes follow their target without overshoot. A missing spring means they jump there.
    private func followCriticallyDamped(to target: (x: Double, y: Double), dt: Double) {
        guard let response = tokens.easing["spring.glance"]?.response else {
            eye = (target.x, target.y, 0, 0)
            return
        }
        let omega = 2 * .pi / response
        eye.vx += (-omega * omega * (eye.x - target.x) - 2 * omega * eye.vx) * dt
        eye.vy += (-omega * omega * (eye.y - target.y) - 2 * omega * eye.vy) * dt
        eye.x += eye.vx * dt
        eye.y += eye.vy * dt
    }

    /// A named cubic Bézier from the tokens, evaluated at `x` (0…1).
    private func curve(_ name: String, _ x: Double) -> Double {
        guard let points = tokens.easing[name]?.bezier, points.count == 4 else { return x }
        return CubicBezier(x1: points[0], y1: points[1], x2: points[2], y2: points[3]).value(at: x)
    }

    private func interval(_ low: Double, _ high: Double) -> Double { low + random() * (high - low) }

    /// 0 in the day … 1 in the middle of the night.
    private func sleepiness(_ hour: Double) -> Double {
        let time = tokens.motion.timeOfDay
        let distance = abs(hour - time.nightCenterH)
        let circular = min(distance, 24 - distance)
        return min(1, max(0, (time.nightWidthH - circular) / max(0.5, time.nightWidthH - time.nightFalloffH)))
    }

    /// 1 at the morning peak, fading out either side.
    private func morningness(_ hour: Double) -> Double {
        let time = tokens.motion.timeOfDay
        return max(0, 1 - abs(hour - time.morningCenterH) / time.morningWidthH)
    }
}

/// A CSS-style cubic Bézier timing curve.
struct CubicBezier {
    var x1: Double, y1: Double, x2: Double, y2: Double

    func value(at x: Double) -> Double {
        var low = 0.0
        var high = 1.0
        var u = x
        for _ in 0..<24 {
            u = (low + high) / 2
            if component(u, x1, x2) < x { low = u } else { high = u }
        }
        return component(u, y1, y2)
    }

    private func component(_ u: Double, _ p1: Double, _ p2: Double) -> Double {
        3 * (1 - u) * (1 - u) * u * p1 + 3 * (1 - u) * u * u * p2 + u * u * u
    }
}
