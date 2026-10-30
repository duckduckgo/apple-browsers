//
//  UpdatePromptStageTrackerTests.swift
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

@testable import AppUpdaterShared
import Combine
import Foundation
import FoundationExtensions
@_spi(Testing) import Persistence
import Testing

@MainActor
@Suite("UpdatePromptStageTracker")
final class UpdatePromptStageTrackerTests {

    private let store = InMemoryThrowingKeyValueStore().throwingKeyedStoring() as any ThrowingKeyedStoring<UpdateControllerSettings>
    private let settings = MoreProminentUpdatesSettings(hoursUntilFirstPrompt: 48, hoursUntilSecondPrompt: 96, hoursUntilAppStoreUpdateAvailable: 24)
    private let day0 = Date(timeIntervalSince1970: 1_800_000_000)
    private lazy var now = day0
    private var scheduled: (delay: TimeInterval, action: () -> Void)?
    private let becomeActive = PassthroughSubject<Void, Never>()

    private func makeTracker(installedVersion: String = "1.0.0 (100)", reevaluationTriggers: AnyPublisher<Void, Never>? = nil) -> UpdatePromptStageTracker {
        UpdatePromptStageTracker(store: store,
                                 settings: { [settings] in settings },
                                 installedVersion: installedVersion,
                                 now: { [unowned self] in now },
                                 schedule: { [unowned self] delay, action in
                                     scheduled = (delay, action)
                                     return AnyCancellable { [unowned self] in scheduled = nil }
                                 },
                                 reevaluationTriggers: reevaluationTriggers ?? becomeActive.eraseToAnyPublisher())
    }

    private func advance(by interval: TimeInterval) {
        now += interval
    }

    private func fireScheduledReevaluation() throws {
        let action = try #require(scheduled).action
        action()
    }

    @available(iOS 16, macOS 13, *)
    @Test("Shows no stage and starts no clock when no update is available", .timeLimit(.minutes(1)))
    func noUpdate() {
        let tracker = makeTracker()

        tracker.updateCheckDidFinish(isUpdateAvailable: false, isCritical: false)

        #expect(tracker.stage == .none)
        #expect(tracker.clockStartDate == nil)
        #expect(scheduled == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Ramps from available to the first and second prompts at the configured thresholds", .timeLimit(.minutes(1)))
    func rampsThroughStages() throws {
        let tracker = makeTracker()

        tracker.updateCheckDidFinish(isUpdateAvailable: true, isCritical: false)
        #expect(tracker.stage == .available)
        #expect(tracker.clockStartDate == day0)
        #expect(scheduled?.delay == .hours(48))

        advance(by: .hours(48))
        try fireScheduledReevaluation()
        #expect(tracker.stage == .firstPrompt)
        #expect(scheduled?.delay == .hours(48))

        advance(by: .hours(48))
        try fireScheduledReevaluation()
        #expect(tracker.stage == .secondPrompt)
        #expect(scheduled == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Schedules the next threshold from the time already elapsed", .timeLimit(.minutes(1)))
    func schedulesRemainingTime() {
        let tracker = makeTracker()
        tracker.updateCheckDidFinish(isUpdateAvailable: true, isCritical: false)

        advance(by: .hours(60))
        tracker.updateCheckDidFinish(isUpdateAvailable: true, isCritical: false)

        #expect(tracker.stage == .firstPrompt)
        #expect(scheduled?.delay == .hours(36))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Later checks that find an update, including newer releases, don't restart the clock", .timeLimit(.minutes(1)))
    func laterChecksKeepClock() {
        let tracker = makeTracker()
        tracker.updateCheckDidFinish(isUpdateAvailable: true, isCritical: false)

        advance(by: .hours(100))
        tracker.updateCheckDidFinish(isUpdateAvailable: true, isCritical: false)

        #expect(tracker.clockStartDate == day0)
        #expect(tracker.stage == .secondPrompt)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The clock survives a relaunch on the same version", .timeLimit(.minutes(1)))
    func clockSurvivesRelaunch() {
        makeTracker().updateCheckDidFinish(isUpdateAvailable: true, isCritical: false)
        advance(by: .hours(50))

        let relaunched = makeTracker()
        #expect(relaunched.stage == .none, "no stage until a check confirms the update is still available")

        relaunched.updateCheckDidFinish(isUpdateAvailable: true, isCritical: false)
        #expect(relaunched.clockStartDate == day0)
        #expect(relaunched.stage == .firstPrompt)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Updating the app clears the clock, and the next update found starts a new one", .timeLimit(.minutes(1)))
    func updatingClearsClock() {
        makeTracker(installedVersion: "1.0.0 (100)").updateCheckDidFinish(isUpdateAvailable: true, isCritical: false)
        advance(by: .hours(100))

        let updated = makeTracker(installedVersion: "1.1.0 (110)")
        #expect(updated.clockStartDate == nil)

        updated.updateCheckDidFinish(isUpdateAvailable: true, isCritical: false)
        #expect(updated.clockStartDate == now)
        #expect(updated.stage == .available)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A check that no longer finds the update clears the clock, so a republished update starts again from day 0", .timeLimit(.minutes(1)))
    func withdrawnUpdateClearsClock() {
        let tracker = makeTracker()
        tracker.updateCheckDidFinish(isUpdateAvailable: true, isCritical: false)
        advance(by: .hours(50))

        tracker.updateCheckDidFinish(isUpdateAvailable: false, isCritical: false)
        #expect(tracker.stage == .none)
        #expect(tracker.clockStartDate == nil)
        #expect(scheduled == nil)

        advance(by: .hours(10))
        tracker.updateCheckDidFinish(isUpdateAvailable: true, isCritical: false)
        #expect(tracker.clockStartDate == now)
        #expect(tracker.stage == .available)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Critical updates go straight to the second prompt", .timeLimit(.minutes(1)))
    func criticalUpdateSkipsRamp() {
        let tracker = makeTracker()

        tracker.updateCheckDidFinish(isUpdateAvailable: true, isCritical: true)

        #expect(tracker.stage == .secondPrompt)
        #expect(scheduled == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A clock start in the future is clamped to now", .timeLimit(.minutes(1)))
    func futureClockStartIsClamped() {
        let tracker = makeTracker()
        tracker.updateCheckDidFinish(isUpdateAvailable: true, isCritical: false)

        advance(by: -.hours(72))
        tracker.reevaluate()

        #expect(tracker.clockStartDate == now)
        #expect(tracker.stage == .available)
        #expect(scheduled?.delay == .hours(48))
    }

    @available(iOS 16, macOS 13, *)
    @Test("Becoming active catches up on a threshold the timer missed, such as during sleep", .timeLimit(.minutes(1)))
    func becomingActiveReevaluates() {
        let tracker = makeTracker()
        tracker.updateCheckDidFinish(isUpdateAvailable: true, isCritical: false)

        advance(by: .hours(97))
        becomeActive.send()

        #expect(tracker.stage == .secondPrompt)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A trigger sent from a background thread re-evaluates on the main thread", .timeLimit(.minutes(1)))
    func backgroundTriggerReevaluatesOnMain() async {
        let tracker = makeTracker(reevaluationTriggers: becomeActive.receive(on: DispatchQueue.global()).eraseToAnyPublisher())
        tracker.updateCheckDidFinish(isUpdateAvailable: true, isCritical: false)
        advance(by: .hours(97))
        let reachedSecondPrompt = tracker.$stage.first { $0 == .secondPrompt }.values

        becomeActive.send()
        for await _ in reachedSecondPrompt {}

        #expect(tracker.stage == .secondPrompt)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Each threshold starts its stage", .timeLimit(.minutes(1)), arguments: [
        (TimeInterval.hours(48) - 1, UpdatePromptStage.available),
        (.hours(48), .firstPrompt),
        (.hours(96) - 1, .firstPrompt),
        (.hours(96), .secondPrompt)
    ])
    func thresholdBoundaries(elapsed: TimeInterval, expected: UpdatePromptStage) {
        let settings = MoreProminentUpdatesSettings(hoursUntilFirstPrompt: 48, hoursUntilSecondPrompt: 96, hoursUntilAppStoreUpdateAvailable: 24)

        #expect(UpdatePromptStageTracker.stage(afterElapsed: elapsed, settings: settings) == expected)
    }
}
