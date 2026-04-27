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
    var isEligibleForNTPAfterIdleResult = true
    var effectiveAfterInactivityOptionResult: AfterInactivityOption = .newTab
    var idleThresholdSecondsResult = 300

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

    func makeEvaluator(
        featureOn: Bool = true,
        settingsJSON: String? = "{\"idleThresholdSeconds\": 60}",
        eligibilityManager: IdleReturnEligibilityManaging? = nil
    ) -> IdleReturnEvaluator {
        let mockConfig = MockPrivacyConfiguration()
        mockConfig.subfeatureSettings = settingsJSON
        let mockManager = MockPrivacyConfigurationManager()
        mockManager.privacyConfig = mockConfig
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: featureOn ? [.showNTPAfterIdleReturn] : [])
        return IdleReturnEvaluator(
            featureFlagger: featureFlagger,
            privacyConfigurationManager: mockManager,
            idleReturnEligibilityManager: eligibilityManager
        )
    }

    @Test("When feature is off then didReturnAfterIdle returns false")
    func whenFeatureOffThenReturnsFalse() {
        let evaluator = makeEvaluator(featureOn: false)
        let date = Date().addingTimeInterval(-61)
        #expect(!evaluator.didReturnAfterIdle(lastBackgroundDate: date))
    }

    @Test("When lastBackgroundDate is nil then didReturnAfterIdle returns false")
    func whenLastBackgroundDateNilThenReturnsFalse() {
        let evaluator = makeEvaluator()
        #expect(!evaluator.didReturnAfterIdle(lastBackgroundDate: nil))
    }

    @Test("When under threshold then didReturnAfterIdle returns false")
    func whenUnderThresholdThenReturnsFalse() {
        let evaluator = makeEvaluator(settingsJSON: "{\"idleThresholdSeconds\": 120}")
        let oneHourAgo = Date().addingTimeInterval(-110)
        #expect(!evaluator.didReturnAfterIdle(lastBackgroundDate: oneHourAgo))
    }

    @Test("When over threshold then didReturnAfterIdle returns true")
    func whenOverThresholdThenReturnsTrue() {
        let evaluator = makeEvaluator(settingsJSON: "{\"idleThresholdSeconds\": 120}")
        let twoHoursAgo = Date().addingTimeInterval(-121)
        #expect(evaluator.didReturnAfterIdle(lastBackgroundDate: twoHoursAgo))
    }

    @Test("When at exactly threshold then didReturnAfterIdle returns true")
    func whenAtThresholdThenReturnsTrue() {
        let evaluator = makeEvaluator(settingsJSON: "{\"idleThresholdSeconds\": 120}")
        let oneMinuteAgo = Date().addingTimeInterval(-120)
        #expect(evaluator.didReturnAfterIdle(lastBackgroundDate: oneMinuteAgo))
    }

    @Test("When settings missing then uses default threshold and returns true for 300+s idle")
    func whenSettingsMissingThenUsesDefaultThreshold() {
        let evaluator = makeEvaluator(settingsJSON: nil)
        let fiveMinutesAgo = Date().addingTimeInterval(-300)
        #expect(evaluator.didReturnAfterIdle(lastBackgroundDate: fiveMinutesAgo))
        let justUnderFiveMinutes = Date().addingTimeInterval(-299)
        #expect(!evaluator.didReturnAfterIdle(lastBackgroundDate: justUnderFiveMinutes))
    }

    @Test("When settings invalid JSON then uses default threshold")
    func whenSettingsInvalidThenUsesDefaultThreshold() {
        let evaluator = makeEvaluator(settingsJSON: "not json")
        let fiveMinutesAgo = Date().addingTimeInterval(-300)
        #expect(evaluator.didReturnAfterIdle(lastBackgroundDate: fiveMinutesAgo))
        let justUnderFiveMinutes = Date().addingTimeInterval(-299)
        #expect(!evaluator.didReturnAfterIdle(lastBackgroundDate: justUnderFiveMinutes))
    }

    @Test("When idleThresholdSeconds missing in settings then uses default")
    func whenIdleThresholdSecondsMissingThenUsesDefault() {
        let evaluator = makeEvaluator(settingsJSON: "{}")
        let fiveMinutesAgo = Date().addingTimeInterval(-300)
        #expect(evaluator.didReturnAfterIdle(lastBackgroundDate: fiveMinutesAgo))
        let justUnderFiveMinutes = Date().addingTimeInterval(-299)
        #expect(!evaluator.didReturnAfterIdle(lastBackgroundDate: justUnderFiveMinutes))
    }

    @Test("When eligibility manager returns true then treatmentForIdleReturn is .ntp")
    func whenEligibleThenTreatmentIsNTP() {
        let mockEligibility = MockIdleReturnEligibilityManager()
        mockEligibility.isEligibleForNTPAfterIdleResult = true
        let evaluator = makeEvaluator(eligibilityManager: mockEligibility)
        #expect(evaluator.treatmentForIdleReturn() == .ntp)
    }

    @Test("When eligibility manager returns false then treatmentForIdleReturn is .lut")
    func whenNotEligibleThenTreatmentIsLUT() {
        let mockEligibility = MockIdleReturnEligibilityManager()
        mockEligibility.isEligibleForNTPAfterIdleResult = false
        let evaluator = makeEvaluator(eligibilityManager: mockEligibility)
        #expect(evaluator.treatmentForIdleReturn() == .lut)
    }

    @Test("When no eligibility manager provided then treatmentForIdleReturn defaults to .ntp")
    func whenNoEligibilityManagerThenTreatmentIsNTP() {
        let evaluator = makeEvaluator(eligibilityManager: nil)
        #expect(evaluator.treatmentForIdleReturn() == .ntp)
    }
}
