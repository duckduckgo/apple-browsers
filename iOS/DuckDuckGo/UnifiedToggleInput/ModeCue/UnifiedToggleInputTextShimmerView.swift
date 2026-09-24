//
//  UnifiedToggleInputTextShimmerView.swift
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

/// A text control the shimmer can paint over.
protocol UnifiedToggleInputTextShimmerSource: UIView {
    /// Where the typed text sits, in the source's own bounds. The band travels across this span.
    var shimmerTextFrame: CGRect { get }
}

/// Loops a band of the mode's colours across the typed text, left to right.
///
/// The text is never restyled: the band is a gradient masked to a snapshot of the source's glyphs,
/// so editing, selection, marked text and autocorrect behave exactly as without it.
final class UnifiedToggleInputTextShimmerView: UIView {

    private enum Metrics {
        /// Band width as a fraction of the text span.
        static let bandWidthFraction: CGFloat = 0.75
        static let travelDuration: CFTimeInterval = 1.5
        static let loopDuration: CFTimeInterval = 2.0
        static let reduceMotionOpacity: Float = 0.55
        static let travelAnimationKey = "textShimmerTravel"
    }

    private let bandLayer = CAGradientLayer()
    private let glyphMask = CALayer()
    private let isReduceMotionEnabled: () -> Bool
    private var mode: TextEntryMode = .search

    init(isReduceMotionEnabled: @escaping () -> Bool = { UIAccessibility.isReduceMotionEnabled }) {
        self.isReduceMotionEnabled = isReduceMotionEnabled
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        isHidden = true
        layer.addSublayer(bandLayer)
        layer.mask = glyphMask
        applyColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setMode(_ mode: TextEntryMode) {
        guard mode != self.mode else { return }
        self.mode = mode
        applyColors()
    }

    /// Re-masks the band to what the source currently draws. Call whenever its text, layout or scroll
    /// position changes.
    func show(over source: UnifiedToggleInputTextShimmerSource) {
        source.layoutIfNeeded()
        isHidden = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glyphMask.frame = convert(source.bounds, from: source)
        glyphMask.contents = renderGlyphs(of: source)
        bandLayer.frame = convert(source.shimmerTextFrame, from: source)
        CATransaction.commit()
        applyMotion()
    }

    func hide() {
        isHidden = true
        glyphMask.contents = nil
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyColors()
    }

    // MARK: - Rendering

    private func renderGlyphs(of source: UIView) -> CGImage? {
        let format = UIGraphicsImageRendererFormat(for: traitCollection)
        format.opaque = false
        return UIGraphicsImageRenderer(bounds: source.bounds, format: format).image { context in
            source.layer.render(in: context.cgContext)
        }.cgImage
    }

    private func applyColors() {
        let gradient = isReduceMotionEnabled()
            ? UnifiedToggleInputModeCuePalette.modeColors(for: mode, resolvedWith: traitCollection)
            : UnifiedToggleInputModeCuePalette.textShimmerBand(for: mode, resolvedWith: traitCollection)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bandLayer.colors = gradient.colors.map(\.cgColor)
        bandLayer.locations = gradient.locations
        CATransaction.commit()
    }

    // MARK: - Motion

    private func applyMotion() {
        if isReduceMotionEnabled() {
            showStaticWash()
        } else {
            startTravelIfNeeded()
        }
    }

    /// Reduce Motion: the whole text carries the mode's colours, without anything moving.
    private func showStaticWash() {
        bandLayer.removeAnimation(forKey: Metrics.travelAnimationKey)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bandLayer.opacity = Metrics.reduceMotionOpacity
        bandLayer.startPoint = CGPoint(x: 0, y: 0.5)
        bandLayer.endPoint = CGPoint(x: 1, y: 0.5)
        CATransaction.commit()
    }

    /// The band travels in the layer's unit space, so resizing the span as the user types doesn't
    /// restart the loop — it just stretches the path.
    private func startTravelIfNeeded() {
        guard bandLayer.animation(forKey: Metrics.travelAnimationKey) == nil else { return }
        let width = Metrics.bandWidthFraction
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bandLayer.opacity = 1
        // Resting pose between laps: parked past the trailing edge, so nothing shows.
        bandLayer.startPoint = CGPoint(x: 1, y: 0.5)
        bandLayer.endPoint = CGPoint(x: 1 + width, y: 0.5)
        CATransaction.commit()

        let start = CABasicAnimation(keyPath: "startPoint")
        start.fromValue = CGPoint(x: -width, y: 0.5)
        start.toValue = CGPoint(x: 1, y: 0.5)
        let end = CABasicAnimation(keyPath: "endPoint")
        end.fromValue = CGPoint(x: 0, y: 0.5)
        end.toValue = CGPoint(x: 1 + width, y: 0.5)
        for travel in [start, end] {
            travel.duration = Metrics.travelDuration
            travel.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        }

        let loop = CAAnimationGroup()
        loop.animations = [start, end]
        loop.duration = Metrics.loopDuration
        loop.repeatCount = .infinity
        // Survives the app going to the background.
        loop.isRemovedOnCompletion = false
        bandLayer.add(loop, forKey: Metrics.travelAnimationKey)
    }
}
