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

/// Drives a value from a start to a target over a duration using a `CADisplayLink`, emitting an
/// eased progress each frame.
///
/// Used to replay the floating-UI capsule morph — the same per-frame chrome state the scroll path
/// applies — during a discrete animated bar reveal/hide. A single `UIView.animate` can't reproduce
/// the morph because its geometry and alpha handoff are non-linear in the visibility percent, so it
/// only interpolates the endpoints (the bars pop or slide in). Scrubbing the percent replays the
/// exact transition instead.
final class ChromeMorphAnimator {

    /// Forwards display-link ticks without the link retaining the animator, so the animator (and its
    /// link) deallocate naturally when their owner goes away even if `cancel()` is never called.
    private final class WeakDisplayLinkProxy {
        weak var target: ChromeMorphAnimator?

        init(target: ChromeMorphAnimator) {
            self.target = target
        }

        @objc func tick(_ link: CADisplayLink) {
            target?.handleTick(link)
        }
    }

    private var displayLink: CADisplayLink?
    private var startTimestamp: CFTimeInterval = 0
    private var hasStartTimestamp = false
    private var duration: CFTimeInterval = 0
    private var fromValue: CGFloat = 0
    private var toValue: CGFloat = 0
    private var onProgress: ((CGFloat) -> Void)?
    private var onComplete: (() -> Void)?

    /// The last value emitted, so an interrupted animation can resume from where it visually is
    /// rather than snapping back to a stale endpoint.
    private(set) var currentValue: CGFloat = 1

    var isAnimating: Bool {
        displayLink != nil
    }

    /// Starts scrubbing `from` -> `to` over `duration`, calling `onProgress` each frame (including
    /// immediately with `from`) and `onComplete` once settled. A zero/negative duration applies the
    /// target synchronously. Any in-flight animation is cancelled first.
    func animate(from: CGFloat,
                 to: CGFloat,
                 duration: CFTimeInterval,
                 onProgress: @escaping (CGFloat) -> Void,
                 onComplete: @escaping () -> Void) {
        cancel()

        guard duration > 0 else {
            currentValue = to
            onProgress(to)
            onComplete()
            return
        }

        self.fromValue = from
        self.toValue = to
        self.duration = duration
        self.onProgress = onProgress
        self.onComplete = onComplete
        currentValue = from
        hasStartTimestamp = false

        let link = CADisplayLink(target: WeakDisplayLinkProxy(target: self), selector: #selector(WeakDisplayLinkProxy.tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link

        // Apply the starting state immediately; the elapsed clock starts on the first tick.
        onProgress(from)
    }

    /// Stops the animation without firing completion. Safe to call when not animating.
    func cancel() {
        displayLink?.invalidate()
        displayLink = nil
        onProgress = nil
        onComplete = nil
    }

    private func handleTick(_ link: CADisplayLink) {
        // Start the clock on the first tick (the starting state was already applied in `animate`),
        // so the animation runs for the full requested duration from here.
        guard hasStartTimestamp else {
            startTimestamp = link.timestamp
            hasStartTimestamp = true
            return
        }

        let elapsed = link.timestamp - startTimestamp
        let t = max(0, min(1, duration > 0 ? elapsed / duration : 1))

        if t >= 1 {
            currentValue = toValue
            let completion = onComplete
            cancel()
            completion?()
            return
        }

        let eased = t * t * (3 - 2 * t)
        let value = fromValue + (toValue - fromValue) * CGFloat(eased)
        currentValue = value
        onProgress?(value)
    }

    deinit {
        cancel()
    }
}
