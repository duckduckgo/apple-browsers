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

    /// Every tunable of the gesture, in one place for design.
    enum Constants {
        /// How far the finger must keep pulling up once the chat is at its bottom.
        static let triggerDistance: CGFloat = 110
        /// The pull is split into this many steps; each one reached on the way up ticks, the last one arms.
        static let hapticSteps = 5
        /// Past the trigger, the chat follows the finger this much, so it resists further pulling.
        static let overpullResistance: CGFloat = 0.3
        /// How fast the indicator rises relative to the chat.
        static let indicatorFollow: CGFloat = 0.3
        /// Gap between the indicator, before it rises, and the top of the bottom chrome.
        static let indicatorSpacing: CGFloat = 4
        static let springBackDuration: TimeInterval = 0.35
        static let commitDuration: TimeInterval = 0.2
        /// How long the new tab gets to appear before the old chat is put back anyway.
        static let newTabTimeout: TimeInterval = 1
    }

    /// What decides, when a pan begins, whether it may start a new chat.
    struct Eligibility: Equatable {
        var isFeatureEnabled: Bool
        var isPhone: Bool
        var hasChat: Bool
        var isKeyboardVisible: Bool
        var isGenerating: Bool
        var isVoiceSessionActive: Bool
        var isInputHidden: Bool
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
            && !isVoiceSessionActive
            && !isInputHidden
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
        /// `distance` is how far past the bottom the finger has pulled; `progress` is that toward the trigger, from 0 to 1.
        case pull(distance: CGFloat, progress: CGFloat, isArmed: Bool)
        /// The pull reached a new step on its way to the trigger; `step` runs from 1 to `hapticSteps - 1`.
        case tick(step: Int)
        /// The pull reached the trigger; releasing now starts a new chat.
        case arm
        case springBack
        case startNewChat
    }

    enum Pull: Equatable {
        case idle
        /// Eligible, waiting for the chat to reach its bottom.
        case tracking
        /// At the bottom; the pull is measured upward from `baseline`, and has reached `step`.
        case pulling(baseline: CGFloat, step: Int)
        /// Pulled past the threshold; releasing starts a new chat.
        case armed(baseline: CGFloat)

        mutating func handle(_ event: Event) -> [Effect] {
            switch (self, event) {
            case (_, .began(let isEligible)):
                self = isEligible ? .tracking : .idle
                return isEligible ? [.checkAtBottom] : []

            case (.tracking, .reachedBottom(let translation)):
                self = .pulling(baseline: translation, step: 0)
                return []

            case (.tracking, .moved):
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

            case (.tracking, .ended), (.tracking, .cancelled):
                self = .idle
                return []

            case (.idle, _), (.pulling, .reachedBottom), (.armed, .reachedBottom):
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

    /// From release to the new chat's tab showing: the old chat fades out, then a new tab is asked for. The old
    /// tab is put back as it was once it goes off screen, or after a timeout if the new tab never comes; anything
    /// unexpected before the request puts it back without one.
    enum Commit: Equatable {
        case idle
        /// The old chat is fading out; no new tab has been asked for yet.
        case leaving(chatID: String)
        /// A new tab was asked for; the old chat stays hidden until its tab goes off screen.
        case awaitingNewTab

        enum Event: Equatable {
            case released(chatID: String?)
            /// The fade finished; `chatID` and `isEligible` are as they are now, not as they were at release.
            case fadedOut(chatID: String?, isEligible: Bool)
            case urlChanged(chatID: String?)
            case timedOut
            /// The tab went off screen, or the interaction was otherwise abandoned.
            case cancelled
        }

        enum Effect: Equatable {
            case fadeOut
            case requestNewChat
            case scheduleTimeout
            /// Put the old chat back as it was.
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
