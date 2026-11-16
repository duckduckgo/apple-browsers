//
//  ChromeMorphAnimator.swift
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

/// Moves the chrome visibility fraction toward a target on a damped spring.
///
/// A scroll only ever assigns a new target; the spring decides the pacing. It carries its velocity
/// across target changes, so reversing mid-flight neither stalls nor snaps, and a hard flick is
/// paced out over roughly `collapseDuration` / `expandDuration` instead of cutting in one frame.
/// Expanding runs slightly past the target before settling, which is what gives the morph its give;
/// collapsing stops as soon as it arrives.
final class ChromeMorphAnimator {

    static let defaultCollapseDuration: CFTimeInterval = 0.225
    static let defaultExpandDuration: CFTimeInterval = 0.285

    /// Slightly under-damped: about 1.5% overshoot.
    static let dampingRatio: CGFloat = 0.8

    /// Spring response per second of perceived duration, for `dampingRatio`.
    private static let responsePerDuration: CGFloat = 1.35

    /// Below these the remaining motion is not worth another frame.
    private static let settleEpsilon: CGFloat = 0.001
    private static let settleSpeedEpsilon: CGFloat = 0.02

    /// Longest step integrated at once; longer frames are split so the spring stays stable.
    private static let maxIntegrationStep: CGFloat = 1.0 / 240
    /// A stalled run loop resumes the spring instead of fast-forwarding through it.
    private static let maxFrameDuration: CGFloat = 0.1

    private let collapseDuration: CFTimeInterval
    private let expandDuration: CFTimeInterval
    private var response: CGFloat

    private var displayLink: CADisplayLink?
    private var previousTargetTimestamp: CFTimeInterval?
    private var target: CGFloat = 1
    private var velocity: CGFloat = 0
    private var onProgress: ((CGFloat) -> Void)?
    private var onComplete: (() -> Void)?

    /// The value last emitted, so an interrupted morph resumes from where it visually is. May sit
    /// slightly outside `0...1` while the spring settles.
    private(set) var currentValue: CGFloat = 1

    var isAnimating: Bool { displayLink != nil }

    var targetValue: CGFloat { target }

    init(collapseDuration: CFTimeInterval = ChromeMorphAnimator.defaultCollapseDuration,
         expandDuration: CFTimeInterval = ChromeMorphAnimator.defaultExpandDuration) {
        self.collapseDuration = collapseDuration
        self.expandDuration = expandDuration
        response = Self.response(forDuration: collapseDuration)
    }

    private static func response(forDuration duration: CFTimeInterval) -> CGFloat {
        CGFloat(max(duration, 0.0001)) * responsePerDuration
    }

    /// Aims the morph at `value`. `duration` overrides the pace for this leg only, for the few
    /// callers that need a specific length (find-in-page, onboarding).
    func setTarget(_ value: CGFloat,
                   duration: CFTimeInterval? = nil,
                   onProgress: @escaping (CGFloat) -> Void,
                   onComplete: @escaping () -> Void) {
        if value != target || duration != nil {
            response = Self.response(forDuration: duration ?? (value < currentValue ? collapseDuration : expandDuration))
        }
        target = value
        self.onProgress = onProgress
        self.onComplete = onComplete

        guard isAnimating || abs(target - currentValue) > Self.settleEpsilon else {
            settle()
            return
        }
        guard displayLink == nil else { return }

        let link = CADisplayLink(target: WeakDisplayLinkProxy(target: self), selector: #selector(WeakDisplayLinkProxy.tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// Applies `value` with no motion, abandoning anything in flight. For callers that supersede the
    /// morph entirely rather than redirecting it.
    func jump(to value: CGFloat) {
        cancel()
        currentValue = value
        target = value
    }

    /// Stops motion without firing completion. Safe to call when idle.
    func cancel() {
        displayLink?.invalidate()
        displayLink = nil
        previousTargetTimestamp = nil
        velocity = 0
        onProgress = nil
        onComplete = nil
    }

    private func handleTick(_ link: CADisplayLink) {
        advance(timestamp: link.timestamp, targetTimestamp: link.targetTimestamp)
    }

    /// Uses time between delivered frames so a missed callback does not stretch the animation.
    /// Retargeting preserves this clock, the displayed value and its velocity.
    func advance(timestamp: CFTimeInterval, targetTimestamp: CFTimeInterval) {
        guard isAnimating else { return }
        let elapsed = CGFloat(max(targetTimestamp - (previousTargetTimestamp ?? timestamp), 0))
        previousTargetTimestamp = targetTimestamp
        integrate(over: min(elapsed, Self.maxFrameDuration))

        // The collapsed end has no give: the shape can't shrink further, so stop on arrival rather
        // than spend the spring's tail frozen just below it.
        if target <= 0, currentValue <= 0 {
            settle()
            return
        }

        guard abs(target - currentValue) > Self.settleEpsilon || abs(velocity) > Self.settleSpeedEpsilon else {
            settle()
            return
        }
        onProgress?(currentValue)
    }

    private func integrate(over duration: CGFloat) {
        let angularFrequency = 2 * .pi / response
        let stiffness = angularFrequency * angularFrequency
        let damping = 2 * Self.dampingRatio * angularFrequency
        var remaining = duration
        while remaining > 0 {
            let step = min(remaining, Self.maxIntegrationStep)
            velocity += (stiffness * (target - currentValue) - damping * velocity) * step
            currentValue += velocity * step
            remaining -= step
        }
    }

    private func settle() {
        currentValue = target
        let progress = onProgress
        let completion = onComplete
        cancel()
        progress?(currentValue)
        completion?()
    }

    /// Forwards ticks without the link retaining the animator.
    private final class WeakDisplayLinkProxy {
        weak var target: ChromeMorphAnimator?

        init(target: ChromeMorphAnimator) {
            self.target = target
        }

        @objc func tick(_ link: CADisplayLink) {
            target?.handleTick(link)
        }
    }

    deinit {
        cancel()
    }
}
