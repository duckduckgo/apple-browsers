//
//  UnifiedToggleInputModeCueSweepView.swift
//  DuckDuckGo
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

import UIKit

/// A comet of light that travels around a rounded border and fades out while still moving.
///
/// The colour comes from a gradient filling the pill; the mask decides how much of it is showing and
/// where. Travel is driven by `lineDashPhase` rather than by rotating the gradient, because the pill
/// is a wide capsule — a rotating cone crosses the flat edges far faster than the round caps, which
/// reads as the highlight surging and stalling twice a lap. Advancing a dash moves it at a constant
/// arc length per second, and wraps seamlessly at the seam.
final class UnifiedToggleInputModeCueSweepView: UIView {

    struct Style {
        let lineWidth: CGFloat
        /// A soft halo around the comet, so it reads as light rather than a hard stroke.
        let glowRadius: CGFloat
        /// Longer borders want a shorter lap time than the pill, or the comet crawls.
        let secondsPerLap: CFTimeInterval
        let laps: CGFloat
        /// Linear reads as steady travel round a loop; a curve lets a one-off sweep launch and settle.
        let timing: CAMediaTimingFunction
        /// A wider halo on the comet's head than on its tail, so the head reads as the light source.
        let headGlowRadius: CGFloat
        /// How brightly the whole border lights up in the comet's wake; 0 for none.
        let afterglowOpacity: Float

    }

    private enum Metrics {
        static let fadeInDuration: TimeInterval = 0.14
        static let fadeOutDuration: TimeInterval = 0.32
    }

    /// Room past the bounds for the halo, which would otherwise be clipped.
    private var bleed: CGFloat { style.glowRadius * 3 }
    private var travelDuration: CFTimeInterval { style.secondsPerLap * CFTimeInterval(style.laps) }
    /// The fade-out overlaps the final stretch, so the comet leaves while still moving.
    private var holdDuration: TimeInterval {
        max(travelDuration - Metrics.fadeInDuration - Metrics.fadeOutDuration, 0)
    }

    /// A tail of faint, overlapping segments that stack into an even fade, ending in a bright head.
    /// Lengths are fractions of the perimeter; every segment ends at the same point.
    private enum Comet {
        static let tailSegmentCount = 9
        static let longestTail: CGFloat = 0.36
        static let shortestTail: CGFloat = 0.06
        static let tailOpacity: Float = 0.14
        static let head: (lengthFraction: CGFloat, opacity: Float) = (0.04, 1.0)

        static let segments: [(lengthFraction: CGFloat, opacity: Float)] = {
            let step = (longestTail - shortestTail) / CGFloat(tailSegmentCount - 1)
            let tail = (0..<tailSegmentCount).map { (longestTail - step * CGFloat($0), tailOpacity) }
            return tail + [head]
        }()
    }

    private let cornerRadius: CGFloat
    private let style: Style
    private let gradientLayer = CAGradientLayer()
    private let maskContainer = CALayer()
    private let cometLayers: [CAShapeLayer]
    private let afterglowLayer = CAShapeLayer()
    private var pendingTravel: Bool?

    init(cornerRadius: CGFloat, style: Style) {
        self.cornerRadius = cornerRadius
        self.style = style
        cometLayers = Comet.segments.map { _ in CAShapeLayer() }
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        alpha = 0
        setupLayers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupLayers() {
        gradientLayer.type = .conic
        // For a conic gradient `startPoint` is the cone's centre and `endPoint` sets where angle 0 sits.
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 0)
        layer.addSublayer(gradientLayer)

        for cometLayer in cometLayers {
            cometLayer.fillColor = nil
            cometLayer.strokeColor = UIColor.white.cgColor
            cometLayer.lineWidth = style.lineWidth
            cometLayer.lineCap = .round
            cometLayer.shadowColor = UIColor.white.cgColor
            cometLayer.shadowOpacity = 1
            cometLayer.shadowOffset = .zero
            cometLayer.shadowRadius = style.glowRadius
            maskContainer.addSublayer(cometLayer)
        }
        cometLayers.last?.shadowRadius = style.headGlowRadius
        setupAfterglow()
        layer.mask = maskContainer
    }

    private func setupAfterglow() {
        afterglowLayer.fillColor = nil
        afterglowLayer.strokeColor = UIColor.white.cgColor
        afterglowLayer.lineWidth = style.lineWidth
        afterglowLayer.shadowColor = UIColor.white.cgColor
        afterglowLayer.shadowOpacity = 1
        afterglowLayer.shadowOffset = .zero
        afterglowLayer.shadowRadius = style.headGlowRadius
        afterglowLayer.opacity = 0
        maskContainer.insertSublayer(afterglowLayer, at: 0)
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        // Layout runs inside the host's animations; these are geometry updates, not animatable state.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let bleed = self.bleed
        gradientLayer.frame = bounds.insetBy(dx: -bleed, dy: -bleed)
        maskContainer.frame = gradientLayer.frame
        applyRenderScale()
        applyBorderPath()
        CATransaction.commit()
        startPendingTravel()
    }

    /// Manually created layers default to a scale of 1, which leaves the rounded caps visibly jagged
    /// on a 2x or 3x screen.
    private func applyRenderScale() {
        let scale = traitCollection.displayScale > 0 ? traitCollection.displayScale : 2
        gradientLayer.contentsScale = scale
        maskContainer.contentsScale = scale
        cometLayers.forEach { $0.contentsScale = scale }
    }

    private func applyBorderPath() {
        let inset = style.lineWidth / 2
        let bleed = self.bleed
        let border = CGRect(origin: CGPoint(x: bleed, y: bleed), size: bounds.size).insetBy(dx: inset, dy: inset)
        let path = UIBezierPath(roundedRect: border, cornerRadius: max(cornerRadius - inset, 0)).cgPath
        (cometLayers + [afterglowLayer]).forEach { $0.frame = maskContainer.bounds; $0.path = path }
    }

    private var borderPerimeter: CGFloat {
        let inset = style.lineWidth / 2
        let rect = bounds.insetBy(dx: inset, dy: inset)
        // UIBezierPath clamps the radius the same way, so the two stay in step.
        let radius = min(max(cornerRadius - inset, 0), min(rect.width, rect.height) / 2)
        let straightWidth = max(rect.width - 2 * radius, 0)
        let straightHeight = max(rect.height - 2 * radius, 0)
        return 2 * (straightWidth + straightHeight) + 2 * .pi * radius
    }

    // MARK: - Playback

    /// - Parameter travels: `false` under Reduce Motion — the whole border lights up and fades in the
    ///   mode's colour, so the signal survives without anything moving.
    func play(gradient: UnifiedToggleInputModeCueGradient, travels: Bool, completion: @escaping () -> Void) {
        apply(gradient)
        // The size isn't known until the first layout pass, and the perimeter drives the dash lengths.
        pendingTravel = travels
        startPendingTravel()
        animateEnvelope(completion: completion)
    }

    private func apply(_ gradient: UnifiedToggleInputModeCueGradient) {
        // Resolve dynamic colours against this view's trait collection so dark mode is honoured.
        gradientLayer.colors = gradient.colors.map { $0.resolvedColor(with: traitCollection).cgColor }
        gradientLayer.locations = gradient.locations
    }

    private func startPendingTravel() {
        guard let travels = pendingTravel, !bounds.isEmpty else { return }
        pendingTravel = nil
        let perimeter = borderPerimeter
        configureComet(travels: travels, perimeter: perimeter)
        guard travels else { return }
        addTravelAnimations(perimeter: perimeter)
    }

    private func configureComet(travels: Bool, perimeter: CGFloat) {
        for (index, cometLayer) in cometLayers.enumerated() {
            let segment = Comet.segments[index]
            guard travels else {
                // One evenly lit border rather than a comet frozen mid-lap.
                cometLayer.lineDashPattern = nil
                cometLayer.opacity = index == cometLayers.count - 1 ? 1 : 0
                continue
            }
            let length = perimeter * segment.lengthFraction
            cometLayer.lineDashPattern = [NSNumber(value: length), NSNumber(value: perimeter - length)]
            cometLayer.opacity = segment.opacity
        }
    }

    private func addTravelAnimations(perimeter: CGFloat) {
        let distance = perimeter * style.laps
        for (index, cometLayer) in cometLayers.enumerated() {
            // Offsetting each phase by its own dash length lines the segments up at their leading edge.
            let length = perimeter * Comet.segments[index].lengthFraction
            let travel = CABasicAnimation(keyPath: "lineDashPhase")
            travel.fromValue = length
            travel.toValue = length - distance
            travel.duration = travelDuration
            travel.timingFunction = style.timing
            travel.fillMode = .forwards
            travel.isRemovedOnCompletion = false
            cometLayer.add(travel, forKey: "modeCueTravel")
        }
        addAfterglow()
    }

    /// The whole border swells into light behind the comet and dims away before it finishes.
    private func addAfterglow() {
        guard style.afterglowOpacity > 0 else { return }
        let afterglow = CAKeyframeAnimation(keyPath: "opacity")
        afterglow.values = [0, style.afterglowOpacity, 0]
        afterglow.keyTimes = [0, 0.45, 1]
        afterglow.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn)]
        afterglow.duration = travelDuration
        afterglowLayer.add(afterglow, forKey: "modeCueAfterglow")
    }

    private func animateEnvelope(completion: @escaping () -> Void) {
        UIView.animate(withDuration: Metrics.fadeInDuration, delay: 0, options: .curveEaseOut) {
            self.alpha = 1
        } completion: { _ in
            UIView.animate(withDuration: Metrics.fadeOutDuration, delay: self.holdDuration, options: .curveEaseIn) {
                self.alpha = 0
            } completion: { _ in
                completion()
            }
        }
    }
}
