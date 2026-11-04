//
//  DuckAISwipeNewChat.swift
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

import CoreGraphics
import Foundation

/// Pulling up past the bottom of a Duck.ai chat starts a new chat in a new tab.
enum DuckAISwipeNewChat {

    /// Every tunable of the gesture, in one place for design.
    enum Constants {
        /// How far the finger must keep pulling up once the chat is at its bottom.
        static let triggerDistance: CGFloat = 110
        /// Gap between the hint and the top of the bottom chrome.
        static let hintSpacing: CGFloat = 12
        /// How far below its resting place the hint starts its slide in.
        static let hintSlideDistance: CGFloat = 20
        static let hintHideDuration: TimeInterval = 0.2
        static let undoToastDuration: TimeInterval = 4
    }

    /// What decides, when a pan begins, whether it may start a new chat.
    struct Eligibility: Equatable {
        var isFeatureEnabled: Bool
        var isPhone: Bool
        var hasChat: Bool
        var isKeyboardVisible: Bool
        var isGenerating: Bool
        var panVelocity: CGPoint
        var startY: CGFloat
        /// Where the bottom safe-area inset (home indicator) starts, in the same coordinates as `startY`.
        var bottomInsetMinY: CGFloat

        var isEligible: Bool {
            isFeatureEnabled
            && isPhone
            && hasChat
            && !isKeyboardVisible
            && !isGenerating
            && abs(panVelocity.y) > abs(panVelocity.x)
            && startY < bottomInsetMinY
        }
    }

    enum Event: Equatable {
        case began(isEligible: Bool)
        /// The page reported the chat under the finger is at its bottom; `translation` is the pan's vertical translation then.
        case reachedBottom(translation: CGFloat)
        case moved(translation: CGFloat)
        case ended
        case cancelled
    }

    enum Effect: Equatable {
        case checkAtBottom
        case showHint(progress: CGFloat, isArmed: Bool)
        case hideHint
        case haptic
        case startNewChat
    }

    enum Pull: Equatable {
        case idle
        /// Eligible, waiting for the chat to reach its bottom.
        case tracking
        /// At the bottom; the pull is measured upward from `baseline`.
        case pulling(baseline: CGFloat)
        /// Pulled past the threshold; releasing starts a new chat.
        case armed(baseline: CGFloat)

        mutating func handle(_ event: Event) -> [Effect] {
            switch (self, event) {
            case (_, .began(let isEligible)):
                self = isEligible ? .tracking : .idle
                return isEligible ? [.checkAtBottom] : []

            case (.tracking, .reachedBottom(let translation)):
                self = .pulling(baseline: translation)
                return []

            case (.tracking, .moved):
                return [.checkAtBottom]

            case (.pulling(let baseline), .moved(let translation)), (.armed(let baseline), .moved(let translation)):
                let progress = min(max((baseline - translation) / Constants.triggerDistance, 0), 1)
                let isArmed = progress >= 1
                let wasArmed = self == .armed(baseline: baseline)
                self = isArmed ? .armed(baseline: baseline) : .pulling(baseline: baseline)
                let hint = Effect.showHint(progress: progress, isArmed: isArmed)
                return isArmed && !wasArmed ? [hint, .haptic] : [hint]

            case (.armed, .ended):
                self = .idle
                return [.hideHint, .startNewChat]

            case (.pulling, .ended), (.pulling, .cancelled), (.armed, .cancelled):
                self = .idle
                return [.hideHint]

            case (.tracking, .ended), (.tracking, .cancelled):
                self = .idle
                return []

            case (.idle, _), (.pulling, .reachedBottom), (.armed, .reachedBottom):
                return []
            }
        }
    }
}
