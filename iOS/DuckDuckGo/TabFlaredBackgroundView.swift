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

    enum Shape {
        /// The browser-tab silhouette, whose feet flare into the bar below.
        case flared
        /// Detached pill for when there's no bar below to merge into.
        case roundedRectangle
    }

    /// 0 = flared (feet spread into the bar below), 1 = detached rounded rectangle. Intermediate
    /// values are the morph between them; every stage is the same path structure, which is what lets
    /// Core Animation interpolate it.
    private(set) var detachmentProgress: CGFloat = 0

    var shape: Shape {
        get { detachmentProgress < 0.5 ? .flared : .roundedRectangle }
        set { setShape(newValue, animated: false) }
    }

    /// Duration matching the chrome show/hide so the tab reshapes alongside the address bar.
    static let shapeChangeDuration: TimeInterval = 0.25

    func setShape(_ shape: Shape, animated: Bool, duration: TimeInterval = TabFlaredBackgroundView.shapeChangeDuration) {
        let progress: CGFloat = shape == .flared ? 0 : 1
        guard progress != detachmentProgress else { return }

        let previousPath = shapeLayer.presentation()?.path ?? shapeLayer.path
        detachmentProgress = progress
        shapeLayer.path = currentPath()

        guard animated, let previousPath else {
            shapeLayer.removeAnimation(forKey: "path")
            return
        }

        let animation = CABasicAnimation(keyPath: "path")
        animation.fromValue = previousPath
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        shapeLayer.add(animation, forKey: "path")
    }

    var topCornerRadius: CGFloat = 12 {
        didSet { setNeedsLayout() }
    }

    /// Only used by `.roundedRectangle`; the flared shape ends in fillets instead of corners.
    var bottomCornerRadius: CGFloat = 12 {
        didSet { setNeedsLayout() }
    }

    /// Lifts `.roundedRectangle` off the strip so it reads as detached rather than as a tab whose
    /// feet have been cut off. Applied equally top and bottom to keep the shape centred on the cell,
    /// which centres its label on the full cell height. Ignored by `.flared`, which has to reach the
    /// bar below.
    var detachedVerticalInset: CGFloat = 4 {
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
        shapeLayer.path = currentPath()
    }

    private func currentPath() -> CGPath {
        Self.path(in: bounds,
                  topCornerRadius: topCornerRadius,
                  bottomCornerRadius: bottomCornerRadius,
                  rampSize: rampSize,
                  detachedVerticalInset: detachedVerticalInset,
                  detachmentProgress: detachmentProgress)
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

    /// Builds the tab outline (`rect` is the tab body plus both ramps).
    ///
    /// `detachmentProgress` morphs between the two silhouettes: at 0 the bottom corners are the
    /// concave fillets of the Figma export (`C14.4772 23 10 18.5228 10 13`), feet spread to `rect`'s
    /// edges to meet the bar below; at 1 they are convex corners tucked back to the body walls, inset
    /// by `detachedVerticalInset`. Both ends emit the identical sequence of segments, so Core
    /// Animation can interpolate between them.
    ///
    /// The bottom corners are cubic Béziers, not `addArc(center:…clockwise:)`: that arc's winding is
    /// evaluated y-up while `CAShapeLayer` renders y-down, which flips the concave fillet into a
    /// bump. Their control points are the kappa offsets below, which is also what lets one formula
    /// cover both corner directions.
    static func path(in rect: CGRect,
                     topCornerRadius: CGFloat,
                     bottomCornerRadius: CGFloat,
                     rampSize: CGSize,
                     detachedVerticalInset: CGFloat,
                     detachmentProgress: CGFloat) -> CGPath {
        let path = CGMutablePath()
        guard rect.width > 0, rect.height > 0 else { return path }

        let progress = min(max(detachmentProgress, 0), 1)
        let control = Self.quarterCircleControl

        // The body is always inset by the full ramp width; only the feet retract as we detach.
        let bodyInset = max(0, min(rampSize.width, rect.width / 2))
        let bodyLeft = rect.minX + bodyInset
        let bodyRight = rect.maxX - bodyInset
        let verticalInset = detachedVerticalInset * progress
        let top = rect.minY + verticalInset
        let bottom = rect.maxY - verticalInset

        let footSpread = bodyInset * (1 - progress)
        let bottomCorner = max(0, min(bottomCornerRadius, (bodyRight - bodyLeft) / 2)) * progress
        // Vertical reach of the bottom corner: the ramp's height when flared, the corner radius when not.
        let cornerHeight = max(0, min(rampSize.height, rect.height)) * (1 - progress) + bottomCorner
        // Where the bottom edge meets the corner: outside the body wall when flared, inside it when not.
        let leftFoot = bodyLeft - footSpread + bottomCorner
        let rightFoot = bodyRight + footSpread - bottomCorner
        // Flips the control points as the corner turns from concave to convex.
        let controlSpread = control * (footSpread - bottomCorner)

        let corner = max(0, min(topCornerRadius, (bodyRight - bodyLeft) / 2, bottom - top - cornerHeight))

        path.move(to: CGPoint(x: leftFoot, y: bottom))
        path.addLine(to: CGPoint(x: rightFoot, y: bottom))

        // Trailing (right) bottom corner, up and in to the body wall.
        path.addCurve(to: CGPoint(x: bodyRight, y: bottom - cornerHeight),
                      control1: CGPoint(x: rightFoot - controlSpread, y: bottom),
                      control2: CGPoint(x: bodyRight, y: bottom - cornerHeight * (1 - control)))

        path.addLine(to: CGPoint(x: bodyRight, y: top + corner))
        path.addArc(tangent1End: CGPoint(x: bodyRight, y: top),
                    tangent2End: CGPoint(x: bodyRight - corner, y: top),
                    radius: corner)

        path.addLine(to: CGPoint(x: bodyLeft + corner, y: top))
        path.addArc(tangent1End: CGPoint(x: bodyLeft, y: top),
                    tangent2End: CGPoint(x: bodyLeft, y: top + corner),
                    radius: corner)

        path.addLine(to: CGPoint(x: bodyLeft, y: bottom - cornerHeight))

        // Leading (left) bottom corner, down and out to the foot.
        path.addCurve(to: CGPoint(x: leftFoot, y: bottom),
                      control1: CGPoint(x: bodyLeft, y: bottom - cornerHeight * (1 - control)),
                      control2: CGPoint(x: leftFoot + controlSpread, y: bottom))

        path.closeSubpath()
        return path
    }
}
