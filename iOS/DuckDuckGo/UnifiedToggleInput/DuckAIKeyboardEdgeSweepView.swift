//
//  DuckAIKeyboardEdgeSweepView.swift
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

/// Pinned to the keyboard. A stroke sweeps once along the keyboard's top edge each time the
/// keyboard comes up for the Duck.ai input, so the user notices they're typing to Duck.ai.
final class DuckAIKeyboardEdgeSweepView: UIView {

    private enum Constants {
        /// The Search Assist gradient (Mandarin 50 → Blossom 70 → Pondwater 60), laid along the stroke
        /// from tail to head.
        static let mandarin = UIColor(RebrandingColor.Mandarin.mandarin50)
        static let blossom = UIColor(RebrandingColor.Blossom.blossom70)
        static let pondwater = UIColor(RebrandingColor.Pondwater.pondwater60)
        /// The trail's length on the conic gradient, in degrees behind its 360° end.
        static let maximumTrailLength: CGFloat = 220
        static let minimumTrailLength: CGFloat = 60
        static let keyboardCornerRadius: CGFloat = 27
        /// Below this the keyboard is hidden (or a hardware keyboard is attached) and the guide
        /// only covers the bottom safe area.
        static let minimumKeyboardHeight: CGFloat = 100
        static let duration: CFTimeInterval = 2.5
        /// The input can drop the keyboard for a moment while it switches modes or reloads its keyboard;
        /// a gap shorter than this doesn't count as leaving, so the sweep doesn't replay.
        static let leaveGracePeriod: TimeInterval = 0.3
        static let easing = CAMediaTimingFunction(name: .easeOut)
        static let leadStartWidth: CGFloat = 2
        static let trailWidth: CGFloat = 1
        static let opacity: Float = 0.65
        /// The stroke is opaque this far below the keyboard's top edge and gone by `fadeEnd`.
        static let fadeStart: CGFloat = 14
        static let fadeEnd: CGFloat = 46
        /// Where the bright head sits on the conic gradient, in degrees clockwise from the top.
        static let headAngle: CGFloat = 355
        /// How far, in degrees, the stroke stays from the visible part of the ring before and after the pass.
        static let clearance: CGFloat = 10
    }

    static func isActive(isFeatureOn: Bool,
                         isUserSettingEnabled: Bool,
                         isInputEditing: Bool,
                         inputMode: TextEntryMode,
                         isUnifiedToggleInputAvailable: Bool) -> Bool {
        isFeatureOn && isUserSettingEnabled && isInputEditing && inputMode == .aiChat && isUnifiedToggleInputAvailable
    }

    func update(isActive: Bool, keyboardTargetHeight: CGFloat? = nil) {
        guard isActive || self.isActive else { return }
        self.isActive = isActive
        if !isActive {
            isAwaitingKeyboardReveal = false
        } else if let keyboardTargetHeight {
            isAwaitingKeyboardReveal = keyboardTargetHeight >= Constants.minimumKeyboardHeight
                && bounds.height < Constants.minimumKeyboardHeight
        }
        setNeedsLayout()
        layoutIfNeeded()
    }

    private var isActive = false
    private var isAwaitingKeyboardReveal = false
    private var hasPlayed = false
    private var pendingReset: DispatchWorkItem?
    private var isPlaybackReady: Bool {
        isActive && bounds.width > 0 && (bounds.height >= Constants.minimumKeyboardHeight || isAwaitingKeyboardReveal)
    }
    private var ringBounds: CGRect { CGRect(x: 0, y: 0, width: max(0, bounds.width), height: max(0, bounds.width)) }
    private let fadeContainer = CALayer()
    private let fadeMask = CAGradientLayer()
    private let trailHost = CALayer()
    private let trailMask = CAShapeLayer()
    private let trailGradient = CAGradientLayer()
    private let leadHost = CALayer()
    private let leadMask = CAShapeLayer()
    private let leadGradient = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = false

        func stop(_ degrees: CGFloat) -> NSNumber { NSNumber(value: Double(degrees / 360)) }
        // Transparent ends keep their neighbour's RGB, so the fade doesn't pass through grey.
        let mandarin = Constants.mandarin, blossom = Constants.blossom, pondwater = Constants.pondwater

        trailGradient.colors = [mandarin.withAlphaComponent(0), mandarin.withAlphaComponent(0), mandarin,
                                blossom, pondwater, pondwater.withAlphaComponent(0)].map(\.cgColor)
        trailGradient.locations = trailLocations(length: Constants.maximumTrailLength)
        leadGradient.colors = [blossom.withAlphaComponent(0), blossom.withAlphaComponent(0), blossom.withAlphaComponent(0.35),
                               pondwater.withAlphaComponent(0.8), pondwater, pondwater.withAlphaComponent(0)].map(\.cgColor)
        leadGradient.locations = [0, stop(255), stop(285), stop(325), stop(352), 1]

        fadeMask.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
        fadeContainer.mask = fadeMask
        fadeContainer.opacity = Constants.opacity
        layer.addSublayer(fadeContainer)
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
            fadeContainer.addSublayer(host)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        isHidden = bounds.width <= 0 || bounds.height < Constants.minimumKeyboardHeight
        if bounds.height >= Constants.minimumKeyboardHeight {
            isAwaitingKeyboardReveal = false
        }
        if hasPlayed && trailHost.bounds.width != ringBounds.width {
            removeAnimations()
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let side = hypot(ringBounds.width, ringBounds.height) + 16
        fadeContainer.frame = bounds
        for host in [trailHost, leadHost] {
            host.frame = ringBounds
            host.mask?.frame = ringBounds
        }
        for gradient in [trailGradient, leadGradient] {
            gradient.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            gradient.position = CGPoint(x: ringBounds.midX, y: ringBounds.midY)
        }
        trailGradient.locations = trailLocations(length: trailLength)
        trailMask.path = ringPath(width: Constants.trailWidth)
        leadMask.path = ringPath(width: Constants.trailWidth)
        // Starts above the bounds so the ring drawn outside the top edge stays inside the mask.
        let overhang = Constants.leadStartWidth * 2
        let height = Constants.fadeEnd + overhang
        fadeMask.frame = CGRect(x: -overhang, y: -overhang, width: bounds.width + overhang * 2, height: height)
        fadeMask.locations = [0, NSNumber(value: Double((Constants.fadeStart + overhang) / height)), 1]
        CATransaction.commit()
        reconcilePlayback()
    }

    private func reconcilePlayback() {
        if isPlaybackReady {
            pendingReset?.cancel()
            pendingReset = nil
            guard !hasPlayed else { return }
            play()
        } else {
            guard hasPlayed, pendingReset == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingReset = nil
                guard !self.isPlaybackReady else { return }
                self.reset()
            }
            pendingReset = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Constants.leaveGracePeriod, execute: work)
        }
    }

    /// Half the angle, seen from the gradient's centre, over which the stroke shows: the top edge and
    /// the top of each side down to `fadeEnd`. Only this part of the ring is ever visible.
    private var visibleHalfAngle: CGFloat {
        atan2(ringBounds.width / 2, ringBounds.height / 2 - Constants.fadeEnd) * 180 / .pi
    }

    private var trailLength: CGFloat {
        max(Constants.minimumTrailLength, min(Constants.maximumTrailLength, 360 - 2 * (visibleHalfAngle + Constants.clearance)))
    }

    private func trailLocations(length: CGFloat) -> [NSNumber] {
        // The Search Assist stops, from the trail's transparent tail to its transparent head at 360°.
        [0, 0.002, 0.248, 0.499, 0.749].map { NSNumber(value: Double((360 - length + length * $0) / 360)) } + [1]
    }

    /// A ring of `width` drawn just outside the keyboard's edge.
    private func ringPath(width: CGFloat) -> CGPath {
        let offset = width / 2
        let radius = Constants.keyboardCornerRadius + offset
        return UIBezierPath(roundedRect: ringBounds.insetBy(dx: -offset, dy: -offset), cornerRadius: radius).cgPath
    }

    private func play() {
        hasPlayed = true
        guard !UIAccessibility.isReduceMotionEnabled else { return }

        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        // The head starts just left of the visible top and stops once the tail has cleared its right side.
        let edge = visibleHalfAngle + Constants.clearance
        rotation.fromValue = (-edge - Constants.headAngle) * .pi / 180
        rotation.toValue = (edge + trailLength - Constants.headAngle) * .pi / 180
        rotation.duration = Constants.duration
        rotation.timingFunction = Constants.easing
        rotation.fillMode = .forwards
        rotation.isRemovedOnCompletion = false

        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 1, 1, 0]
        opacity.keyTimes = [0, 0.05, 0.7, 1]
        opacity.duration = Constants.duration

        // The lead starts wide and narrows to the trail width by 75% of the run, on a linear clock.
        let taperPath = CAKeyframeAnimation(keyPath: "path")
        taperPath.values = [ringPath(width: Constants.leadStartWidth), ringPath(width: Constants.trailWidth), ringPath(width: Constants.trailWidth)]
        taperPath.keyTimes = [0, 0.75, 1]
        taperPath.duration = Constants.duration
        let taperWidth = CAKeyframeAnimation(keyPath: "lineWidth")
        taperWidth.values = [Constants.leadStartWidth, Constants.trailWidth, Constants.trailWidth]
        taperWidth.keyTimes = [0, 0.75, 1]
        taperWidth.duration = Constants.duration

        trailGradient.add(rotation, forKey: "sweep")
        leadGradient.add(rotation, forKey: "sweep")
        trailHost.add(opacity, forKey: "sweep")
        leadHost.add(opacity, forKey: "sweep")
        leadMask.add(taperPath, forKey: "taperPath")
        leadMask.add(taperWidth, forKey: "taperWidth")
    }

    private func reset() {
        hasPlayed = false
        removeAnimations()
    }

    private func removeAnimations() {
        [trailHost, leadHost, trailGradient, leadGradient, leadMask].forEach { $0.removeAllAnimations() }
    }
}
