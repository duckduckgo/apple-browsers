//
//  TabFlaredBackgroundView.swift
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

/// Draws the active iPad tab background: rounded top corners and concave bottom fillets that flare
/// outward so the tab merges into the toolbar below. Mirrors the macOS tab shape in UIKit coordinates.
///
/// The tab body is the bounds inset by `rampSize.width` on each side; the ramps flare to the edges, so
/// the caller sizes this view `2 * rampSize.width` wider than the tab and centers it over it.
final class TabFlaredBackgroundView: UIView {

    var topCornerRadius: CGFloat = 12 {
        didSet { setNeedsLayout() }
    }

    /// Bottom-side concave fillet: width spreads past the tab body, height reaches up the side.
    var rampSize: CGSize = CGSize(width: 10, height: 10) {
        didSet { setNeedsLayout() }
    }

    var fillColor: UIColor = .clear {
        didSet { applyFillColor() }
    }

    private var shapeLayer: CAShapeLayer {
        // swiftlint:disable:next force_cast
        layer as! CAShapeLayer
    }

    override class var layerClass: AnyClass { CAShapeLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        applyFillColor()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        shapeLayer.path = Self.path(in: bounds, topCornerRadius: topCornerRadius, rampSize: rampSize)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            applyFillColor()
        }
    }

    private func applyFillColor() {
        shapeLayer.fillColor = fillColor.resolvedColor(with: traitCollection).cgColor
    }

    /// Kappa: the cubic control-point offset (as a fraction of radius) that best approximates a
    /// quarter circle. kappa = 4/3 · (√2 − 1) ≈ 0.5523.
    private static let quarterCircleControl: CGFloat = 0.5522847498307936

    /// Builds the flared-tab outline (`rect` is the tab body plus both ramps). The bottom fillets are
    /// cubic Béziers matching the Figma export (`C14.4772 23 10 18.5228 10 13`), whose control points
    /// are the kappa offsets below.
    ///
    /// They are cubics, not `addArc(center:…clockwise:)`: that arc's winding is evaluated y-up while
    /// `CAShapeLayer` renders y-down, which flips the concave fillet into a bump.
    static func path(in rect: CGRect, topCornerRadius: CGFloat, rampSize: CGSize) -> CGPath {
        let path = CGMutablePath()
        guard rect.width > 0, rect.height > 0 else { return path }

        let rampWidth = max(0, min(rampSize.width, rect.width / 2))
        let rampHeight = max(0, min(rampSize.height, rect.height))
        let corner = max(0, min(topCornerRadius, (rect.width - 2 * rampWidth) / 2, rect.height - rampHeight))
        let control = Self.quarterCircleControl

        let bodyLeft = rect.minX + rampWidth
        let bodyRight = rect.maxX - rampWidth
        let top = rect.minY
        let bottom = rect.maxY

        // Bottom edge, foot to foot.
        path.move(to: CGPoint(x: rect.minX, y: bottom))
        path.addLine(to: CGPoint(x: rect.maxX, y: bottom))

        // Right ramp fillet.
        path.addCurve(to: CGPoint(x: bodyRight, y: bottom - rampHeight),
                      control1: CGPoint(x: rect.maxX - rampWidth * control, y: bottom),
                      control2: CGPoint(x: bodyRight, y: bottom - rampHeight * (1 - control)))

        path.addLine(to: CGPoint(x: bodyRight, y: top + corner))
        path.addArc(tangent1End: CGPoint(x: bodyRight, y: top),
                    tangent2End: CGPoint(x: bodyRight - corner, y: top),
                    radius: corner)

        path.addLine(to: CGPoint(x: bodyLeft + corner, y: top))
        path.addArc(tangent1End: CGPoint(x: bodyLeft, y: top),
                    tangent2End: CGPoint(x: bodyLeft, y: top + corner),
                    radius: corner)

        path.addLine(to: CGPoint(x: bodyLeft, y: bottom - rampHeight))

        // Left ramp fillet.
        path.addCurve(to: CGPoint(x: rect.minX, y: bottom),
                      control1: CGPoint(x: bodyLeft, y: bottom - rampHeight * (1 - control)),
                      control2: CGPoint(x: rect.minX + rampWidth * control, y: bottom))

        path.closeSubpath()
        return path
    }
}
