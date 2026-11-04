//
//  DuckAISwipeNewChatTests.swift
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
import Testing
@testable import DuckDuckGo

@Suite("Duck.ai swipe up for a new chat")
struct DuckAISwipeNewChatTests {

    typealias Pull = DuckAISwipeNewChat.Pull
    typealias Eligibility = DuckAISwipeNewChat.Eligibility

    private let threshold = DuckAISwipeNewChat.Constants.triggerDistance

    /// Runs `events` from idle and returns every effect, in order.
    private func run(_ events: [DuckAISwipeNewChat.Event]) -> (pull: Pull, effects: [DuckAISwipeNewChat.Effect]) {
        var pull = Pull.idle
        let effects = events.flatMap { pull.handle($0) }
        return (pull, effects)
    }

    private func startNewChatCount(_ effects: [DuckAISwipeNewChat.Effect]) -> Int {
        effects.filter { $0 == .startNewChat }.count
    }

    // MARK: - Pull

    @available(iOS 16, macOS 13, *)
    @Test("Releasing below the threshold does not start a new chat", .timeLimit(.minutes(1)))
    func releaseBelowThresholdDoesNotTrigger() {
        let result = run([.began(isEligible: true), .reachedBottom(translation: 0), .moved(translation: -(threshold - 1)), .ended])
        #expect(startNewChatCount(result.effects) == 0)
        #expect(!result.effects.contains(.haptic))
        #expect(result.effects.last == .hideHint)
        #expect(result.pull == .idle)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Releasing past the threshold starts exactly one new chat, with one haptic", .timeLimit(.minutes(1)))
    func releasePastThresholdTriggersOnce() {
        let result = run([.began(isEligible: true),
                          .reachedBottom(translation: 0),
                          .moved(translation: -threshold),
                          .moved(translation: -(threshold + 40)),
                          .ended,
                          .ended])
        #expect(startNewChatCount(result.effects) == 1)
        #expect(result.effects.filter { $0 == .haptic }.count == 1)
        #expect(result.effects.contains(.showHint(progress: 1, isArmed: true)))
        #expect(result.pull == .idle)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Dropping back below the threshold before release disarms", .timeLimit(.minutes(1)))
    func droppingBackBelowThresholdDisarms() {
        let result = run([.began(isEligible: true),
                          .reachedBottom(translation: 0),
                          .moved(translation: -threshold),
                          .moved(translation: -(threshold / 2)),
                          .ended])
        #expect(startNewChatCount(result.effects) == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The pull is measured from where the chat reached its bottom mid-drag", .timeLimit(.minutes(1)))
    func reachingBottomMidDragUsesNewBaseline() {
        let bottomAt: CGFloat = -300
        let short = run([.began(isEligible: true),
                         .moved(translation: bottomAt),
                         .reachedBottom(translation: bottomAt),
                         .moved(translation: bottomAt - (threshold - 1)),
                         .ended])
        #expect(startNewChatCount(short.effects) == 0)

        let full = run([.began(isEligible: true),
                        .moved(translation: bottomAt),
                        .reachedBottom(translation: bottomAt),
                        .moved(translation: bottomAt - threshold),
                        .ended])
        #expect(startNewChatCount(full.effects) == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Scrolling that never reaches the bottom only asks the page, and shows no hint", .timeLimit(.minutes(1)))
    func notAtBottomNeverShowsHint() {
        let result = run([.began(isEligible: true), .moved(translation: -500), .moved(translation: -900), .ended])
        #expect(result.effects == [.checkAtBottom, .checkAtBottom, .checkAtBottom])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Cancelling an armed pull hides the hint, starts nothing and resets", .timeLimit(.minutes(1)))
    func cancelResets() {
        var pull = Pull.idle
        _ = pull.handle(.began(isEligible: true))
        _ = pull.handle(.reachedBottom(translation: 0))
        _ = pull.handle(.moved(translation: -threshold))
        #expect(pull == .armed(baseline: 0))

        #expect(pull.handle(.cancelled) == [.hideHint])
        #expect(pull == .idle)
        #expect(pull.handle(.ended).isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A new pan starts over, without the previous pull's baseline", .timeLimit(.minutes(1)))
    func newPanStartsOver() {
        let result = run([.began(isEligible: true),
                          .reachedBottom(translation: 0),
                          .moved(translation: -(threshold - 1)),
                          .began(isEligible: true),
                          .moved(translation: -threshold),
                          .ended])
        #expect(startNewChatCount(result.effects) == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("An ineligible pan never arms, even if the page reports the bottom", .timeLimit(.minutes(1)))
    func ineligiblePanNeverArms() {
        let result = run([.began(isEligible: false),
                          .reachedBottom(translation: 0),
                          .moved(translation: -(threshold * 3)),
                          .ended])
        #expect(result.effects.isEmpty)
    }

    // MARK: - Eligibility

    private static let eligible = Eligibility(isFeatureEnabled: true,
                                              isPhone: true,
                                              hasChat: true,
                                              isKeyboardVisible: false,
                                              isGenerating: false,
                                              panVelocity: CGPoint(x: 10, y: -400),
                                              startY: 500,
                                              bottomInsetMinY: 800)

    @available(iOS 16, macOS 13, *)
    @Test("A vertical pan on a chat with nothing in the way is eligible", .timeLimit(.minutes(1)))
    func baselineIsEligible() {
        #expect(Self.eligible.isEligible)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Each blocking state makes the pan ineligible",
          .timeLimit(.minutes(1)),
          arguments: [
            ("flag off", \Eligibility.isFeatureEnabled, false),
            ("not a phone", \Eligibility.isPhone, false),
            ("no chat ID", \Eligibility.hasChat, false),
            ("keyboard up", \Eligibility.isKeyboardVisible, true),
            ("generating", \Eligibility.isGenerating, true)
          ] as [(String, WritableKeyPath<Eligibility, Bool>, Bool)])
    func blockingStateIsIneligible(_ name: String, _ keyPath: WritableKeyPath<Eligibility, Bool>, _ value: Bool) {
        var eligibility = Self.eligible
        eligibility[keyPath: keyPath] = value
        #expect(!eligibility.isEligible, "\(name)")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A mostly horizontal pan is ineligible", .timeLimit(.minutes(1)))
    func horizontalPanIsIneligible() {
        var eligibility = Self.eligible
        eligibility.panVelocity = CGPoint(x: -400, y: -300)
        #expect(!eligibility.isEligible)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A pan starting in the bottom safe-area inset is ineligible", .timeLimit(.minutes(1)))
    func startInBottomInsetIsIneligible() {
        var eligibility = Self.eligible
        eligibility.startY = eligibility.bottomInsetMinY
        #expect(!eligibility.isEligible)
    }
}
