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

/// Draws the active iPad tab background: rounded top corners plus concave "ramp" fillets at the
/// bottom that flare outward so the tab merges into the toolbar below (the classic browser-tab
/// silhouette). Mirrors the macOS tab shape (`TabBackgroundShapeView`) but authored in UIKit
/// coordinates (y increases downward).
///
/// The tab body occupies the view's bounds inset horizontally by `rampSize.width` on each side; the
/// ramps flare out to the bounds' edges, so the caller sizes this view `2 * rampSize.width` wider
/// than the tab itself and centers it over the tab.
final class TabFlaredBackgroundView: UIView {

    var topCornerRadius: CGFloat = 12 {
        didSet { setNeedsLayout() }
    }

    /// Width/height of the outward concave fillet at the bottom of each side. Width is how far the
    /// foot spreads past the tab body; height is how far up the side the fillet reaches.
    var rampSize: CGSize = CGSize(width: 10, height: 10) {
        didSet { setNeedsLayout() }
    }

    var fillColor: UIColor = .clear {
        didSet { shapeLayer.fillColor = fillColor.cgColor }
    }

    private var shapeLayer: CAShapeLayer {
        // swiftlint:disable:next force_cast
        layer as! CAShapeLayer
    }

    override class var layerClass: AnyClass { CAShapeLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        shapeLayer.fillColor = fillColor.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        shapeLayer.path = Self.path(in: bounds, topCornerRadius: topCornerRadius, rampSize: rampSize)
    }

    /// Bézier control-point ratio for approximating a quarter circle with a cubic curve.
    private static let quarterCircleControl: CGFloat = 0.5522847498307936

    /// Builds the flared-tab outline. `rect` is the full drawing rect (tab body plus both ramps).
    ///
    /// The two bottom fillets are drawn as cubic Béziers rather than `addArc(center:…clockwise:)`
    /// because that arc's winding is evaluated in the path's (y-up) space while a `CAShapeLayer`
    /// renders y-down, which flips a concave fillet into a convex bump. The cubic control points are
    /// unambiguous in either space and mirror the Figma curve exactly.
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

        // Bottom edge, widened by the ramps: left foot -> right foot.
        path.move(to: CGPoint(x: rect.minX, y: bottom))
        path.addLine(to: CGPoint(x: rect.maxX, y: bottom))

        // Trailing (right) ramp: concave quarter-fillet from the right foot up-and-in to the body wall.
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

        // Leading (left) ramp: concave quarter-fillet from the body wall down-and-out to the left foot.
        path.addCurve(to: CGPoint(x: rect.minX, y: bottom),
                      control1: CGPoint(x: bodyLeft, y: bottom - rampHeight * (1 - control)),
                      control2: CGPoint(x: rect.minX + rampWidth * control, y: bottom))

        path.closeSubpath()
        return path
    }
}
