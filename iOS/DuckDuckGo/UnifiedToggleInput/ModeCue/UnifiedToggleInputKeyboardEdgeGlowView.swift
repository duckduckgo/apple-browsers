//
//  UnifiedToggleInputKeyboardEdgeGlowView.swift
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

/// A crisp hairline on the keyboard's top edge with a glow rising off it in the mode's colours, as if
/// the keyboard cast a coloured shadow upwards that fades as it goes. It breathes, and its hues drift.
///
/// Drawn in the app's window, which sits under the keyboard, so the keyboard covers everything below
/// its edge and only the outline and the corner gaps show. Hidden whenever the software keyboard is
/// off screen, where the guide would otherwise leave it at the bottom of the screen.
final class UnifiedToggleInputKeyboardEdgeGlowView: UIView {

    private enum Metrics {
        /// Matches the system keyboard's top corners.
        static let keyboardCornerRadius: CGFloat = 30
        static let lineWidth: CGFloat = 1.5
        static let lineGlowRadius: CGFloat = 3
        /// Straight run below each corner, so the hairline follows the keyboard's sides into the gaps.
        static let sideRun: CGFloat = 12
        /// How far the rising glow reaches above the keyboard.
        static let auraHeight: CGFloat = 48

        static let auraOpacity: Float = 0.24
        static let auraBreathingOpacity: Float = 0.4
        static let auraPeriod: CFTimeInterval = 2.8
        static let lineOpacity: Float = 0.5
        static let lineBreathingOpacity: Float = 0.8
        static let linePeriod: CFTimeInterval = 2.2
        /// Shorter than this, the keyboard frame is only an accessory bar over a hardware keyboard.
        static let minimumKeyboardHeight: CGFloat = 120
    }

    /// Alpha of the rising glow from its top (far from the keyboard) down to the keyboard edge. Eased,
    /// so it melts into the page instead of ending on a visible line.
    private enum AuraFalloff {
        static let alphas: [CGFloat] = [0, 0.02, 0.07, 0.2, 0.48, 1]
    }

    private let lineGradientLayer = CAGradientLayer()
    private let lineMask = CAShapeLayer()
    private let auraLayer = CAGradientLayer()
    private let auraFalloffMask = CAGradientLayer()
    private let isReduceMotionEnabled: () -> Bool
    private var mode: TextEntryMode = .search
    private var isShowing = false
    private var isKeyboardOnScreen = false

    init(isReduceMotionEnabled: @escaping () -> Bool = { UIAccessibility.isReduceMotionEnabled }) {
        self.isReduceMotionEnabled = isReduceMotionEnabled
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        alpha = 0
        setupAura()
        setupLine()
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChangeFrame(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupAura() {
        UnifiedToggleInputModeCueHueDrift.applyRestingPose(to: auraLayer)
        auraLayer.opacity = Metrics.auraOpacity
        auraFalloffMask.startPoint = CGPoint(x: 0.5, y: 0)
        auraFalloffMask.endPoint = CGPoint(x: 0.5, y: 1)
        auraLayer.mask = auraFalloffMask
        layer.addSublayer(auraLayer)
    }

    private func setupLine() {
        UnifiedToggleInputModeCueHueDrift.applyRestingPose(to: lineGradientLayer)
        lineGradientLayer.opacity = Metrics.lineOpacity
        lineMask.fillColor = nil
        lineMask.strokeColor = UIColor.black.cgColor
        lineMask.lineWidth = Metrics.lineWidth
        lineMask.lineCap = .round
        lineMask.shadowColor = UIColor.black.cgColor
        lineMask.shadowOpacity = 1
        lineMask.shadowOffset = .zero
        lineMask.shadowRadius = Metrics.lineGlowRadius
        lineGradientLayer.mask = lineMask
        layer.addSublayer(lineGradientLayer)
    }

    /// Spans the keyboard's width, from the top of the glow down past the keyboard's corners.
    func install(in host: UIView) {
        translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(self)
        let keyboard = host.keyboardLayoutGuide
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: keyboard.leadingAnchor),
            trailingAnchor.constraint(equalTo: keyboard.trailingAnchor),
            topAnchor.constraint(equalTo: keyboard.topAnchor, constant: -Metrics.auraHeight),
            heightAnchor.constraint(equalToConstant: Metrics.auraHeight + Metrics.keyboardCornerRadius + Metrics.sideRun)
        ])
    }

    /// Call inside an animation block to fade.
    func apply(mode: TextEntryMode, isVisible: Bool) {
        self.mode = mode
        isShowing = isVisible
        if isVisible {
            applyColors()
            startGlimmer()
        } else {
            stopGlimmer()
        }
        applyVisibility()
    }

    private func applyVisibility() {
        alpha = isShowing && isKeyboardOnScreen ? 1 : 0
    }

    /// Fades with the keyboard's own animation, so the glow leaves and arrives with it.
    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let screenHeight = window?.windowScene?.screen.bounds.height ?? UIScreen.main.bounds.height
        let visibleHeight = screenHeight - endFrame.minY
        isKeyboardOnScreen = visibleHeight >= Metrics.minimumKeyboardHeight
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
        UIView.animate(withDuration: duration, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.applyVisibility()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lineGradientLayer.frame = bounds
        lineMask.frame = bounds
        lineMask.path = edgePath()
        auraLayer.frame = bounds
        auraFalloffMask.frame = auraLayer.bounds
        applyAuraFalloff()
        CATransaction.commit()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard isShowing else { return }
        applyColors()
    }

    private func applyColors() {
        let gradient = UnifiedToggleInputModeCuePalette.modeColors(for: mode, resolvedWith: traitCollection)
        for layer in [lineGradientLayer, auraLayer] {
            layer.colors = gradient.colors.map(\.cgColor)
            layer.locations = gradient.locations
        }
    }

    /// Fades from nothing at the top to full at the keyboard edge, and stays full below it, where the
    /// keyboard covers it except in the corner gaps.
    private func applyAuraFalloff() {
        guard bounds.height > 0 else { return }
        let edgeLocation = Metrics.auraHeight / bounds.height
        let falloff = AuraFalloff.alphas
        let steps = CGFloat(falloff.count - 1)
        auraFalloffMask.colors = (falloff + [1]).map { UIColor.black.withAlphaComponent($0).cgColor }
        auraFalloffMask.locations = falloff.indices.map { NSNumber(value: Double(edgeLocation * CGFloat($0) / steps)) } + [1]
    }

    /// Straddles the keyboard's edge, so the hairline sits right on it.
    private func edgePath() -> CGPath {
        let radius = Metrics.keyboardCornerRadius
        let inset = Metrics.lineWidth / 2
        let top = Metrics.auraHeight - inset
        let bottom = top + radius + Metrics.sideRun
        let left = inset
        let right = bounds.width - inset
        let path = UIBezierPath()
        path.move(to: CGPoint(x: left, y: bottom))
        path.addLine(to: CGPoint(x: left, y: top + radius))
        path.addArc(withCenter: CGPoint(x: left + radius, y: top + radius), radius: radius,
                    startAngle: .pi, endAngle: .pi * 1.5, clockwise: true)
        path.addLine(to: CGPoint(x: right - radius, y: top))
        path.addArc(withCenter: CGPoint(x: right - radius, y: top + radius), radius: radius,
                    startAngle: .pi * 1.5, endAngle: 0, clockwise: true)
        path.addLine(to: CGPoint(x: right, y: bottom))
        return path.cgPath
    }

    // MARK: - Glimmer

    /// Brightness of the glow and the hairline swings out of step while the hues drift along the edge.
    private func startGlimmer() {
        guard !isReduceMotionEnabled() else { return }
        UnifiedToggleInputModeCueBreathing.start(on: auraLayer, keyPath: "opacity",
                                                 from: Metrics.auraOpacity, to: Metrics.auraBreathingOpacity,
                                                 period: Metrics.auraPeriod)
        UnifiedToggleInputModeCueBreathing.start(on: lineGradientLayer, keyPath: "opacity",
                                                 from: Metrics.lineOpacity, to: Metrics.lineBreathingOpacity,
                                                 period: Metrics.linePeriod)
        UnifiedToggleInputModeCueHueDrift.start(on: auraLayer)
        UnifiedToggleInputModeCueHueDrift.start(on: lineGradientLayer)
    }

    private func stopGlimmer() {
        UnifiedToggleInputModeCueBreathing.stop(on: auraLayer, keyPath: "opacity")
        UnifiedToggleInputModeCueBreathing.stop(on: lineGradientLayer, keyPath: "opacity")
        UnifiedToggleInputModeCueHueDrift.stop(on: auraLayer)
        UnifiedToggleInputModeCueHueDrift.stop(on: lineGradientLayer)
    }
}
