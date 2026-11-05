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

    private let steps = DuckAISwipeNewChat.Constants.hapticSteps

    private func startNewChatCount(_ effects: [DuckAISwipeNewChat.Effect]) -> Int {
        effects.filter { $0 == .startNewChat }.count
    }

    private func ticks(_ effects: [DuckAISwipeNewChat.Effect]) -> [Int] {
        effects.compactMap { if case .tick(let step) = $0 { step } else { nil } }
    }

    /// A slow pull from the bottom to `distance`, a point at a time.
    private func slowPull(to distance: CGFloat) -> [DuckAISwipeNewChat.Event] {
        [.began(isEligible: true), .reachedBottom(translation: 0)]
            + stride(from: 1, through: distance, by: 1).map { .moved(translation: -$0) }
    }

    // MARK: - Pull

    @available(iOS 16, macOS 13, *)
    @Test("Releasing below the threshold springs back without starting a new chat", .timeLimit(.minutes(1)))
    func releaseBelowThresholdDoesNotTrigger() {
        let result = run([.began(isEligible: true), .reachedBottom(translation: 0), .moved(translation: -(threshold - 1)), .ended])
        #expect(startNewChatCount(result.effects) == 0)
        #expect(!result.effects.contains(.arm))
        #expect(result.effects.last == .springBack)
        #expect(result.pull == .idle)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Releasing past the threshold starts exactly one new chat, armed once", .timeLimit(.minutes(1)))
    func releasePastThresholdTriggersOnce() {
        let result = run([.began(isEligible: true),
                          .reachedBottom(translation: 0),
                          .moved(translation: -threshold),
                          .moved(translation: -(threshold + 40)),
                          .ended,
                          .ended])
        #expect(startNewChatCount(result.effects) == 1)
        #expect(result.effects.filter { $0 == .arm }.count == 1)
        #expect(result.effects.contains(.pull(distance: threshold + 40, progress: 1, isArmed: true)))
        #expect(!result.effects.contains(.springBack))
        #expect(result.pull == .idle)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A slow pull ticks once at each step on the way up, then arms", .timeLimit(.minutes(1)))
    func slowPullTicksEachStepThenArms() {
        let result = run(slowPull(to: threshold + 20))
        #expect(ticks(result.effects) == Array(1..<steps))
        #expect(result.effects.filter { $0 == .arm }.count == 1)
        #expect(result.effects.last { if case .tick = $0 { true } else { $0 == .arm } } == .arm)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Easing back down does not tick; pulling up again ticks and arms again", .timeLimit(.minutes(1)))
    func easingBackDownIsSilent() {
        var pull = Pull.idle
        _ = slowPull(to: threshold).flatMap { pull.handle($0) }

        let down = stride(from: threshold, through: threshold * 0.3, by: -1).flatMap { pull.handle(.moved(translation: -$0)) }
        #expect(ticks(down).isEmpty)
        #expect(!down.contains(.arm))

        let up = stride(from: threshold * 0.3, through: threshold, by: 1).flatMap { pull.handle(.moved(translation: -$0)) }
        #expect(!ticks(up).isEmpty)
        #expect(up.filter { $0 == .arm }.count == 1)
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
        #expect(result.effects.last == .springBack)
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
    @Test("Scrolling that never reaches the bottom only asks the page, and moves nothing", .timeLimit(.minutes(1)))
    func notAtBottomNeverShowsHint() {
        let result = run([.began(isEligible: true), .moved(translation: -500), .moved(translation: -900), .ended])
        #expect(result.effects == [.checkAtBottom, .checkAtBottom, .checkAtBottom])
    }

    @available(iOS 16, macOS 13, *)
    @Test("Cancelling an armed pull springs back, starts nothing and resets", .timeLimit(.minutes(1)))
    func cancelResets() {
        var pull = Pull.idle
        _ = pull.handle(.began(isEligible: true))
        _ = pull.handle(.reachedBottom(translation: 0))
        _ = pull.handle(.moved(translation: -threshold))
        #expect(pull == .armed(baseline: 0))

        #expect(pull.handle(.cancelled) == [.springBack])
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

    // MARK: - Commit

    typealias Commit = DuckAISwipeNewChat.Commit

    /// Releases on chat "old" and lets the fade finish with the chat unchanged and still eligible.
    private func fadedOut() -> Commit {
        var commit = Commit.idle
        _ = commit.handle(.released(chatID: "old"))
        _ = commit.handle(.fadedOut(chatID: "old", isEligible: true))
        return commit
    }

    @available(iOS 16, macOS 13, *)
    @Test("Releasing fades the old chat out before asking the page for anything", .timeLimit(.minutes(1)))
    func releaseFadesOutFirst() {
        var commit = Commit.idle
        #expect(commit.handle(.released(chatID: "old")) == [.fadeOut])
        #expect(commit == .leaving(chatID: "old"))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Once faded out, the page is asked for a new chat and stays hidden until it moves off the old one",
          .timeLimit(.minutes(1)))
    func fadedOutRequestsNewChatThenRevealsOnNewChatID() {
        var commit = Commit.idle
        _ = commit.handle(.released(chatID: "old"))
        #expect(commit.handle(.fadedOut(chatID: "old", isEligible: true)) == [.requestNewChat, .scheduleTimeout])

        #expect(commit.handle(.urlChanged(chatID: "old")).isEmpty)
        #expect(commit.handle(.urlChanged(chatID: nil)) == [.reveal])
        #expect(commit == .idle)
    }

    @available(iOS 16, macOS 13, *)
    @Test("If the page never moves off the old chat, it is shown again when the wait times out", .timeLimit(.minutes(1)))
    func timeoutReveals() {
        var commit = fadedOut()
        #expect(commit.handle(.timedOut) == [.reveal])
        #expect(commit == .idle)
        #expect(commit.handle(.timedOut).isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The tab moving off the chat during the fade puts it back without starting a new chat", .timeLimit(.minutes(1)))
    func chatChangingDuringFadeRestores() {
        var commit = Commit.idle
        _ = commit.handle(.released(chatID: "old"))
        #expect(commit.handle(.urlChanged(chatID: nil)) == [.restore])
        #expect(commit == .idle)
        #expect(commit.handle(.fadedOut(chatID: nil, isEligible: true)).isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A different chat once the fade finishes puts it back without starting a new chat", .timeLimit(.minutes(1)))
    func differentChatAfterFadeRestores() {
        var commit = Commit.idle
        _ = commit.handle(.released(chatID: "old"))
        #expect(commit.handle(.fadedOut(chatID: "other", isEligible: true)) == [.restore])
        #expect(commit == .idle)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Becoming ineligible during the fade puts the chat back without starting a new one", .timeLimit(.minutes(1)))
    func ineligibleAfterFadeRestores() {
        var commit = Commit.idle
        _ = commit.handle(.released(chatID: "old"))
        let effects = commit.handle(.fadedOut(chatID: "old", isEligible: false))
        #expect(effects == [.restore])
        #expect(!effects.contains(.requestNewChat))
        #expect(commit == .idle)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Cancelling at any point puts the chat back, and later events do nothing", .timeLimit(.minutes(1)))
    func cancelRestores() {
        var leaving = Commit.idle
        _ = leaving.handle(.released(chatID: "old"))
        #expect(leaving.handle(.cancelled) == [.restore])
        #expect(leaving.handle(.fadedOut(chatID: "old", isEligible: true)).isEmpty)

        var awaiting = fadedOut()
        #expect(awaiting.handle(.cancelled) == [.restore])
        #expect(awaiting.handle(.urlChanged(chatID: nil)).isEmpty)
        #expect(awaiting.handle(.timedOut).isEmpty)

        var idle = Commit.idle
        #expect(idle.handle(.cancelled).isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Releasing on a page with no chat puts it back", .timeLimit(.minutes(1)))
    func releaseWithoutChatRestores() {
        var commit = Commit.idle
        #expect(commit.handle(.released(chatID: nil)) == [.restore])
        #expect(commit == .idle)
    }

    // MARK: - Eligibility

    private static let eligible = Eligibility(isFeatureEnabled: true,
                                              isPhone: true,
                                              hasChat: true,
                                              isKeyboardVisible: false,
                                              isGenerating: false,
                                              isVoiceSessionActive: false,
                                              isInputHidden: false,
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
            ("generating", \Eligibility.isGenerating, true),
            ("voice session", \Eligibility.isVoiceSessionActive, true),
            ("input hidden by the page", \Eligibility.isInputHidden, true)
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
