//
//  SpinnerView.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import AppKit
import DesignResourcesKit

final class SpinnerView: NSView {

    private lazy var spinnerGradientColors = SpinnerGradientColors(startColor: progressStartColor, finalColor: progressFinalColor)
    private lazy var spinnerLayer: CAShapeLayer = buildSpinnerLayer()
    private lazy var gradientLayer: CAGradientLayer = {
        let layer = buildGradientLayer()
        layer.mask = spinnerLayer
        return layer
    }()

    private var mustRemoveRotationAnimation = false

    var lineLengthInDegrees: CGFloat = SpinnerConstants.defaultLineLength {
        didSet {
            refreshGradientBounds()
        }
    }

    var lineWidth: CGFloat = SpinnerConstants.defaultLineWidth {
        didSet {
            refreshSpinnerLineWidth()
        }
    }

    var progressStartColor: NSColor = NSColor(designSystemColor: .spinnerStart) {
        didSet {
            refreshGradientColors()
        }
    }

    var progressFinalColor: NSColor = NSColor(designSystemColor: .spinnerFinal) {
        didSet {
            refreshGradientColors()
        }
    }

    var hidesWhenStopped = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayer()
        setupInitialState()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
        setupInitialState()
    }

    override func layout() {
        super.layout()
        refreshGradientBounds()
    }
}

extension SpinnerView {

    var isAnimating: Bool {
        gradientLayer.animation(forKey: SpinnerConstants.rotationAnimationKey) != nil
    }

    func startAnimating() {
        cancelPendingRotationAnimationRemoval()
        ensureGradientLayerIsVisible()

        if isAnimating {
            return
        }

        let fadeInAnimation =  CASpringAnimation.buildFadeInAnimation(duration: SpinnerConstants.animationShortDuration)
        let rotationAnimation = CABasicAnimation.buildRotationAnimation(duration: SpinnerConstants.animationLongDuration)

        gradientLayer.colors = spinnerGradientColors.gradientColors(rendered: false)

        gradientLayer.add(fadeInAnimation, forKey: SpinnerConstants.fadeAnimationKey)
        gradientLayer.add(rotationAnimation, forKey: SpinnerConstants.rotationAnimationKey)
    }

    func stopAnimating(animated: Bool = true) {
        guard mustRemoveRotationAnimation == false else {
            return
        }

        guard isAnimating, animated else {
            removeRotationAnimationAndHide()
            return
        }

        mustRemoveRotationAnimation = true

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.removeRotationAnimationIfNeeded()
        }

        let fadeOutAnimation = CASpringAnimation.buildFadeOutAnimation(duration: SpinnerConstants.animationShortDuration)
        gradientLayer.opacity = 0
        gradientLayer.add(fadeOutAnimation, forKey: SpinnerConstants.fadeAnimationKey)

        CATransaction.commit()
    }

    func refreshSpinnerColorsIfNeeded(rendered: Bool, animated: Bool = true) {
        let currentColors = gradientLayer.colors as? [CGColor] ?? []
        let targetColors = spinnerGradientColors.gradientColors(rendered: rendered)

        guard currentColors != targetColors else {
            return
        }

        gradientLayer.colors = targetColors

        guard animated else {
            return
        }

        let animation = CABasicAnimation.buildColorsAnimation(duration: SpinnerConstants.animationShortDuration, fromValue: currentColors, toValue: targetColors)
        gradientLayer.add(animation, forKey: SpinnerConstants.colorsAnimationKey)
    }
}

private extension SpinnerView {

    func setupLayer() {
        wantsLayer = true
        layer?.addSublayer(gradientLayer)
    }

    func setupInitialState() {
        gradientLayer.isHidden = hidesWhenStopped
    }

    func refreshGradientBounds() {
        gradientLayer.frame = bounds
        spinnerLayer.path = buildSpinnerPath()
        spinnerLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    func refreshSpinnerLineWidth() {
        spinnerLayer.lineWidth = lineWidth
    }

    func refreshGradientColors() {
        spinnerGradientColors = SpinnerGradientColors(startColor: progressStartColor, finalColor: progressFinalColor)
    }

    func ensureGradientLayerIsVisible() {
        guard gradientLayer.isHidden || gradientLayer.opacity < 1 else {
            return
        }

        gradientLayer.isHidden = false
        gradientLayer.opacity = 1
    }

    func cancelPendingRotationAnimationRemoval() {
        mustRemoveRotationAnimation = false
    }

    func removeRotationAnimationIfNeeded() {
        guard mustRemoveRotationAnimation else {
            return
        }

        removeRotationAnimationAndHide()
        mustRemoveRotationAnimation = false
    }

    func removeRotationAnimationAndHide() {
        gradientLayer.removeAnimation(forKey: SpinnerConstants.rotationAnimationKey)
        gradientLayer.isHidden = hidesWhenStopped
    }
}

private extension SpinnerView {

    func buildGradientLayer() -> CAGradientLayer {
        let gradient = CAGradientLayer()
        gradient.type = .conic
        gradient.locations = [0, 1]
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 0.5, y: 0)
        gradient.frame = bounds

        return gradient
    }

    func buildSpinnerLayer() -> CAShapeLayer {
        let spinner = CAShapeLayer()
        spinner.path = buildSpinnerPath()
        spinner.strokeColor = .white
        spinner.fillColor = .clear
        spinner.lineWidth = lineWidth
        spinner.lineCap = .round
        spinner.position = CGPoint(x: bounds.midX, y: bounds.midY)
        return spinner
    }

    func buildSpinnerPath() -> CGPath {
        let radius = min(bounds.width, bounds.height) * 0.5 - lineWidth
        let path = CGMutablePath()
        path.addArc(center: .zero, radius: radius, startAngle: .zero, endAngle: lineLengthInDegrees, clockwise: false)
        return path
    }
}

private enum SpinnerConstants {
    static let animationLongDuration: TimeInterval = 0.5
    static let animationShortDuration: TimeInterval = 0.15
    static let defaultLineWidth: CGFloat = 1.5
    static let defaultLineLength: CGFloat = CGFloat.pi * 2 * 0.6
    static let rotationAnimationKey = "rotation"
    static let fadeAnimationKey = "fade"
    static let colorsAnimationKey = "colors"
}

private struct SpinnerGradientColors {
    let startColor: NSColor
    let finalColor: NSColor

    private func gradient(baseColor: NSColor) -> [CGColor] {
        [
            baseColor.cgColor,
            baseColor.withAlphaComponent(0).cgColor
        ]
    }

    func gradientColors(rendered: Bool) -> [CGColor] {
        var output: [CGColor] = []
        NSAppearance.withAppAppearance {
            output = rendered ? gradient(baseColor: finalColor) : gradient(baseColor: startColor)
        }

        return output
    }
}
