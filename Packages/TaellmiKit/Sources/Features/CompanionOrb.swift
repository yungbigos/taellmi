import SwiftUI

/// tälli for now: an organic shape that breathes slowly and swells with your voice.
/// A placeholder until the real avatar; respects Reduce Motion.
struct CompanionOrb: View {
    var level: Float
    var isListening: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            Canvas { canvas, size in
                let time = context.date.timeIntervalSinceReferenceDate
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let voice = isListening ? CGFloat(level) : 0
                let base = min(size.width, size.height) * (0.30 + 0.10 * voice)
                let path = Self.blob(
                    center: center, radius: base, time: reduceMotion ? 0 : time, energy: voice)
                let gradient = Gradient(colors: [
                    Color(red: 0.98, green: 0.62, blue: 0.42), Color(red: 0.86, green: 0.36, blue: 0.62),
                    Color(red: 0.42, green: 0.40, blue: 0.92),
                ])
                canvas.fill(
                    path,
                    with: .radialGradient(
                        gradient, center: CGPoint(x: center.x - base * 0.3, y: center.y - base * 0.4),
                        startRadius: 0, endRadius: base * 1.6))
                canvas.stroke(path, with: .color(.white.opacity(0.35)), lineWidth: 1)
            }
        }
        .accessibilityLabel(isListening ? "tälli hört zu" : "tälli")
    }

    /// A closed, wobbling outline: slow breathing waves plus faster ripples that grow with the voice.
    static func blob(center: CGPoint, radius: CGFloat, time: Double, energy: CGFloat) -> Path {
        var path = Path()
        let steps = 72
        for step in 0...steps {
            let angle = Double(step) / Double(steps) * 2 * .pi
            let wobble =
                0.05 * sin(3 * angle + time * 1.1) + 0.035 * sin(5 * angle - time * 0.7)
                + Double(energy) * 0.12 * sin(7 * angle + time * 5.0)
            let r = radius * (1 + CGFloat(wobble))
            let point = CGPoint(x: center.x + r * CGFloat(cos(angle)), y: center.y + r * CGFloat(sin(angle)))
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}
