//
//  IdleReturnEvaluatorTests.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Testing
import Core
@_spi(Testing) import Persistence
import PrivacyConfig
@testable import DuckDuckGo

final class MockIdleReturnEligibilityManager: IdleReturnEligibilityManaging {
    var isFeatureAvailableResult = true
    var isEligibleForNTPAfterIdleResult = true
    var effectiveAfterInactivityOptionResult: AfterInactivityOption = .newTab
    var idleThresholdSecondsResult = 300
    var ntpAfterIdleStateResult: NTPAfterIdleState = .eligibleCardShown

    func isFeatureAvailable() -> Bool {
        isFeatureAvailableResult
    }

    func isEligibleForNTPAfterIdle() -> Bool {
        isEligibleForNTPAfterIdleResult
    }

    func effectiveAfterInactivityOption() -> AfterInactivityOption {
        effectiveAfterInactivityOptionResult
    }

    func idleThresholdSeconds() -> Int {
        idleThresholdSecondsResult
    }

    func ntpAfterIdleState() -> NTPAfterIdleState {
        ntpAfterIdleStateResult
    }
}

@MainActor
final class IdleReturnEvaluatorTests {

    private static let now = Date(timeIntervalSince1970: 1_000_000)

    private func makeEvaluator(
        featureAvailable: Bool = true,
        thresholdSeconds: Int = 60,
        effectiveOption: AfterInactivityOption = .newTab,
        secondsSinceLastBackground: TimeInterval? = nil
    ) -> IdleReturnEvaluator {
        let eligibility = MockIdleReturnEligibilityManager()
        eligibility.isFeatureAvailableResult = featureAvailable
        eligibility.idleThresholdSecondsResult = thresholdSeconds
        eligibility.effectiveAfterInactivityOptionResult = effectiveOption

        let storage: any ThrowingKeyedStoring<IdleReturnLastBackgroundDateKeys> = InMemoryThrowingKeyValueStore().throwingKeyedStoring()
        if let secondsSinceLastBackground {
            try? storage.set(Self.now.addingTimeInterval(-secondsSinceLastBackground), for: \.lastBackgroundDate)
        }

        return IdleReturnEvaluator(eligibilityManager: eligibility,
                                   lastBackgroundDateStorage: storage,
                                   now: { Self.now })
    }

    @available(iOS 16, *)
    @Test("When feature is unavailable then the return is ordinary", .timeLimit(.minutes(1)))
    func whenFeatureUnavailableThenReturnsFalse() {
        let evaluator = makeEvaluator(featureAvailable: false, secondsSinceLastBackground: 61)
        #expect(evaluator.evaluateReturn() == .ordinary(timeAwayMs: 61_000))
    }

    @available(iOS 16, *)
    @Test("When no background date is stored then the return is ordinary", .timeLimit(.minutes(1)))
    func whenNoStoredBackgroundDateThenReturnsFalse() {
        let evaluator = makeEvaluator()
        #expect(evaluator.evaluateReturn() == .ordinary(timeAwayMs: nil))
    }

    @available(iOS 16, *)
    @Test("When under threshold then the return is ordinary", .timeLimit(.minutes(1)))
    func whenUnderThresholdThenReturnsFalse() {
        let evaluator = makeEvaluator(thresholdSeconds: 120, secondsSinceLastBackground: 110)
        #expect(evaluator.evaluateReturn() == .ordinary(timeAwayMs: 110_000))
    }

    @available(iOS 16, *)
    @Test("When over threshold then the return is after idle", .timeLimit(.minutes(1)))
    func whenOverThresholdThenReturnsTrue() {
        let evaluator = makeEvaluator(thresholdSeconds: 120, secondsSinceLastBackground: 121)
        #expect(evaluator.evaluateReturn() == .afterIdle(treatment: .ntp, timeAwayMs: 121_000))
    }

    @available(iOS 16, *)
    @Test("When at exactly threshold then the return is after idle", .timeLimit(.minutes(1)))
    func whenAtThresholdThenReturnsTrue() {
        let evaluator = makeEvaluator(thresholdSeconds: 120, secondsSinceLastBackground: 120)
        #expect(evaluator.evaluateReturn() == .afterIdle(treatment: .ntp, timeAwayMs: 120_000))
    }

    @available(iOS 16, *)
    @Test("When no background date is stored then timeAwayMs is nil", .timeLimit(.minutes(1)))
    func whenNoStoredBackgroundDateThenTimeAwayIsNil() {
        let evaluator = makeEvaluator()
        #expect(evaluator.evaluateReturn().timeAwayMs == nil)
    }

    @available(iOS 16, *)
    @Test("timeAwayMs reports the gap since the stored background date", .timeLimit(.minutes(1)))
    func timeAwayMsReportsGap() {
        let evaluator = makeEvaluator(secondsSinceLastBackground: 90)
        #expect(evaluator.evaluateReturn().timeAwayMs == 90_000)
    }

    @available(iOS 16, *)
    @Test("timeAwayMs is reported even when the return did not qualify as idle", .timeLimit(.minutes(1)))
    func timeAwayMsReportedForOrdinaryReturn() {
        let evaluator = makeEvaluator(thresholdSeconds: 120, secondsSinceLastBackground: 30)
        #expect(evaluator.evaluateReturn() == .ordinary(timeAwayMs: 30_000))
    }

    @available(iOS 16, *)
    @Test("When effective option is .newTab then the treatment is .ntp", .timeLimit(.minutes(1)))
    func whenEffectiveOptionIsNewTabThenTreatmentIsNTP() {
        let evaluator = makeEvaluator(effectiveOption: .newTab, secondsSinceLastBackground: 61)
        #expect(evaluator.evaluateReturn() == .afterIdle(treatment: .ntp, timeAwayMs: 61_000))
    }

    @available(iOS 16, *)
    @Test("When effective option is .lastUsedTab then the treatment is .lut", .timeLimit(.minutes(1)))
    func whenEffectiveOptionIsLastUsedTabThenTreatmentIsLUT() {
        let evaluator = makeEvaluator(effectiveOption: .lastUsedTab, secondsSinceLastBackground: 61)
        #expect(evaluator.evaluateReturn() == .afterIdle(treatment: .lut, timeAwayMs: 61_000))
    }

    @available(iOS 16, *)
    @Test("A return marked as landed at launch is reported as landed", .timeLimit(.minutes(1)))
    func markedReturnIsReportedAsLanded() {
        let evaluator = makeEvaluator(secondsSinceLastBackground: 61)

        evaluator.markReturnLandedAtLaunch()

        #expect(evaluator.evaluateReturn() == .landedAtLaunch(timeAwayMs: 61_000))
        #expect(evaluator.evaluateReturn().isAfterIdle)
    }

    @available(iOS 16, *)
    @Test("A mark does not carry over to the next time the app is backgrounded", .timeLimit(.minutes(1)))
    func markDoesNotCarryOverToTheNextBackground() throws {
        let storage: any ThrowingKeyedStoring<IdleReturnLastBackgroundDateKeys> = InMemoryThrowingKeyValueStore().throwingKeyedStoring()
        try storage.set(Self.now.addingTimeInterval(-600), for: \.lastBackgroundDate)
        let evaluator = IdleReturnEvaluator(eligibilityManager: MockIdleReturnEligibilityManager(),
                                            lastBackgroundDateStorage: storage,
                                            now: { Self.now })
        evaluator.markReturnLandedAtLaunch()

        try storage.set(Self.now.addingTimeInterval(-400), for: \.lastBackgroundDate)

        #expect(evaluator.evaluateReturn() == .afterIdle(treatment: .ntp, timeAwayMs: 400_000))
    }

    @available(iOS 16, *)
    @Test("A marked return is ordinary once the feature is unavailable", .timeLimit(.minutes(1)))
    func markedReturnIsOrdinaryWhenFeatureUnavailable() {
        let evaluator = makeEvaluator(featureAvailable: false, secondsSinceLastBackground: 61)

        evaluator.markReturnLandedAtLaunch()

        #expect(evaluator.evaluateReturn() == .ordinary(timeAwayMs: 61_000))
    }
}
