//
//  ConfettiView.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

#if os(iOS)

import SwiftUI
import DesignResourcesKit

/// A one-shot confetti burst. Draws all particles in a single `Canvas` pass; each particle is a closed-form function of progress.
///
/// Particles are deterministically seeded at init (not on appear) so bursts are reproducible. Progress animates via `Animatable` rather than `TimelineView`.
/// Under Reduce Motion, nothing is drawn (celebration is decorative).
public struct ConfettiView: View {

    public struct Configuration {
        /// How many particles the burst emits.
        public var particleCount: Int
        /// Nominal per-tick travel distance, before decay.
        public var startVelocity: Double
        /// The full angular width of the burst, centred on straight up.
        public var spreadDegrees: Double
        /// Per-tick multiplier applied to velocity.
        public var decay: Double
        /// Downward pull, applied three times per tick.
        public var gravity: Double
        /// How long the burst runs.
        public var duration: TimeInterval
        /// Turns about a particle's own centre, scaled by its individual tilt rate.
        public var zSpin: Double
        /// Base particle size multiplier.
        public var sizeScalar: Double
        /// How much larger than the base a particle may be.
        public var sizeVariation: Double
        /// How much earlier than the end a particle may finish fading.
        public var fadeOutVariance: Double
        /// The shapes to draw from. Repeating a shape weights it more heavily.
        public var shapes: [ConfettiShape]
        /// The colors to draw from, each a body fill with a matching outline.
        public var colors: [ConfettiColor]
        /// Seeds the particle set (fixed by default for reproducibility).
        public var seed: UInt64

        public init(particleCount: Int = 60,
                    startVelocity: Double = 33,
                    spreadDegrees: Double = 96,
                    decay: Double = 0.92,
                    gravity: Double = 1.4,
                    duration: TimeInterval = 5,
                    zSpin: Double = 0.2,
                    sizeScalar: Double = 3,
                    sizeVariation: Double = 1.6,
                    fadeOutVariance: Double = 0.6,
                    shapes: [ConfettiShape] = ConfettiShape.defaultPool,
                    colors: [ConfettiColor] = ConfettiColor.brand,
                    seed: UInt64 = 0xC0FFEE) {
            self.particleCount = max(0, particleCount)
            self.startVelocity = startVelocity
            self.spreadDegrees = spreadDegrees
            // Above 1 the burst never settles; at exactly 1 the closed-form sum degenerates.
            self.decay = min(decay, 1)
            self.gravity = gravity
            self.duration = duration
            self.zSpin = zSpin
            self.sizeScalar = sizeScalar
            self.sizeVariation = sizeVariation
            self.fadeOutVariance = fadeOutVariance
            self.shapes = shapes
            self.colors = colors
            self.seed = seed
        }

        public static let `default` = Configuration()
    }

    private let configuration: Configuration
    private let origin: UnitPoint
    private let stillProgress: Double?
    private let particles: [Particle]

    @State private var isAnimating = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private init(configuration: Configuration, origin: UnitPoint, stillProgress: Double?) {
        self.configuration = configuration
        self.origin = origin
        self.stillProgress = stillProgress

        var generator = SeededGenerator(seed: configuration.seed)
        self.particles = (0..<configuration.particleCount).map { _ in
            Particle(configuration: configuration, using: &generator)
        }
    }

    public init(configuration: Configuration = .default, origin: UnitPoint = .center) {
        self.init(configuration: configuration, origin: origin, stillProgress: nil)
    }

    /// A burst frozen at `elapsed` seconds (for static previews and snapshot tests).
    public init(configuration: Configuration = .default, origin: UnitPoint = .center, still elapsed: TimeInterval) {
        self.init(configuration: configuration,
                  origin: origin,
                  stillProgress: elapsed / max(configuration.duration, .leastNonzeroMagnitude))
    }

    public var body: some View {
        Group {
            if reduceMotion {
                Color.clear
            } else {
                burst
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Rendering

private extension ConfettiView {

    @ViewBuilder
    var burst: some View {
        if let stillProgress {
            canvas(progress: stillProgress)
        } else {
            canvas(progress: isAnimating ? 1 : 0)
                .onAppear {
                    // Defer the animation start so progress-0 frame commits first, then SwiftUI interpolates.
                    DispatchQueue.main.async {
                        withAnimation(.linear(duration: configuration.duration)) {
                            isAnimating = true
                        }
                    }
                }
        }
    }

    func canvas(progress: Double) -> some View {
        ConfettiCanvas(progress: progress, particles: particles, configuration: configuration, origin: origin)
    }
}

/// Draws particles at a given progress. Conforming to `Animatable` triggers SwiftUI re-renders for each animation frame.
private struct ConfettiCanvas: View, Animatable {
    private static let ticksPerSecond: Double = 60

    var progress: Double
    let particles: [Particle]
    let configuration: ConfettiView.Configuration
    let origin: UnitPoint

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { graphics, size in
            draw(in: &graphics, size: size)
        }
        // Canvas claims full area (no intrinsic size).
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func draw(in graphics: inout GraphicsContext, size: CGSize) {
        let tick = progress * configuration.duration * Self.ticksPerSecond
        let anchor = CGPoint(x: size.width * origin.x, y: size.height * origin.y)
        let shadings = resolvedShadings(in: graphics)

        for particle in particles {
            let opacity = particle.opacity(atProgress: progress)
            guard opacity > 0 else { continue }

            let scale = particle.size * particle.popScale(atProgress: progress)
            guard scale > 0 else { continue }

            let offset = particle.offset(atTick: tick, configuration: configuration)
            let variant = particle.variant
            let shading = shadings[particle.colorIndex]

            // The transform goes on the context rather than into `Path.applying`, which would rebuild both
            // paths — 100+ curve segments each for the star and blob outlines — for every particle, every
            // frame. Here CoreGraphics applies it via the CTM and the stored paths are reused as-is.
            var layer = graphics
            layer.opacity = opacity
            layer.translateBy(x: anchor.x + offset.width, y: anchor.y + offset.height)
            layer.rotate(by: .radians(particle.rotation(atProgress: progress)))
            layer.scaleBy(x: scale, y: scale)

            layer.fill(variant.body, with: shading.body)

            if variant.clipsOutlineToBody {
                layer.clip(to: variant.body)
            }
            layer.fill(variant.outline, with: shading.outline)
        }
    }

    private func resolvedShadings(in graphics: GraphicsContext) -> [(body: GraphicsContext.Shading, outline: GraphicsContext.Shading)] {
        let palette = configuration.colors.isEmpty ? ConfettiColor.brand : configuration.colors
        return palette.map { (graphics.resolve(.color($0.fill)), graphics.resolve(.color($0.stroke))) }
    }
}

// MARK: - Particle

/// One particle's fixed properties. Time-varying values are derived from these for frame-independent rendering.
private struct Particle {
    /// Gravity is applied three times per tick.
    private static let gravityTicksPerStep: Double = 3
    /// How strongly a larger (nearer) particle falls faster than the base size.
    private static let depthGravityInfluence: Double = 0.35
    /// Sideways wobble amplitude, as a multiple of the configured size scalar.
    private static let wobbleAmplitude: Double = 15
    /// The fraction of the burst spent on the initial pop.
    private static let popFraction: Double = 0.08
    /// How far into the pop the particle reaches its overshoot before easing back.
    private static let popPeakFraction: Double = 0.6
    /// The overshoot the pop reaches before settling at full size.
    private static let popOvershoot: Double = 1.15
    /// How long before `fadeOutEnd` a particle begins fading.
    private static let fadeLength: Double = 0.5
    /// Where in the fade the particle has lost half its opacity.
    private static let fadeMidFraction: Double = 0.6

    let variant: ConfettiShape.Variant
    let colorIndex: Int
    let angle: Double
    /// `cos`/`sin` of `angle` and the wobble's starting phase, all fixed at init — recomputing them per
    /// frame was ~54,000 redundant transcendental calls over a single burst.
    let cosAngle: Double
    let sinAngle: Double
    let wobbleBase: Double
    let velocity: Double
    /// The particle's drawn size in points.
    let size: Double
    let depthGravity: Double
    let wobbleSpeed: Double
    let wobbleOffset: Double
    let turns: Double
    let initialRotation: Double
    let fadeOutEnd: Double

    init(configuration: ConfettiView.Configuration, using generator: inout SeededGenerator) {
        let shape = configuration.shapes.randomElement(using: &generator) ?? .rect
        variant = shape.variants.randomElement(using: &generator) ?? ConfettiShape.rect.variants[0]
        colorIndex = configuration.colors.indices.randomElement(using: &generator) ?? 0

        // Straight up is -90°, with the spread opening symmetrically around it.
        let spread = configuration.spreadDegrees * .pi / 180
        angle = -.pi / 2 + (spread / 2 - Double.random(in: 0...spread, using: &generator))
        cosAngle = cos(angle)
        sinAngle = sin(angle)

        velocity = configuration.startVelocity * 0.5 + Double.random(in: 0...1, using: &generator) * configuration.startVelocity

        let baseSize = 6 * configuration.sizeScalar
        size = baseSize + Double.random(in: 0...1, using: &generator) * baseSize * configuration.sizeVariation

        let depth = size / max(baseSize, 1)
        depthGravity = configuration.gravity * (1 + (depth - 1) * Self.depthGravityInfluence)

        wobbleSpeed = min(0.11, Double.random(in: 0...1, using: &generator) * 0.1 + 0.05)
        wobbleOffset = Double.random(in: 0...10, using: &generator)
        wobbleBase = cos(wobbleOffset)

        turns = (2 + Double.random(in: 0...4, using: &generator)) * configuration.zSpin
        initialRotation = Double.random(in: 0...(2 * .pi), using: &generator)

        fadeOutEnd = 1 - Double.random(in: 0...1, using: &generator) * configuration.fadeOutVariance
    }

    /// Where the particle sits after `tick` ticks (closed-form calculation).
    func offset(atTick tick: Double, configuration: ConfettiView.Configuration) -> CGSize {
        let decay = configuration.decay
        // The geometric sum is 0/0 at decay == 1, where velocity never decays and travel is simply v * n.
        let travel = decay == 1 ? velocity * tick
                                : velocity * (1 - pow(decay, tick)) / (1 - decay)

        let wobble = (cos(wobbleOffset + wobbleSpeed * tick) - wobbleBase) * (Self.wobbleAmplitude * configuration.sizeScalar)

        return CGSize(width: cosAngle * travel + wobble,
                      height: sinAngle * travel + depthGravity * Self.gravityTicksPerStep * tick)
    }

    func popScale(atProgress progress: Double) -> Double {
        let growth = Self.popFraction * Self.popPeakFraction
        if progress < growth {
            return (progress / growth) * Self.popOvershoot
        }
        if progress < Self.popFraction {
            let settling = (progress - growth) / (Self.popFraction - growth)
            return Self.popOvershoot - settling * (Self.popOvershoot - 1)
        }
        return 1
    }

    func rotation(atProgress progress: Double) -> Double {
        initialRotation + turns * 2 * .pi * progress
    }

    func opacity(atProgress progress: Double) -> Double {
        let start = max(0, fadeOutEnd - Self.fadeLength)
        guard progress > start else { return 1 }
        guard progress < fadeOutEnd else { return 0 }

        // Past the guards above, start < mid < fadeOutEnd holds for any configuration.
        let mid = start + (fadeOutEnd - start) * Self.fadeMidFraction
        if progress <= mid {
            return 1 - ((progress - start) / (mid - start)) * 0.5
        }
        return 0.5 - ((progress - mid) / (fadeOutEnd - mid)) * 0.5
    }
}

// MARK: - Deterministic randomness

/// SplitMix64 deterministic generator for reproducible particle sets.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

// MARK: - Particle color

public struct ConfettiColor {
    public let fill: Color
    public let stroke: Color

    public init(fill: Color, stroke: Color) {
        self.fill = fill
        self.stroke = stroke
    }
}

public extension ConfettiColor {
    static let brandMandarin = ConfettiColor(fill: Color(singleUseColor: .rebranding(.confettiMandarinFill)),
                                             stroke: Color(singleUseColor: .rebranding(.confettiMandarinStroke)))
    static let brandPondwater = ConfettiColor(fill: Color(singleUseColor: .rebranding(.confettiPondwaterFill)),
                                              stroke: Color(singleUseColor: .rebranding(.confettiPondwaterStroke)))
    static let brandLilypad = ConfettiColor(fill: Color(singleUseColor: .rebranding(.confettiLilypadFill)),
                                            stroke: Color(singleUseColor: .rebranding(.confettiLilypadStroke)))
    static let brandBlossom = ConfettiColor(fill: Color(singleUseColor: .rebranding(.confettiBlossomFill)),
                                            stroke: Color(singleUseColor: .rebranding(.confettiBlossomStroke)))
    static let brandPollen = ConfettiColor(fill: Color(singleUseColor: .rebranding(.confettiPollenFill)),
                                           stroke: Color(singleUseColor: .rebranding(.confettiPollenStroke)))

    static let brand: [ConfettiColor] = [.brandMandarin, .brandPondwater, .brandLilypad, .brandBlossom, .brandPollen]
}

#if DEBUG

/// Animates on appear (requires live preview; use "Still" previews for static snapshots).
private struct ConfettiViewPreview: View {
    @State private var runID = UUID()

    var body: some View {
        ZStack {
            Color(designSystemColor: .surfaceTertiary).ignoresSafeArea()

            Button("Replay") { runID = UUID() }

            ConfettiView()
                .id(runID)
        }
    }
}

private struct ConfettiStillPreview: View {
    var elapsed: TimeInterval
    var configuration: ConfettiView.Configuration = .default

    var body: some View {
        ZStack {
            Color(designSystemColor: .surfaceTertiary).ignoresSafeArea()
            ConfettiView(configuration: configuration, still: elapsed)
        }
    }
}

#Preview("Animated") {
    ConfettiViewPreview()
}

#Preview("Still — pop") {
    ConfettiStillPreview(elapsed: 0.2)
}

#Preview("Still — mid-flight") {
    ConfettiStillPreview(elapsed: 0.8)
}

#Preview("Still — raining") {
    ConfettiStillPreview(elapsed: 2.0)
}

#Preview("Still — dark") {
    ConfettiStillPreview(elapsed: 0.8)
        .preferredColorScheme(.dark)
}

#Preview("Configured — stars only, one color") {
    ConfettiStillPreview(elapsed: 0.8,
                         configuration: .init(particleCount: 30,
                                              shapes: [.star],
                                              colors: [.brandPollen]))
}

// Reduce Motion: enable in Settings > Accessibility > Motion in the simulator.

#endif

#endif
