//
//  UnifiedToggleInputModeBorderView.swift
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

/// A soft, fuzzy border in the mode's colours with a glow bleeding out of it, traced around the card.
/// While shown it breathes and its hues drift along it, so it feels alive.
///
/// The glow is the border's own shadow inside the mask, so line and halo always stay in step.
final class UnifiedToggleInputModeBorderView: UIView {

    private enum Metrics {
        static let lineWidth: CGFloat = 1.5
        static let glowRadius: CGFloat = 4
        static let breathingGlowRadius: CGFloat = 11
        static let opacity: Float = 0.5
        static let breathingOpacity: Float = 1
        static let opacityPeriod: CFTimeInterval = 2.2
        static let glowPeriod: CFTimeInterval = 2.9
        /// Room past the bounds for the halo, which would otherwise be clipped.
        static var bleed: CGFloat { breathingGlowRadius * 3 }
    }

    var cornerRadius: CGFloat = 0 {
        didSet {
            guard cornerRadius != oldValue else { return }
            setNeedsLayout()
        }
    }

    private let gradientLayer = CAGradientLayer()
    private let strokeMask = CAShapeLayer()
    private let isReduceMotionEnabled: () -> Bool
    private var mode: TextEntryMode = .search
    private var isShowing = false

    init(isReduceMotionEnabled: @escaping () -> Bool = { UIAccessibility.isReduceMotionEnabled }) {
        self.isReduceMotionEnabled = isReduceMotionEnabled
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        alpha = 0
        UnifiedToggleInputModeCueHueDrift.applyRestingPose(to: gradientLayer)
        gradientLayer.opacity = Metrics.opacity
        strokeMask.fillColor = nil
        strokeMask.strokeColor = UIColor.black.cgColor
        strokeMask.lineWidth = Metrics.lineWidth
        strokeMask.shadowColor = UIColor.black.cgColor
        strokeMask.shadowOpacity = 1
        strokeMask.shadowOffset = .zero
        strokeMask.shadowRadius = Metrics.glowRadius
        gradientLayer.mask = strokeMask
        layer.addSublayer(gradientLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Call inside an animation block to fade.
    func apply(mode: TextEntryMode, isVisible: Bool) {
        self.mode = mode
        isShowing = isVisible
        if isVisible {
            applyColors()
            startBreathing()
        } else {
            stopBreathing()
        }
        alpha = isVisible ? 1 : 0
    }

    private func startBreathing() {
        guard !isReduceMotionEnabled() else { return }
        UnifiedToggleInputModeCueBreathing.start(on: gradientLayer, keyPath: "opacity",
                                                 from: Metrics.opacity, to: Metrics.breathingOpacity,
                                                 period: Metrics.opacityPeriod)
        UnifiedToggleInputModeCueBreathing.start(on: strokeMask, keyPath: "shadowRadius",
                                                 from: Metrics.glowRadius, to: Metrics.breathingGlowRadius,
                                                 period: Metrics.glowPeriod)
        UnifiedToggleInputModeCueHueDrift.start(on: gradientLayer)
    }

    private func stopBreathing() {
        UnifiedToggleInputModeCueBreathing.stop(on: gradientLayer, keyPath: "opacity")
        UnifiedToggleInputModeCueBreathing.stop(on: strokeMask, keyPath: "shadowRadius")
        UnifiedToggleInputModeCueHueDrift.stop(on: gradientLayer)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let bleed = Metrics.bleed
        gradientLayer.frame = bounds.insetBy(dx: -bleed, dy: -bleed)
        strokeMask.frame = gradientLayer.bounds
        let inset = Metrics.lineWidth / 2
        let border = bounds.insetBy(dx: inset, dy: inset).offsetBy(dx: bleed, dy: bleed)
        strokeMask.path = UIBezierPath(roundedRect: border, cornerRadius: max(cornerRadius - inset, 0)).cgPath
        CATransaction.commit()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard isShowing else { return }
        applyColors()
    }

    private func applyColors() {
        let gradient = UnifiedToggleInputModeCuePalette.modeColors(for: mode, resolvedWith: traitCollection)
        gradientLayer.colors = gradient.colors.map(\.cgColor)
        gradientLayer.locations = gradient.locations
    }
}
