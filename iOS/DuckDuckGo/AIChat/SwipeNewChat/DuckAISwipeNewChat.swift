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

/// Pulling up past the bottom of a Duck.ai chat opens a new chat in a new tab.
enum DuckAISwipeNewChat {

    enum Constants {
        static let triggerDistance: CGFloat = 150
        /// Each step reached on the way up ticks; the last one arms.
        static let hapticSteps = 5
        /// How much of the finger's movement past the trigger the chat follows.
        static let overpullResistance: CGFloat = 0.3
        static let indicatorSpacing: CGFloat = 4
        static let springBackDuration: TimeInterval = 0.35
        static let commitDuration: TimeInterval = 0.2
        /// A finger held this long before moving is a long press or a drag, not a pull.
        static let longPressDuration: TimeInterval = 0.5
        /// How long the new tab gets to appear before the old chat is put back.
        static let newTabTimeout: TimeInterval = 1
    }

    struct Eligibility: Equatable {
        var isFeatureAvailable: Bool
        var hasChat: Bool
        var isGenerating: Bool
        var isVoiceSessionActive: Bool
        var isInputHidden: Bool
        var panVelocity: CGPoint
        var startY: CGFloat
        /// Top of the home indicator inset, in the same coordinates as `startY`.
        var bottomInsetMinY: CGFloat
        var isHeld: Bool

        var isEligible: Bool {
            isFeatureAvailable
            && hasChat
            && !isGenerating
            && !isVoiceSessionActive
            && !isInputHidden
            && abs(panVelocity.y) > abs(panVelocity.x)
            && startY < bottomInsetMinY
            && !isHeld
        }
    }

    enum Event: Equatable {
        case touchedDown
        case pageAnswered(isAtBottom: Bool, translation: CGFloat)
        case began(isEligible: Bool, translation: CGFloat)
        case moved(translation: CGFloat)
        case ended
        case cancelled
    }

    enum Effect: Equatable {
        case checkAtBottom
        /// `progress` runs from 0 to 1 toward the trigger.
        case pull(distance: CGFloat, progress: CGFloat, isArmed: Bool)
        case tick(step: Int)
        case arm
        case springBack
        case startNewChat
    }

    /// A pan that starts above the bottom scrolls the chat, and starts pulling once it reaches the bottom while the
    /// finger is still down. Momentum after release never pulls.
    enum Pull: Equatable {
        case idle
        /// `isAtBottom` is nil until the page answers.
        case touched(isAtBottom: Bool?)
        /// Eligible, waiting for the page's answer.
        case tracking
        /// Scrolling toward the bottom; the page is asked again as the finger moves, one question at a time.
        case seeking(isAsking: Bool)
        case pulling(baseline: CGFloat, step: Int)
        case armed(baseline: CGFloat)

        /// A tap leaves `.touched` behind, which doesn't count, since nothing has moved.
        var isUnderway: Bool {
            switch self {
            case .tracking, .seeking, .pulling, .armed: true
            case .idle, .touched: false
            }
        }

        mutating func handle(_ event: Event) -> [Effect] {
            switch (self, event) {
            case (.idle, .touchedDown), (.touched, .touchedDown):
                self = .touched(isAtBottom: nil)
                return [.checkAtBottom]

            case (.touched(nil), .pageAnswered(let isAtBottom, _)):
                self = .touched(isAtBottom: isAtBottom)
                return []

            case (.tracking, .pageAnswered(let isAtBottom, let translation)),
                 (.seeking, .pageAnswered(let isAtBottom, let translation)):
                self = isAtBottom ? .pulling(baseline: translation, step: 0) : .seeking(isAsking: false)
                return []

            case (.seeking(false), .moved):
                self = .seeking(isAsking: true)
                return [.checkAtBottom]

            case (_, .began(false, _)):
                self = .idle
                return []

            case (.touched(true), .began(true, let translation)):
                self = .pulling(baseline: translation, step: 0)
                return []

            case (.touched(false), .began(true, _)):
                self = .seeking(isAsking: false)
                return []

            case (.touched(nil), .began(true, _)):
                self = .tracking
                return []

            case (_, .began(true, _)):
                // No touch-down was seen, so the page is asked now.
                self = .tracking
                return [.checkAtBottom]

            case (.pulling(let baseline, let step), .moved(let translation)):
                return pull(from: baseline, to: translation, lastStep: step)

            case (.armed(let baseline), .moved(let translation)):
                return pull(from: baseline, to: translation, lastStep: Constants.hapticSteps)

            case (.armed, .ended):
                self = .idle
                return [.startNewChat]

            case (.pulling, .ended), (.pulling, .cancelled), (.armed, .cancelled):
                self = .idle
                return [.springBack]

            case (.touched, .ended), (.touched, .cancelled), (.tracking, .ended), (.tracking, .cancelled),
                 (.seeking, .ended), (.seeking, .cancelled):
                self = .idle
                return []

            case (.idle, _), (.touched, _), (.tracking, _), (.seeking, _), (.pulling, _), (.armed, _):
                return []
            }
        }

        private mutating func pull(from baseline: CGFloat, to translation: CGFloat, lastStep: Int) -> [Effect] {
            let distance = max(baseline - translation, 0)
            let progress = min(distance / Constants.triggerDistance, 1)
            let step = Int(progress * CGFloat(Constants.hapticSteps))
            let isArmed = step == Constants.hapticSteps
            self = isArmed ? .armed(baseline: baseline) : .pulling(baseline: baseline, step: step)

            var effects: [Effect] = [.pull(distance: distance, progress: progress, isArmed: isArmed)]
            if isArmed, lastStep < Constants.hapticSteps {
                effects.append(.arm)
            } else if !isArmed, step > lastStep {
                effects.append(.tick(step: step))
            }
            return effects
        }
    }

    /// From release to the new tab: the old chat fades out, then a new tab is asked for. The old chat is put back
    /// once its tab goes off screen, after a timeout, or if anything unexpected happens first.
    enum Commit: Equatable {
        case idle
        case leaving(chatID: String)
        case awaitingNewTab

        enum Event: Equatable {
            case released(chatID: String?)
            /// `chatID` and `isEligible` are read when the fade finishes, not at release.
            case fadedOut(chatID: String?, isEligible: Bool)
            case urlChanged(chatID: String?)
            case timedOut
            case cancelled
        }

        enum Effect: Equatable {
            case fadeOut
            case requestNewChat
            case scheduleTimeout
            case restore
        }

        mutating func handle(_ event: Event) -> [Effect] {
            switch (self, event) {
            case (.idle, .released(let chatID?)):
                self = .leaving(chatID: chatID)
                return [.fadeOut]

            case (.leaving(let chatID), .fadedOut(let current, let isEligible)):
                guard isEligible, current == chatID else {
                    self = .idle
                    return [.restore]
                }
                self = .awaitingNewTab
                return [.requestNewChat, .scheduleTimeout]

            case (.leaving(let chatID), .urlChanged(let current)) where current != chatID:
                self = .idle
                return [.restore]

            case (.leaving, .cancelled), (.awaitingNewTab, .cancelled), (.awaitingNewTab, .timedOut):
                self = .idle
                return [.restore]

            case (.idle, .released(nil)):
                return [.restore]

            default:
                return []
            }
        }
    }
}
