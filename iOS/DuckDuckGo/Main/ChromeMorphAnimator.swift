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

/// Moves the chrome visibility fraction toward a target, never faster than `maxSpeed`.
///
/// That speed limit is the entire timing model. A scroll only ever assigns a new target; the
/// animator decides nothing. Changes slower than the limit land exactly on their target each frame,
/// so an unhurried drag still reads as direct manipulation; anything faster is paced out, so a full
/// hide or reveal always takes `fullTraversalDuration` however hard the page was flicked.
///
/// There is deliberately no elapsed clock, no from/to pair and no notion of "retargeting": a new
/// target mid-flight is a plain assignment, which is what removes the stall and snap failure modes
/// a start-time-based animation needs explicit handling to avoid.
final class ChromeMorphAnimator {

    static let defaultTraversalDuration: CFTimeInterval = 0.30

    /// Below this the remaining distance is not worth another frame.
    private static let settleEpsilon: CGFloat = 0.001

    private let maxSpeed: CGFloat
    private var legSpeed: CGFloat

    private var displayLink: CADisplayLink?
    private var target: CGFloat = 1
    private var onProgress: ((CGFloat) -> Void)?
    private var onComplete: (() -> Void)?

    /// The value last emitted, so an interrupted morph resumes from where it visually is.
    private(set) var currentValue: CGFloat = 1

    var isAnimating: Bool { displayLink != nil }

    var targetValue: CGFloat { target }

    init(fullTraversalDuration: CFTimeInterval = ChromeMorphAnimator.defaultTraversalDuration) {
        maxSpeed = 1 / CGFloat(max(fullTraversalDuration, 0.0001))
        legSpeed = maxSpeed
    }

    /// Aims the morph at `value`. `fullTraversalDuration` overrides the pace for this leg only, for
    /// the few callers that need a specific length (find-in-page, onboarding).
    func setTarget(_ value: CGFloat,
                   fullTraversalDuration: CFTimeInterval? = nil,
                   onProgress: @escaping (CGFloat) -> Void,
                   onComplete: @escaping () -> Void) {
        target = value
        legSpeed = fullTraversalDuration.map { 1 / CGFloat(max($0, 0.0001)) } ?? maxSpeed
        self.onProgress = onProgress
        self.onComplete = onComplete

        guard abs(target - currentValue) > Self.settleEpsilon else {
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
        onProgress = nil
        onComplete = nil
    }

    private func handleTick(_ link: CADisplayLink) {
        // The frame's own duration, so there is no start timestamp to seed, carry over or go stale.
        let frameDuration = CGFloat(max(link.targetTimestamp - link.timestamp, 0))
        let remaining = target - currentValue
        let maxStep = legSpeed * frameDuration

        guard abs(remaining) > maxStep else {
            settle()
            return
        }
        currentValue += remaining < 0 ? -maxStep : maxStep
        onProgress?(currentValue)
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
