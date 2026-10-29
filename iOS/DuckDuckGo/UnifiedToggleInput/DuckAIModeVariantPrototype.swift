//
//  DuckAIModeVariantPrototype.swift
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

import Combine
import UIKit
import DesignResourcesKit
import os.log

// PROTOTYPE: throwaway visuals for "make it more obvious when a user is on Duck.ai" (Round 2).
// Long-press the Search/Duck.ai toggle to cycle Control → B/C → E.
enum DuckAIModeVisualVariant: String, CaseIterable {
    case control
    case inputKeyboard
    case inputKeyboardSweep

    static let didChangeNotification = Notification.Name("DuckAIModeVisualVariant.didChange")
    private static let storageKey = "prototype.duckAIModeVisualVariant.round2"

    static var current: DuckAIModeVisualVariant {
        get { UserDefaults.standard.string(forKey: storageKey).flatMap(Self.init(rawValue:)) ?? .control }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    static func cycle() -> DuckAIModeVisualVariant {
        let all = allCases
        let next = all[(all.firstIndex(of: current)! + 1) % all.count]
        current = next
        return next
    }

    var title: String {
        switch self {
        case .control: return "Control"
        case .inputKeyboard: return "B/C · Input + Keyboard"
        case .inputKeyboardSweep: return "E · Input + Keyboard Sweep"
        }
    }

    var tintsDuckAITab: Bool { self != .control }

    // t-accent-alt/text-secondary (LatestColorPalette.accentAltTextSecondary); iOS's DesignSystemColor doesn't expose it.
    static let duckAITabTint = UIColor(light: 0x034180, dark: 0xE6F6FF)
}

extension UIColor {
    convenience init(prototypeHex hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }

    /// The Figma file is light-only; the dark values are a prototype guess.
    convenience init(light: UInt32, dark: UInt32) {
        self.init { traits in
            UIColor(prototypeHex: traits.userInterfaceStyle == .dark ? dark : light)
        }
    }
}

// MARK: - Shared clock

/// One clock for the input card and the keyboard, so E's laps stay in step across the two views.
final class DuckAIModeVisualsDriver {

    enum Surface {
        case card
        case keyboard
    }

    struct Lap {
        let surfaces: Set<Surface>
        let duration: CFTimeInterval
    }

    static let shared = DuckAIModeVisualsDriver()

    static let sweepDuration: CFTimeInterval = 2.2
    private static let rest: TimeInterval = 3
    /// B/C: after two loops the card stroke settles to a fainter, shorter streak.
    private static let settleAfterLoops = 2

    let laps = PassthroughSubject<Lap, Never>()
    @Published private(set) var activeVariant: DuckAIModeVisualVariant?
    @Published private(set) var isSettled = false

    private var generation = 0
    /// Swipe-tab previews build their own input views; only an active one may switch the visuals on.
    private var activeOwners = Set<ObjectIdentifier>()

    func setActive(_ active: Bool, owner: AnyObject) {
        if active {
            activeOwners.insert(ObjectIdentifier(owner))
        } else {
            activeOwners.remove(ObjectIdentifier(owner))
        }
        let isActive = !activeOwners.isEmpty
        let variant = isActive && DuckAIModeVisualVariant.current != .control ? DuckAIModeVisualVariant.current : nil
        guard variant != activeVariant else { return }
        generation += 1
        let current = generation
        isSettled = false
        activeVariant = variant

        switch variant {
        case .inputKeyboard:
            loopCard(generation: current)
            after(Double(Self.settleAfterLoops) * (Self.sweepDuration + Self.rest), generation: current) { [weak self] in
                self?.isSettled = true
            }
        case .inputKeyboardSweep:
            // First play runs on both together, then single laps alternate. Laps use B/C's sweep
            // duration, not the Figma half speed, so both variants share one timing.
            laps.send(Lap(surfaces: [.card, .keyboard], duration: Self.sweepDuration))
            after(Self.sweepDuration + Self.rest, generation: current) { [weak self] in
                self?.alternate(onCard: true, generation: current)
            }
        case .control, nil:
            break
        }
    }

    private func loopCard(generation: Int) {
        laps.send(Lap(surfaces: [.card], duration: Self.sweepDuration))
        after(Self.sweepDuration + Self.rest, generation: generation) { [weak self] in
            self?.loopCard(generation: generation)
        }
    }

    private func alternate(onCard: Bool, generation: Int) {
        laps.send(Lap(surfaces: [onCard ? .card : .keyboard], duration: Self.sweepDuration))
        after(Self.sweepDuration + Self.rest, generation: generation) { [weak self] in
            self?.alternate(onCard: !onCard, generation: generation)
        }
    }

    private func after(_ delay: TimeInterval, generation: Int, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard self?.generation == generation else { return }
            work()
        }
    }
}

// MARK: - Edge sweep (B on the card, E on the keyboard)

/// A gradient stroke that sweeps once around a rounded rect from its top-right corner.
final class DuckAIEdgeSweepView: UIView {

    private enum Constants {
        static let tail = UIColor(prototypeHex: 0xCDEAFB)
        static let body = UIColor(prototypeHex: 0xA9D8F9)
        static let mid = UIColor(prototypeHex: 0x9FD6B6)
        static let lead = UIColor(prototypeHex: 0xC7B1F5)
        static let leadStartWidth: CGFloat = 3
        static let trailWidth: CGFloat = 1
        /// The arc's lead sits ~355° into the gradient and the card's top-right corner is ~66°
        /// clockwise from the top, so a run starts at -289° and makes one full turn.
        static let startAngle: CGFloat = -289 * .pi / 180
        static let endAngle: CGFloat = 71 * .pi / 180
        static let easing = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        static let restingTail: CGFloat = 140
        static let settledTail: CGFloat = 250
        static let settledStrength: Float = 0.45
        static let settleDuration: CFTimeInterval = 1.6
        /// Where each trail colour sits between the tail start and 360°.
        static let trailStops: [CGFloat] = [0.227, 0.455, 0.659, 0.841, 0.955]
    }

    /// Fades the stroke out below the top edge, so only the top edge and upper corners light up.
    struct TopFade {
        let opaqueHeight: CGFloat
        let clearHeight: CGFloat
    }

    var cornerRadius: CGFloat = 28 { didSet { setNeedsLayout() } }
    var maskedCorners: CACornerMask = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner] {
        didSet { setNeedsLayout() }
    }

    private let surface: DuckAIModeVisualsDriver.Surface
    private let topFade: TopFade?
    private let strengthLayer = CALayer()
    private let fadeMask = CAGradientLayer()
    private let trailHost = CALayer()
    private let trailMask = CAShapeLayer()
    private let trailGradient = CAGradientLayer()
    private let leadHost = CALayer()
    private let leadMask = CAShapeLayer()
    private let leadGradient = CAGradientLayer()
    private var cancellables = Set<AnyCancellable>()

    init(surface: DuckAIModeVisualsDriver.Surface, topFade: TopFade? = nil) {
        self.surface = surface
        self.topFade = topFade
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        clipsToBounds = false

        func stop(_ degrees: CGFloat) -> NSNumber { NSNumber(value: Double(degrees / 360)) }
        let clear = UIColor.clear.cgColor

        trailGradient.colors = [clear, clear, Constants.tail.cgColor, Constants.body.cgColor, Constants.mid.cgColor,
                                Constants.lead.cgColor, Constants.body.cgColor, clear]
        trailGradient.locations = trailLocations(tail: Constants.restingTail)
        leadGradient.colors = [clear, clear, Constants.mid.withAlphaComponent(0.35).cgColor,
                               Constants.lead.withAlphaComponent(0.8).cgColor, Constants.body.cgColor, clear]
        leadGradient.locations = [0, stop(255), stop(285), stop(325), stop(352), 1]

        layer.addSublayer(strengthLayer)
        if topFade != nil {
            fadeMask.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
            strengthLayer.mask = fadeMask
        }
        for (host, mask, gradient) in [(trailHost, trailMask, trailGradient), (leadHost, leadMask, leadGradient)] {
            gradient.type = .conic
            gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
            gradient.endPoint = CGPoint(x: 0.5, y: 0)
            mask.fillColor = nil
            mask.strokeColor = UIColor.black.cgColor
            mask.lineWidth = Constants.trailWidth
            host.mask = mask
            host.opacity = 0
            host.addSublayer(gradient)
            strengthLayer.addSublayer(host)
        }

        let driver = DuckAIModeVisualsDriver.shared
        driver.laps
            .filter { [surface] in $0.surfaces.contains(surface) }
            .sink { [weak self] lap in self?.play(duration: lap.duration) }
            .store(in: &cancellables)
        driver.$activeVariant
            .filter { $0 == nil }
            .sink { [weak self] _ in self?.stop() }
            .store(in: &cancellables)
        if surface == .card {
            driver.$isSettled
                .removeDuplicates()
                .sink { [weak self] settled in self?.setSettled(settled) }
                .store(in: &cancellables)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let side = hypot(bounds.width, bounds.height) + 16
        strengthLayer.frame = bounds
        for host in [trailHost, leadHost] {
            host.frame = bounds
            host.mask?.frame = bounds
        }
        for gradient in [trailGradient, leadGradient] {
            gradient.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            gradient.position = CGPoint(x: bounds.midX, y: bounds.midY)
        }
        trailMask.path = ringPath(width: Constants.trailWidth)
        leadMask.path = ringPath(width: Constants.trailWidth)
        if let topFade {
            // Starts above the bounds so the ring drawn outside the top edge stays inside the mask.
            let overhang = Constants.leadStartWidth * 2
            let height = topFade.clearHeight + overhang
            fadeMask.frame = CGRect(x: -overhang, y: -overhang, width: bounds.width + overhang * 2, height: height)
            fadeMask.locations = [0, NSNumber(value: Double((topFade.opaqueHeight + overhang) / height)), 1]
        }
        CATransaction.commit()
    }

    private func trailLocations(tail: CGFloat) -> [NSNumber] {
        let stops = Constants.trailStops.map { tail + (360 - tail) * $0 }
        return ([0, tail] + stops + [360]).map { NSNumber(value: Double($0 / 360)) }
    }

    /// A ring of `width` drawn just outside the edge, like a CSS border at `inset: -width`.
    private func ringPath(width: CGFloat) -> CGPath {
        let offset = width / 2
        var corners = UIRectCorner()
        if maskedCorners.contains(.layerMinXMinYCorner) { corners.insert(.topLeft) }
        if maskedCorners.contains(.layerMaxXMinYCorner) { corners.insert(.topRight) }
        if maskedCorners.contains(.layerMinXMaxYCorner) { corners.insert(.bottomLeft) }
        if maskedCorners.contains(.layerMaxXMaxYCorner) { corners.insert(.bottomRight) }
        let radius = cornerRadius + offset
        return UIBezierPath(roundedRect: bounds.insetBy(dx: -offset, dy: -offset),
                            byRoundingCorners: corners,
                            cornerRadii: CGSize(width: radius, height: radius)).cgPath
    }

    /// The gradient's current start angle (degrees, clockwise from the top) and how visible the
    /// stroke is, read from the running animation so anything following it stays in step.
    var liveSweep: (angle: CGFloat, visibility: CGFloat)? {
        guard trailGradient.animation(forKey: "sweep") != nil,
              let gradient = trailGradient.presentation(),
              let host = trailHost.presentation() else { return nil }
        let transform = gradient.transform
        return (atan2(transform.m12, transform.m11) * 180 / .pi, CGFloat(host.opacity))
    }

    private func stop() {
        [trailHost, leadHost, trailGradient, leadGradient, leadMask].forEach { $0.removeAllAnimations() }
    }

    private func setSettled(_ settled: Bool) {
        let tail = settled ? Constants.settledTail : Constants.restingTail
        let strength: Float = settled ? Constants.settledStrength : 1
        let locations = CABasicAnimation(keyPath: "locations")
        locations.fromValue = trailGradient.locations
        locations.toValue = trailLocations(tail: tail)
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = strengthLayer.opacity
        opacity.toValue = strength
        for animation in [locations, opacity] {
            animation.duration = settled ? Constants.settleDuration : 0
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        }
        trailGradient.locations = trailLocations(tail: tail)
        strengthLayer.opacity = strength
        trailGradient.add(locations, forKey: "settle")
        strengthLayer.add(opacity, forKey: "settle")
    }

    private func play(duration: CFTimeInterval) {
        layoutIfNeeded()

        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = Constants.startAngle
        rotation.toValue = Constants.endAngle
        rotation.duration = duration
        rotation.timingFunction = Constants.easing
        rotation.fillMode = .forwards
        rotation.isRemovedOnCompletion = false

        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 1, 1, 0]
        opacity.keyTimes = [0, 0.05, 0.7, 1]
        opacity.duration = duration

        // The lead starts wide and narrows to the trail width by 75% of the run, on a linear clock.
        let taperPath = CAKeyframeAnimation(keyPath: "path")
        taperPath.values = [ringPath(width: Constants.leadStartWidth), ringPath(width: Constants.trailWidth), ringPath(width: Constants.trailWidth)]
        taperPath.keyTimes = [0, 0.75, 1]
        taperPath.duration = duration
        let taperWidth = CAKeyframeAnimation(keyPath: "lineWidth")
        taperWidth.values = [Constants.leadStartWidth, Constants.trailWidth, Constants.trailWidth]
        taperWidth.keyTimes = [0, 0.75, 1]
        taperWidth.duration = duration

        trailGradient.add(rotation, forKey: "sweep")
        leadGradient.add(rotation, forKey: "sweep")
        trailHost.add(opacity, forKey: "sweep")
        leadHost.add(opacity, forKey: "sweep")
        leadMask.add(taperPath, forKey: "taperPath")
        leadMask.add(taperWidth, forKey: "taperWidth")
    }
}

// MARK: - B icon tint

/// Icons nearest the travelling card stroke take on its colour: a tinted copy of each icon
/// (and of the model picker title) fades in over it as the stroke passes.
final class DuckAIIconGlowController {

    private enum Constants {
        /// The brightest part of the stroke sits ~340° into the conic gradient.
        static let head: CGFloat = 340
        static let fadeIn: CGFloat = 22
        static let fadeOut: CGFloat = 100
        static let blue = UIColor(light: 0x0076CF, dark: 0xA9D8F9)
        static let purple = UIColor(light: 0x763AC2, dark: 0xC7B1F5)
        static let green = UIColor(light: 0x008C4D, dark: 0x9FD6B6)
        static let labelStrength: CGFloat = 0.85
        /// The stroke's ease-out passes most icons within half a second, so a purely angle-driven
        /// tint (as in the Figma prototype) only flickers on device. Each glow holds its colour
        /// after the head passes and fades over this long instead.
        static let glowDecay: CGFloat = 1.2
        /// A soft halo in the glow colour around each tinted icon makes the tint read on device.
        /// Dark icons on a light card need much less of it than light icons on a dark card.
        struct Look {
            let tintStrength: CGFloat
            let haloRadius: CGFloat
            let haloOpacity: Float
        }
        static let darkLook = Look(tintStrength: 1, haloRadius: 6, haloOpacity: 0.9)
        static let lightLook = Look(tintStrength: 0.75, haloRadius: 4, haloOpacity: 0.3)
        /// Skips photo thumbnails; icons are at most this wide.
        static let maximumIconWidth: CGFloat = 40
    }

    private weak var host: UIView?
    private weak var card: UIView?
    private weak var sweep: DuckAIEdgeSweepView?
    private let iconRoots: () -> [UIView]
    private var displayLink: CADisplayLink?
    private var cancellable: AnyCancellable?
    /// The source image each glow copy was made from, so it is re-tinted only when the icon changes.
    private let glowSources = NSMapTable<UIImageView, UIImage>.weakToWeakObjects()
    /// Icon → its glow copy in `overlay`.
    private let glows = NSMapTable<UIView, UIView>.weakToStrongObjects()
    private let overlay: UIView = {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }()
    private var lastTargets: [Target] = []
    private let logger = Logger(subsystem: "com.duckduckgo.prototype", category: "DuckAIIconGlow")
    private var wasStrokeVisible = false
    private var lastTickTime: CFTimeInterval = 0
    private var glowLevels: [ObjectIdentifier: CGFloat] = [:]
    private var didLogPeak = false

    init(host: UIView, card: UIView, sweep: DuckAIEdgeSweepView, iconRoots: @escaping () -> [UIView]) {
        self.host = host
        self.card = card
        self.sweep = sweep
        self.iconRoots = iconRoots
        cancellable = DuckAIModeVisualsDriver.shared.$activeVariant
            .sink { [weak self] variant in
                if variant == nil { self?.stop() } else { self?.start() }
            }
    }

    deinit {
        displayLink?.invalidate()
    }

    private func start() {
        guard displayLink == nil else { return }
        logger.log("[IconGlow] display link started")
        let link = CADisplayLink(target: DisplayLinkProxy(self), selector: #selector(DisplayLinkProxy.tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stop() {
        displayLink?.invalidate()
        displayLink = nil
        glowLevels.removeAll()
        hideAll()
    }

    fileprivate func tick() {
        guard let host, let card, let sweep else {
            logger.log("[IconGlow] tick without host, card or sweep")
            return
        }
        let now = CACurrentMediaTime()
        let elapsed = CGFloat(min(max(now - lastTickTime, 0), 0.1))
        lastTickTime = now

        let live = sweep.liveSweep
        let visibility = live?.visibility ?? 0
        guard visibility > 0 || glowLevels.values.contains(where: { $0 > 0 }) else {
            wasStrokeVisible = false
            hideAll()
            return
        }
        let isNewLap = visibility > 0 && !wasStrokeVisible
        if isNewLap {
            wasStrokeVisible = true
            didLogPeak = false
        } else if visibility == 0 {
            wasStrokeVisible = false
        }

        let look = host.traitCollection.userInterfaceStyle == .dark ? Constants.darkLook : Constants.lightLook
        let cardFrame = presentedFrame(of: card, in: host)
        let center = CGPoint(x: cardFrame.midX, y: cardFrame.midY)
        var peak: CGFloat = 0
        var count = 0
        forEachTarget { glow, target in
            count += 1
            let targetFrame = presentedFrame(of: target.view, in: host)
            let point = CGPoint(x: targetFrame.midX, y: targetFrame.midY)
            let iconAngle = atan2(point.x - center.x, center.y - point.y) * 180 / .pi
            // > 0: the stroke head has passed this icon.
            let delta = ((live?.angle ?? 0) + Constants.head - iconAngle).truncatingRemainder(dividingBy: 360)
            let d = (delta + 540).truncatingRemainder(dividingBy: 360) - 180
            let strength: CGFloat
            if d < -Constants.fadeIn {
                strength = 0
            } else if d < 0 {
                strength = 1 + d / Constants.fadeIn
            } else {
                strength = max(0, 1 - d / Constants.fadeOut)
            }
            let key = ObjectIdentifier(glow)
            let decayed = (glowLevels[key] ?? 0) - elapsed / Constants.glowDecay
            let level = max(strength * visibility, decayed, 0)
            glowLevels[key] = level

            let isLabel = target.view is UILabel
            glow.alpha = level * look.tintStrength * target.effectiveAlpha * (isLabel ? Constants.labelStrength : 1)
            glow.layer.shadowRadius = look.haloRadius
            glow.layer.shadowOpacity = look.haloOpacity
            peak = max(peak, glow.alpha)
            // While decaying, keep the colour the head left behind rather than sliding to green.
            if strength > 0 {
                let color = d < 18 ? Constants.blue : d < 45 ? Constants.purple : Constants.green
                if let label = glow as? UILabel {
                    label.textColor = color
                } else {
                    glow.tintColor = color
                }
                glow.layer.shadowColor = color.resolvedColor(with: host.traitCollection).cgColor
            }
        }
        if isNewLap, let live {
            logger.log("[IconGlow] lap started: \(count) targets, angle \(Double(live.angle)), visibility \(Double(live.visibility))")
        }
        if peak > 0.5, !didLogPeak {
            didLogPeak = true
            logger.log("[IconGlow] peak glow \(Double(peak)) at angle \(Double(live?.angle ?? 0))")
        }
    }

    private struct Target {
        let view: UIView
        /// The icon's alpha after its ancestors' alpha, so a fading icon fades its glow too.
        let effectiveAlpha: CGFloat
    }

    private func hideAll() {
        overlay.subviews.forEach { $0.alpha = 0 }
    }

    /// Calls `body` with each visible icon's glow copy (created on first use) and the icon it covers.
    /// Glow copies live in `overlay` above the whole card, not inside the buttons: on iOS 26 glass
    /// buttons drop colour from their own subviews.
    private func forEachTarget(_ body: (UIView, Target) -> Void) {
        guard let host else { return }
        if overlay.superview !== host || host.subviews.last !== overlay {
            host.addSubview(overlay)
        }
        overlay.frame = host.bounds
        hideAll()

        var targets: [Target] = []
        func visit(_ view: UIView, insideButton: Bool) {
            guard !view.isHidden else { return }
            if let imageView = view as? UIImageView {
                guard imageView.image != nil, imageView.bounds.width <= Constants.maximumIconWidth else { return }
                targets.append(Target(view: imageView, effectiveAlpha: effectiveAlpha(of: imageView, in: host)))
                return
            }
            if let label = view as? UILabel {
                guard insideButton, label.text?.isEmpty == false else { return }
                targets.append(Target(view: label, effectiveAlpha: effectiveAlpha(of: label, in: host)))
                return
            }
            view.subviews.forEach { visit($0, insideButton: insideButton || view is UIButton) }
        }
        iconRoots().forEach { visit($0, insideButton: false) }
        lastTargets = targets.filter { $0.effectiveAlpha > 0.01 }
        for target in lastTargets {
            body(glow(for: target.view), target)
        }
    }

    /// Reads the on-screen (presentation) alpha, so a toolbar that is still fading in keeps its glow faded too.
    private func effectiveAlpha(of view: UIView, in host: UIView) -> CGFloat {
        var alpha: CGFloat = 1
        var current: UIView? = view
        while let view = current, view !== host {
            alpha *= view.isHidden ? 0 : CGFloat((view.layer.presentation() ?? view.layer).opacity)
            current = view.superview
        }
        return alpha
    }

    /// The view's on-screen frame mid-animation, so glows ride along as the toolbar slides in.
    private func presentedFrame(of view: UIView, in host: UIView) -> CGRect {
        let source = view.layer.presentation() ?? view.layer
        let destination = host.layer.presentation() ?? host.layer
        return source.convert(source.bounds, to: destination)
    }

    private func applyHalo(to glow: UIView) {
        glow.layer.shadowOffset = .zero
    }

    private func glow(for target: UIView) -> UIView {
        guard let host else { return UIView() }
        let frame = presentedFrame(of: target, in: host)
        if let imageView = target as? UIImageView {
            let glow = glows.object(forKey: imageView) as? UIImageView ?? {
                let glow = UIImageView()
                applyHalo(to: glow)
                overlay.addSubview(glow)
                glows.setObject(glow, forKey: imageView)
                return glow
            }()
            glow.frame = frame
            glow.contentMode = imageView.contentMode
            glow.preferredSymbolConfiguration = imageView.preferredSymbolConfiguration
            if let image = imageView.image, glowSources.object(forKey: glow) !== image {
                glowSources.setObject(image, forKey: glow)
                glow.image = image.withRenderingMode(.alwaysTemplate)
            }
            return glow
        }
        guard let label = target as? UILabel else { return UIView() }
        let glow = glows.object(forKey: label) as? UILabel ?? {
            let glow = UILabel()
            applyHalo(to: glow)
            overlay.addSubview(glow)
            glows.setObject(glow, forKey: label)
            return glow
        }()
        glow.frame = frame
        glow.font = label.font
        glow.text = label.text
        glow.textAlignment = label.textAlignment
        glow.numberOfLines = label.numberOfLines
        glow.lineBreakMode = label.lineBreakMode
        return glow
    }
}

/// Breaks the retain cycle between `CADisplayLink` and its target.
private final class DisplayLinkProxy: NSObject {
    private weak var controller: DuckAIIconGlowController?

    init(_ controller: DuckAIIconGlowController) {
        self.controller = controller
        super.init()
    }

    @objc func tick() {
        controller?.tick()
    }
}

// MARK: - C: drifting circles behind the keyboard

/// Drawn in the app window under the keyboard frame; the system keyboard's translucent
/// background lets the circles show through.
final class DuckAIKeyboardGlowView: UIView {

    private struct Blob {
        let color: UIColor
        let diameter: CGFloat
        /// Centre = `anchor` (fraction of the bounds) + `offset`, from the 402pt-wide Figma keyboard.
        let anchor: CGPoint
        let offset: CGPoint
        let duration: CFTimeInterval
        /// (dx, dy, scale) at 33%, 66% and 100%; 0% is the identity.
        let keyframes: [(CGFloat, CGFloat, CGFloat)]
    }

    private static let blur: CGFloat = 40
    /// Half of the Figma value (2.7×), which read too fast on device.
    private static let speed: CFTimeInterval = 1.35
    private static let distance: CGFloat = 1.45
    private static let blobs: [Blob] = [
        Blob(color: UIColor(light: 0xE6F6FF, dark: 0x16365A), diameter: 300, anchor: CGPoint(x: 0, y: 0), offset: CGPoint(x: 60, y: 40), duration: 14,
             keyframes: [(150, 90, 1.15), (60, 220, 0.9), (-80, 120, 1.08)]),
        Blob(color: UIColor(light: 0xF5FBFE, dark: 0x0F2A44), diameter: 260, anchor: CGPoint(x: 1, y: 0), offset: CGPoint(x: -60, y: 70), duration: 17,
             keyframes: [(-160, -110, 0.88), (-60, 140, 1.14), (90, 40, 0.95)]),
        Blob(color: UIColor(light: 0xCAF0FE, dark: 0x0E3F4F), diameter: 280, anchor: CGPoint(x: 0, y: 1), offset: CGPoint(x: 100, y: -20), duration: 19,
             keyframes: [(170, -140, 1.12), (220, 60, 0.92), (40, -60, 1.06)]),
        Blob(color: UIColor(light: 0xEDEEFB, dark: 0x2A2556), diameter: 300, anchor: CGPoint(x: 1, y: 1), offset: CGPoint(x: -60, y: -40), duration: 16,
             keyframes: [(-140, -170, 1.1), (-220, -30, 0.9), (-60, -120, 1.12)]),
    ]

    private static let base = UIColor(light: 0xE6F6FF, dark: 0x0F2238)
    private static let greyTintColor = UIColor { traits in
        traits.userInterfaceStyle == .dark ? .clear : UIColor(red: 150 / 255, green: 166 / 255, blue: 180 / 255, alpha: 0.2)
    }

    private var blobLayers: [CAGradientLayer] = []
    private let greyTint = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        backgroundColor = Self.base
        for blob in Self.blobs {
            let layer = CAGradientLayer()
            layer.type = .radial
            layer.startPoint = CGPoint(x: 0.5, y: 0.5)
            layer.endPoint = CGPoint(x: 1, y: 1)
            // A radial falloff over the outer blur radius stands in for CSS `filter: blur(40px)`.
            let size = blob.diameter + Self.blur * 2
            layer.locations = [0, NSNumber(value: Double((blob.diameter / 2 - Self.blur) / (size / 2))), 1]
            self.layer.addSublayer(layer)
            blobLayers.append(layer)
        }
        layer.addSublayer(greyTint)
        applyPalette()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            applyPalette()
        }
    }

    /// Layer colours are snapshotted `CGColor`s, so they are re-resolved on each appearance change.
    private func applyPalette() {
        for (layer, blob) in zip(blobLayers, Self.blobs) {
            let color = blob.color.resolvedColor(with: traitCollection)
            layer.colors = [color.cgColor, color.cgColor, color.withAlphaComponent(0).cgColor]
        }
        greyTint.backgroundColor = Self.greyTintColor.resolvedColor(with: traitCollection).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        greyTint.frame = bounds
        for (layer, blob) in zip(blobLayers, Self.blobs) {
            let size = blob.diameter + Self.blur * 2
            layer.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            layer.position = CGPoint(x: bounds.width * blob.anchor.x + blob.offset.x,
                                     y: bounds.height * blob.anchor.y + blob.offset.y)
        }
        CATransaction.commit()
    }

    func setAnimating(_ animating: Bool) {
        guard animating, !UIAccessibility.isReduceMotionEnabled else {
            blobLayers.forEach { $0.removeAnimation(forKey: "drift") }
            return
        }
        for (layer, blob) in zip(blobLayers, Self.blobs) where layer.animation(forKey: "drift") == nil {
            let animation = CAKeyframeAnimation(keyPath: "transform")
            animation.values = ([(0, 0, 1)] + blob.keyframes).map { dx, dy, scale in
                let move = CATransform3DMakeTranslation(dx * Self.distance, dy * Self.distance, 0)
                return NSValue(caTransform3D: CATransform3DScale(move, scale, scale, 1))
            }
            animation.keyTimes = [0, 0.33, 0.66, 1]
            animation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 3)
            animation.duration = blob.duration / Self.speed
            animation.autoreverses = true
            animation.repeatCount = .infinity
            layer.add(animation, forKey: "drift")
        }
    }
}

// MARK: - Keyboard overlay

/// Pinned to the keyboard frame in the main view. Holds C's circles (B/C) and the top-edge sweep (E).
final class DuckAIKeyboardVisualsView: UIView {

    private enum Constants {
        static let keyboardCornerRadius: CGFloat = 27
        /// Below this the keyboard is hidden and the guide only covers the bottom safe area.
        static let minimumKeyboardHeight: CGFloat = 100
    }

    private let glowView = DuckAIKeyboardGlowView()
    private let edgeSweepView = DuckAIEdgeSweepView(surface: .keyboard,
                                                    topFade: DuckAIEdgeSweepView.TopFade(opaqueHeight: 14, clearHeight: 46))
    private var cancellables = Set<AnyCancellable>()
    private var activeVariant: DuckAIModeVisualVariant?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = false

        glowView.alpha = 0
        glowView.layer.cornerRadius = Constants.keyboardCornerRadius
        glowView.layer.cornerCurve = .continuous
        edgeSweepView.cornerRadius = Constants.keyboardCornerRadius
        for view in [glowView, edgeSweepView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: leadingAnchor),
                view.trailingAnchor.constraint(equalTo: trailingAnchor),
                view.topAnchor.constraint(equalTo: topAnchor),
                view.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }

        DuckAIModeVisualsDriver.shared.$activeVariant
            .sink { [weak self] variant in
                self?.activeVariant = variant
                self?.updateGlow()
            }
            .store(in: &cancellables)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        isHidden = bounds.height < Constants.minimumKeyboardHeight
        updateGlow()
    }

    private func updateGlow() {
        let shows = activeVariant == .inputKeyboard && !isHidden
        glowView.setAnimating(shows)
        guard (glowView.alpha == 1) != shows else { return }
        UIView.animate(withDuration: 0.3) {
            self.glowView.alpha = shows ? 1 : 0
        }
    }
}
