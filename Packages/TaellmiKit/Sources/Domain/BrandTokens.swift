import Foundation

/// tällmi's design tokens: colours, type, tälli's look and motion. They are config (setting `brand.tokens`,
/// seeded from `Seeds/brand.json`, documented in `docs/brand/tokens.json`), so views never hold literals.
/// Times are seconds; sizes are fractions of the referenced size.
public struct BrandTokens: Sendable, Equatable, Codable {
    public var color: Colors
    public var talli: Talli
    public var type: TypeTokens
    public var motion: Motion
    public var menuBar: MenuBar
    /// Named curves and springs, e.g. `soft`, `enter`, `spring.appear`.
    public var easing: [String: Easing]
    /// How see-through each window and panel is, and what it turns into for accessibility.
    public var surface: Surfaces
    /// Quiet fills on top of a surface, by name (e.g. `field`, `selection`, `mark.spoken`).
    public var fill: [String: Fill]
    public var shape: Shape

    /// Decodes the tokens from their JSON config value.
    public init(json: JSONValue) throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self = try decoder.decode(BrandTokens.self, from: JSONEncoder().encode(json))
    }

    public struct Colors: Sendable, Equatable, Codable {
        public var light: Palette
        public var dark: Palette
    }

    public struct Palette: Sendable, Equatable, Codable {
        public var paper: Swatch
        public var ink: Swatch
        public var blue: Swatch
        public var mist: Swatch
        public var pink: Swatch
        public var quiet: Swatch
    }

    public struct Swatch: Sendable, Equatable, Codable {
        /// `#RRGGBB`.
        public var value: String
        /// The label colour to use on top of this swatch, where one is defined (the accent).
        public var labelOnBlue: String?
    }

    public struct Stop: Sendable, Equatable, Codable {
        public var color: String
        public var at: Double
    }

    public struct Talli: Sendable, Equatable, Codable {
        public var glyph: Glyph
        public var eyes: Eyes
        public var body: Body
        public var mouth: Mouth
        public var letters: Letters
        public var groundNight: Ground
        public var layout: Layout
        public var brow: Brow

        public struct Layout: Sendable, Equatable, Codable {
            public var fitHeight: Double
            public var fitWidth: Double
            public var fill: Double
            public var centerY: Double
        }

        public struct Brow: Sendable, Equatable, Codable {
            public var length: Double
            public var lift: Double
            public var spread: Double
            public var thinning: Double
        }

        public struct Glyph: Sendable, Equatable, Codable {
            public var font: String
            public var weight: Double
            public var char: String
            public var softenStroke: Double
        }

        public struct Eyes: Sendable, Equatable, Codable {
            public var radius: Double
            public var gap: Double
            public var offsetX: Double
            public var liftAboveXheight: Double
            public var xheightPad: Double
            public var travelX: Double
            public var travelY: Double
        }

        public struct Body: Sendable, Equatable, Codable {
            public var fill: Fill
            public var overlays: [Overlay]
        }

        public struct Fill: Sendable, Equatable, Codable {
            public var from: [Double]
            public var to: [Double]
            public var stops: [Stop]
        }

        public struct Overlay: Sendable, Equatable, Codable {
            public var center: [Double]
            public var radius: Double
            public var color: String
            public var opacity: Double
        }

        public struct Mouth: Sendable, Equatable, Codable {
            public var center: [Double]
            public var rx: Double
            public var ry: Double
            public var openRx: Double
            public var openRy: Double
        }

        public struct Letters: Sendable, Equatable, Codable {
            public var size: Double
            public var max: Int
        }

        public struct Ground: Sendable, Equatable, Codable {
            public var center: [Double]
            public var radius: Double
            public var stops: [Stop]
        }
    }

    public struct TypeTokens: Sendable, Equatable, Codable {
        public var families: Families
        public var base: Base
        public var scale: [String: Style]

        public struct Families: Sendable, Equatable, Codable {
            public var display: String
            public var text: String
        }

        public struct Base: Sendable, Equatable, Codable {
            public var sizePt: Double
        }

        public struct Style: Sendable, Equatable, Codable {
            /// `display` or `text`.
            public var family: String
            public var weight: Double
            /// A multiple of the macOS body size.
            public var size: Double
            public var line: Double
            public var tracking: Double
            public var italic: Bool?
        }
    }

    public struct Easing: Sendable, Equatable, Codable {
        /// Cubic Bézier control points x1, y1, x2, y2.
        public var bezier: [Double]?
        /// Spring response in seconds and damping ratio (1 = no overshoot).
        public var response: Double?
        public var damping: Double?
    }

    public struct Motion: Sendable, Equatable, Codable {
        public var appearCursor: Appear
        public var appearLaunch: Appear
        public var breath: Breath
        public var voice: Voice
        public var pause: Pause
        public var thinking: Thinking
        public var saving: Saving
        public var blink: Blink
        public var crossfade: Crossfade
        public var scroll: Crossfade
        public var timeOfDay: TimeOfDay

        enum CodingKeys: String, CodingKey {
            case appearCursor = "appear.cursor"
            case appearLaunch = "appear.launch"
            case breath, voice, pause, thinking, saving, blink, crossfade, scroll, timeOfDay
        }

        public struct Appear: Sendable, Equatable, Codable {
            public var duration: Double
            public var fromScale: Double
            public var rise: Double?
            public var fromX: Double?
            public var fromRotationRad: Double?
            public var fadeIn: Double
            public var eyesOpenAt: Double
            public var eyesOpenFor: Double
            public var lookAtYouAt: Double?
            public var lookAside: [Double]?
            /// The name of the spring in `easing`.
            public var easing: String
        }

        public struct Breath: Sendable, Equatable, Codable {
            public var period: Double
            public var amplitude: Double
            public var nightSlower: Double
            public var morningFaster: Double
        }

        public struct Voice: Sendable, Equatable, Codable {
            public var swellMax: Double
            public var attack: Double
            public var release: Double
            public var dotPulseMax: Double
            public var squash: Double
            public var silenceBelow: Double
            public var reduceMotionDim: Double
        }

        public struct Pause: Sendable, Equatable, Codable {
            public var afterSilence: Double
            public var driftEveryMin: Double
            public var driftEveryMax: Double
            public var driftX: Double
            public var driftY: Double
            public var driftSmoothing: Double
        }

        public struct Thinking: Sendable, Equatable, Codable {
            public var firstLetterAfter: Double
            public var letterEveryMin: Double
            public var letterEveryMax: Double
            public var letterIn: Double
            public var letterOut: Double
            public var look: [Double]
            public var lookSway: Double
            public var lookSwaySpeed: Double
            public var browEveryMin: Double
            public var browEveryMax: Double
            public var browDuration: Double
        }

        public struct Saving: Sendable, Equatable, Codable {
            public var settle: Double
            public var settleDepth: Double
            public var blinkAt: Double
            public var sayAt: Double
            public var mouthResponse: Double
        }

        public struct Blink: Sendable, Equatable, Codable {
            public var duration: Double
            public var nightLonger: Double
            public var everyMin: Double
            public var everyMax: Double
            public var nightLid: Double
            public var morningMore: Double
        }

        /// A timed transition: a duration and the name of its curve in `easing`.
        public struct Crossfade: Sendable, Equatable, Codable {
            public var duration: Double
            public var easing: String
        }

        public struct TimeOfDay: Sendable, Equatable, Codable {
            public var nightCenterH: Double
            public var nightWidthH: Double
            public var morningCenterH: Double
            public var morningWidthH: Double
            public var nightFalloffH: Double
        }
    }

    public struct Surfaces: Sendable, Equatable, Codable {
        public var window: Surface
        public var reading: Surface
        public var panel: Surface
        public var bubble: Surface
        public var outline: Outline
    }

    public struct Surface: Sendable, Equatable, Codable {
        /// A macOS material by name (`popover`, `under_window_background`, …) or `glass`.
        public var material: String
        /// A colour role (`paper`, `mist`, …) laid over the material.
        public var tint: String
        public var tintOpacity: Pair
        /// The solid colour role used when transparency is off or contrast is increased.
        public var fallback: String
    }

    public struct Pair: Sendable, Equatable, Codable {
        public var light: Double
        public var dark: Double
    }

    public struct Outline: Sendable, Equatable, Codable {
        public var color: String
        public var widthPt: Double
    }

    public struct Fill: Sendable, Equatable, Codable {
        public var color: String
        public var opacity: Double
        public var contrastOpacity: Double
    }

    public struct Shape: Sendable, Equatable, Codable {
        /// Corner radii in points, by name (`field`, `panel`, `bubble`, `mark`).
        public var radiusPt: [String: Double]
    }

    public struct MenuBar: Sendable, Equatable, Codable {
        public var sizePt: Double
        public var em: Double
    }
}
