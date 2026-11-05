//
//  UnifiedToggleInputListeningGlow.swift
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

import DesignResourcesKit
import UIKit

/// The light that circles the input card while speech is transcribed into it, matching Duck.ai on the web:
/// a 1pt comet on the card's edge above the card, and a blurred copy behind it that shows outside its edges.
/// It starts at the top centre, moves clockwise, and blends from blue to green to violet, one lap per blend.
final class UnifiedToggleInputListeningGlow {

    private enum Constants {
        static let lapsPerSecond = 0.2125
        static let fadePerSecond = 3.0
        /// The light's length along the edge; the comet in `BorderView` is the same length.
        static let tailLength: CGFloat = 400
        static let haloSegments = 60
        static let haloLineWidth: CGFloat = 16
        static let haloBlurRadius: CGFloat = 16
        static let haloOpacityLight: CGFloat = 0.78
        static let haloOpacityDark: CGFloat = 0.36
        static let reducedMotionHaloBlurRadius: CGFloat = 8
        static let reducedMotionHaloOpacity: Float = 0.55
        /// Caps one frame's step, so a stalled frame doesn't make the light jump.
        static let maxFrameInterval = 1.0 / 15
    }

    /// Sits behind the card; the card's fill hides all of the halo but what spills past its edges.
    private let haloView = HaloView()
    /// Sits above the card and its content.
    private let borderView = BorderView()

    private weak var cardView: UIView?
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var isActive = false
    private var isShowingReducedMotion = false
    /// Laps travelled; the fractional part is the head's position around the card.
    private var progress = 0.0
    private var opacity = 0.0
    private let isReduceMotionEnabled: () -> Bool

    init(isReduceMotionEnabled: @escaping () -> Bool = { UIAccessibility.isReduceMotionEnabled }) {
        self.isReduceMotionEnabled = isReduceMotionEnabled
        haloView.onLayout = { [weak self] in self?.renderReducedMotionIfShown() }
    }

    deinit {
        displayLink?.invalidate()
    }

    /// Places the halo just below `cardView` and the comet above everything already in its superview.
    func install(around cardView: UIView) {
        guard let container = cardView.superview else { return }
        self.cardView = cardView
        container.insertSubview(haloView, belowSubview: cardView)
        container.addSubview(borderView)
        for view in [haloView, borderView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
                view.topAnchor.constraint(equalTo: cardView.topAnchor),
                view.bottomAnchor.constraint(equalTo: cardView.bottomAnchor)
            ])
        }
    }

    /// Fades the light in and sets it moving, or freezes it where it is and fades it out.
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active

        if active && isReduceMotionEnabled() {
            isShowingReducedMotion = true
            renderReducedMotionIfShown()
            return
        }
        if isShowingReducedMotion {
            isShowingReducedMotion = false
            clear()
            return
        }

        if active {
            if opacity == 0 { progress = 0 }
            startDisplayLink()
        }
    }

    // MARK: - Animation

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        lastTimestamp = nil
        let link = CADisplayLink(target: DisplayLinkTarget(glow: self), selector: #selector(DisplayLinkTarget.tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    fileprivate func tick(_ link: CADisplayLink) {
        let now = link.targetTimestamp
        let interval = min(Constants.maxFrameInterval, max(0, now - (lastTimestamp ?? now)))
        lastTimestamp = now

        if isActive {
            opacity = min(1, opacity + interval * Constants.fadePerSecond)
            progress += interval * Constants.lapsPerSecond
        } else {
            opacity = max(0, opacity - interval * Constants.fadePerSecond)
        }

        guard isActive || opacity > 0 else {
            displayLink?.invalidate()
            displayLink = nil
            clear()
            return
        }
        renderComet()
    }

    private func renderComet() {
        guard let cardView else { return }
        let size = cardView.bounds.size
        let radius = Self.cornerRadius(of: cardView)
        let traits = borderView.traitCollection
        let head = CGFloat(progress.truncatingRemainder(dividingBy: 1))
        let blend = Self.colorBlend(at: progress)

        borderView.comet = BorderView.Comet(head: head,
                                            radius: radius,
                                            color: Self.color(blend, of: Self.borderColors, traits: traits),
                                            opacity: CGFloat(opacity))
        borderView.ring = nil

        let haloPath = UIBezierPath()
        let perimeter = Perimeter(size: size, radius: radius)
        let tail = Constants.tailLength / perimeter.length
        for step in 0...Constants.haloSegments {
            let point = perimeter.point(at: head - tail * (1 - CGFloat(step) / CGFloat(Constants.haloSegments)))
            if step == 0 {
                haloPath.move(to: point)
            } else {
                haloPath.addLine(to: point)
            }
        }
        let isDark = traits.userInterfaceStyle == .dark
        withoutImplicitAnimations {
            haloView.layer.shadowPath = haloPath.cgPath.copy(strokingWithWidth: Constants.haloLineWidth,
                                                             lineCap: .round, lineJoin: .round, miterLimit: 10)
            haloView.layer.shadowColor = Self.color(blend, of: Self.haloColors, traits: traits).cgColor
            haloView.layer.shadowRadius = Constants.haloBlurRadius
            haloView.layer.shadowOpacity = Float(opacity * (isDark ? Constants.haloOpacityDark : Constants.haloOpacityLight))
        }
    }

    private func renderReducedMotionIfShown() {
        guard isShowingReducedMotion, let cardView else { return }
        let radius = Self.cornerRadius(of: cardView)
        borderView.comet = nil
        borderView.ring = BorderView.Ring(radius: radius,
                                          color: UIColor(singleUseColor: .unifiedToggleInputListeningGlowReducedMotionRing))
        withoutImplicitAnimations {
            haloView.layer.shadowPath = UIBezierPath(roundedRect: cardView.bounds, cornerRadius: radius).cgPath
            haloView.layer.shadowColor = UIColor(singleUseColor: .unifiedToggleInputListeningGlowReducedMotionHalo).cgColor
            haloView.layer.shadowRadius = Constants.reducedMotionHaloBlurRadius
            haloView.layer.shadowOpacity = Constants.reducedMotionHaloOpacity
        }
    }

    private func clear() {
        borderView.comet = nil
        borderView.ring = nil
        withoutImplicitAnimations {
            haloView.layer.shadowOpacity = 0
            haloView.layer.shadowPath = nil
        }
    }

    private func withoutImplicitAnimations(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
    }

    // MARK: - Colors

    private static let borderColors: [SingleUseColor] = [.unifiedToggleInputListeningGlowBlue,
                                                         .unifiedToggleInputListeningGlowGreen,
                                                         .unifiedToggleInputListeningGlowViolet]
    private static let haloColors: [SingleUseColor] = [.unifiedToggleInputListeningGlowBlue,
                                                       .unifiedToggleInputListeningGlowHaloGreen,
                                                       .unifiedToggleInputListeningGlowViolet]

    /// Which two colors the light is between, and how far, after `progress` laps.
    private static func colorBlend(at progress: Double) -> (from: Int, to: Int, fraction: CGFloat) {
        let phase = progress.truncatingRemainder(dividingBy: 3)
        let from = Int(phase) % 3
        return (from, (from + 1) % 3, CGFloat(phase - Double(Int(phase))))
    }

    private static func color(_ blend: (from: Int, to: Int, fraction: CGFloat),
                              of colors: [SingleUseColor],
                              traits: UITraitCollection) -> UIColor {
        var start: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) = (0, 0, 0, 0)
        var end: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) = (0, 0, 0, 0)
        UIColor(singleUseColor: colors[blend.from]).resolvedColor(with: traits).getRed(&start.r, green: &start.g, blue: &start.b, alpha: &start.a)
        UIColor(singleUseColor: colors[blend.to]).resolvedColor(with: traits).getRed(&end.r, green: &end.g, blue: &end.b, alpha: &end.a)
        let t = blend.fraction
        return UIColor(red: start.r + (end.r - start.r) * t,
                       green: start.g + (end.g - start.g) * t,
                       blue: start.b + (end.b - start.b) * t,
                       alpha: 1)
    }

    private static func cornerRadius(of cardView: UIView) -> CGFloat {
        min(cardView.layer.cornerRadius, cardView.bounds.width / 2, cardView.bounds.height / 2)
    }
}

// MARK: - Perimeter

/// A rounded rectangle's outline measured by distance, so the light moves at the same speed along edges and corners.
private struct Perimeter {
    let size: CGSize
    let radius: CGFloat
    var origin: CGPoint = .zero

    private var straightWidth: CGFloat { size.width - 2 * radius }
    private var straightHeight: CGFloat { size.height - 2 * radius }
    private var cornerLength: CGFloat { .pi * radius / 2 }

    var length: CGFloat { 2 * straightWidth + 2 * straightHeight + 4 * cornerLength }

    /// The point `fraction` of the way around, starting at the top centre and moving clockwise; wraps outside 0..<1.
    func point(at fraction: CGFloat) -> CGPoint {
        let local = localPoint(at: fraction)
        return CGPoint(x: origin.x + local.x, y: origin.y + local.y)
    }

    private func localPoint(at fraction: CGFloat) -> CGPoint {
        let w = size.width, h = size.height, r = radius
        var d = (fraction.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * length

        if d < straightWidth / 2 { return CGPoint(x: w / 2 + d, y: 0) }
        d -= straightWidth / 2
        if d < cornerLength { let a = d / r; return CGPoint(x: w - r + r * sin(a), y: r - r * cos(a)) }
        d -= cornerLength
        if d < straightHeight { return CGPoint(x: w, y: r + d) }
        d -= straightHeight
        if d < cornerLength { let a = d / r; return CGPoint(x: w - r + r * cos(a), y: h - r + r * sin(a)) }
        d -= cornerLength
        if d < straightWidth { return CGPoint(x: w - r - d, y: h) }
        d -= straightWidth
        if d < cornerLength { let a = d / r; return CGPoint(x: r - r * sin(a), y: h - r + r * cos(a)) }
        d -= cornerLength
        if d < straightHeight { return CGPoint(x: 0, y: h - r - d) }
        d -= straightHeight
        if d < cornerLength { let a = d / r; return CGPoint(x: r - r * cos(a), y: r - r * sin(a)) }
        d -= cornerLength
        return CGPoint(x: r + d, y: 0)
    }
}

// MARK: - Views

/// Draws nothing itself: the halo is its layer's shadow, cast from a path, which the GPU blurs.
private final class HaloView: UIView {

    var onLayout: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        layer.shadowOffset = .zero
        layer.shadowOpacity = 0
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

private final class BorderView: UIView {

    struct Comet {
        let head: CGFloat
        let radius: CGFloat
        let color: UIColor
        let opacity: CGFloat
    }

    struct Ring {
        let radius: CGFloat
        let color: UIColor
    }

    private enum Constants {
        static let lineWidth: CGFloat = 1
        static let segments = 120
        static let taper: CGFloat = 0.15
        static let tailLength: CGFloat = 400
    }

    var comet: Comet? { didSet { setNeedsDisplay() } }
    var ring: Ring? { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
        isUserInteractionEnabled = false
        isAccessibilityElement = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        // Centred on the card's own 1pt edge.
        let inset = Constants.lineWidth / 2
        let edge = bounds.insetBy(dx: inset, dy: inset)
        context.setLineWidth(Constants.lineWidth)

        if let ring {
            context.setStrokeColor(ring.color.cgColor)
            context.addPath(UIBezierPath(roundedRect: edge, cornerRadius: max(0, ring.radius - inset)).cgPath)
            context.strokePath()
        }

        guard let comet, comet.opacity > 0 else { return }
        let perimeter = Perimeter(size: edge.size, radius: max(0, comet.radius - inset), origin: edge.origin)
        let tail = Constants.tailLength / perimeter.length
        context.setLineCap(.butt)
        for step in 0..<Constants.segments {
            let fraction = CGFloat(step) / CGFloat(Constants.segments)
            let start = perimeter.point(at: comet.head - tail * (1 - fraction))
            let end = perimeter.point(at: comet.head - tail * (1 - CGFloat(step + 1) / CGFloat(Constants.segments)))
            // Both ends taper, so it reads as a band of light rather than a head with a trail.
            let alpha = fraction < Constants.taper ? fraction / Constants.taper
                : fraction > 1 - Constants.taper ? (1 - fraction) / Constants.taper
                : 1
            context.setStrokeColor(comet.color.withAlphaComponent(alpha * comet.opacity).cgColor)
            context.move(to: start)
            context.addLine(to: end)
            context.strokePath()
        }
    }
}

/// Holds the glow weakly, so the display link doesn't keep it alive.
private final class DisplayLinkTarget: NSObject {

    private weak var glow: UnifiedToggleInputListeningGlow?

    init(glow: UnifiedToggleInputListeningGlow) {
        self.glow = glow
    }

    @objc func tick(_ link: CADisplayLink) {
        guard let glow else {
            link.invalidate()
            return
        }
        glow.tick(link)
    }
}
