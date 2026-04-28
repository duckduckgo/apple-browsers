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
import PrivacyConfig
@testable import DuckDuckGo

final class MockIdleReturnEligibilityManager: IdleReturnEligibilityManaging {
    var isFeatureAvailableResult = true
    var isEligibleForNTPAfterIdleResult = true
    var effectiveAfterInactivityOptionResult: AfterInactivityOption = .newTab
    var idleThresholdSecondsResult = 300

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
}

@MainActor
final class IdleReturnEvaluatorTests {

    private func makeEligibility(
        featureAvailable: Bool = true,
        thresholdSeconds: Int = 60,
        effectiveOption: AfterInactivityOption = .newTab
    ) -> MockIdleReturnEligibilityManager {
        let mock = MockIdleReturnEligibilityManager()
        mock.isFeatureAvailableResult = featureAvailable
        mock.idleThresholdSecondsResult = thresholdSeconds
        mock.effectiveAfterInactivityOptionResult = effectiveOption
        return mock
    }

    @Test("When feature is unavailable then didReturnAfterIdle returns false")
    func whenFeatureUnavailableThenReturnsFalse() {
        let evaluator = IdleReturnEvaluator(eligibilityManager: makeEligibility(featureAvailable: false))
        let date = Date().addingTimeInterval(-61)
        #expect(!evaluator.didReturnAfterIdle(lastBackgroundDate: date))
    }

    @Test("When lastBackgroundDate is nil then didReturnAfterIdle returns false")
    func whenLastBackgroundDateNilThenReturnsFalse() {
        let evaluator = IdleReturnEvaluator(eligibilityManager: makeEligibility())
        #expect(!evaluator.didReturnAfterIdle(lastBackgroundDate: nil))
    }

    @Test("When under threshold then didReturnAfterIdle returns false")
    func whenUnderThresholdThenReturnsFalse() {
        let evaluator = IdleReturnEvaluator(eligibilityManager: makeEligibility(thresholdSeconds: 120))
        let underThreshold = Date().addingTimeInterval(-110)
        #expect(!evaluator.didReturnAfterIdle(lastBackgroundDate: underThreshold))
    }

    @Test("When over threshold then didReturnAfterIdle returns true")
    func whenOverThresholdThenReturnsTrue() {
        let evaluator = IdleReturnEvaluator(eligibilityManager: makeEligibility(thresholdSeconds: 120))
        let overThreshold = Date().addingTimeInterval(-121)
        #expect(evaluator.didReturnAfterIdle(lastBackgroundDate: overThreshold))
    }

    @Test("When at exactly threshold then didReturnAfterIdle returns true")
    func whenAtThresholdThenReturnsTrue() {
        let evaluator = IdleReturnEvaluator(eligibilityManager: makeEligibility(thresholdSeconds: 120))
        let atThreshold = Date().addingTimeInterval(-120)
        #expect(evaluator.didReturnAfterIdle(lastBackgroundDate: atThreshold))
    }

    @Test("When effective option is .newTab then treatmentForIdleReturn is .ntp")
    func whenEffectiveOptionIsNewTabThenTreatmentIsNTP() {
        let evaluator = IdleReturnEvaluator(eligibilityManager: makeEligibility(effectiveOption: .newTab))
        #expect(evaluator.treatmentForIdleReturn() == .ntp)
    }

    @Test("When effective option is .lastUsedTab then treatmentForIdleReturn is .lut")
    func whenEffectiveOptionIsLastUsedTabThenTreatmentIsLUT() {
        let evaluator = IdleReturnEvaluator(eligibilityManager: makeEligibility(effectiveOption: .lastUsedTab))
        #expect(evaluator.treatmentForIdleReturn() == .lut)
    }
}
