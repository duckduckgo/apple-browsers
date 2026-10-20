//
//  FireAnimationInstrumentation.swift
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

import Foundation
import PixelKit
import QuartzCore

@MainActor
protocol FireAnimationInstrumentation {
    func burnDidStart(accepted: Bool)
    func burnDidFinish()
    func animationDidFinish(animation: FireButtonAnimationType)
}

@MainActor
final class DefaultFireAnimationInstrumentation: FireAnimationInstrumentation {
    private let pixelFiring: PixelFiring?
    private let timeProvider: () -> CFTimeInterval
    private let scope: String
    private let source: String
    private let isManualBurn: Bool
    private var burnStarted = false
    private var burnFinished = false
    private var completedAnimation: FireButtonAnimationType?
    private var animationEndTime: CFTimeInterval?

    init(request: FireRequest,
         pixelFiring: PixelFiring? = PixelKit.shared,
         timeProvider: @escaping () -> CFTimeInterval = CACurrentMediaTime) {
        self.pixelFiring = pixelFiring
        self.timeProvider = timeProvider
        self.source = request.source.rawValue
        self.isManualBurn = request.trigger == .manualFire
        switch request.scope {
        case .all: scope = "all"
        case .tab: scope = "tab"
        case .fireMode: scope = "fire_mode"
        case .normalMode: scope = "normal_mode"
        }
    }

    func burnDidStart(accepted: Bool = true) {
        guard accepted, isManualBurn else { return }
        burnStarted = true
    }

    func burnDidFinish() {
        guard burnStarted, !burnFinished else { return }
        burnFinished = true
        guard let animationEndTime, let completedAnimation else { return }
        pixelFiring?.fire(FireAnimationPixels.burnCompletedAfterAnimation(
            scope: scope, source: source, animation: completedAnimation.rawValue,
            elapsed: .init(seconds: timeProvider() - animationEndTime)), frequency: .standard)
    }

    func animationDidFinish(animation: FireButtonAnimationType) {
        guard burnStarted, completedAnimation == nil else { return }
        completedAnimation = animation
        pixelFiring?.fire(FireAnimationPixels.animationCompleted(
            scope: scope, source: source, animation: animation.rawValue, burnInProgress: !burnFinished),
            frequency: .dailyAndCount)
        guard !burnFinished else { return }
        animationEndTime = timeProvider()
        pixelFiring?.fire(FireAnimationPixels.burnOutlastedAnimation(
            scope: scope, source: source, animation: animation.rawValue), frequency: .dailyAndCount)
    }
}
