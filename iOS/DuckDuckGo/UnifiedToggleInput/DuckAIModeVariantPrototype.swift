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

    /// The prototype palette comes from the light-mode Figma file only.
    static func isSupported(in traits: UITraitCollection) -> Bool {
        traits.userInterfaceStyle != .dark
    }

    static let duckAITabTint = UIColor { traits in
        DuckAIModeVisualVariant.isSupported(in: traits) ? UIColor(prototypeHex: 0x034180) : UIColor(designSystemColor: .textPrimary)
    }
}

extension UIColor {
    convenience init(prototypeHex hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
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

// MARK: - C: drifting circles behind the keyboard

/// Drawn in the app window under the keyboard frame; the system keyboard's translucent
/// background lets the circles show through.
final class DuckAIKeyboardGlowView: UIView {

    private struct Blob {
        let color: UInt32
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
        Blob(color: 0xE6F6FF, diameter: 300, anchor: CGPoint(x: 0, y: 0), offset: CGPoint(x: 60, y: 40), duration: 14,
             keyframes: [(150, 90, 1.15), (60, 220, 0.9), (-80, 120, 1.08)]),
        Blob(color: 0xF5FBFE, diameter: 260, anchor: CGPoint(x: 1, y: 0), offset: CGPoint(x: -60, y: 70), duration: 17,
             keyframes: [(-160, -110, 0.88), (-60, 140, 1.14), (90, 40, 0.95)]),
        Blob(color: 0xCAF0FE, diameter: 280, anchor: CGPoint(x: 0, y: 1), offset: CGPoint(x: 100, y: -20), duration: 19,
             keyframes: [(170, -140, 1.12), (220, 60, 0.92), (40, -60, 1.06)]),
        Blob(color: 0xEDEEFB, diameter: 300, anchor: CGPoint(x: 1, y: 1), offset: CGPoint(x: -60, y: -40), duration: 16,
             keyframes: [(-140, -170, 1.1), (-220, -30, 0.9), (-60, -120, 1.12)]),
    ]

    private var blobLayers: [CAGradientLayer] = []
    private let greyTint = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        backgroundColor = UIColor(prototypeHex: 0xE6F6FF)
        for blob in Self.blobs {
            let layer = CAGradientLayer()
            layer.type = .radial
            layer.startPoint = CGPoint(x: 0.5, y: 0.5)
            layer.endPoint = CGPoint(x: 1, y: 1)
            let color = UIColor(prototypeHex: blob.color)
            layer.colors = [color.cgColor, color.cgColor, color.withAlphaComponent(0).cgColor]
            // A radial falloff over the outer blur radius stands in for CSS `filter: blur(40px)`.
            let size = blob.diameter + Self.blur * 2
            layer.locations = [0, NSNumber(value: Double((blob.diameter / 2 - Self.blur) / (size / 2))), 1]
            self.layer.addSublayer(layer)
            blobLayers.append(layer)
        }
        greyTint.backgroundColor = UIColor(red: 150 / 255, green: 166 / 255, blue: 180 / 255, alpha: 0.2).cgColor
        layer.addSublayer(greyTint)
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
