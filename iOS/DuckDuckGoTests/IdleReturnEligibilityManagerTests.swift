//
//  IdleReturnEligibilityManagerTests.swift
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
import Testing
import Core
import Persistence
import PersistenceTestingUtils
import PrivacyConfig
@testable import DuckDuckGo

private final class MockEffectiveOptionResolver: AfterInactivityEffectiveOptionResolving {
    var resolveEffectiveOptionResult: AfterInactivityOption = .newTab

    func resolveEffectiveOption() -> AfterInactivityOption {
        resolveEffectiveOptionResult
    }
}

@Suite("Idle Return Eligibility Manager")
struct IdleReturnEligibilityManagerTests {

    private func makeThresholdResolver(seconds: Int = 60) -> IdleReturnThresholdResolver {
        let mockConfig = MockPrivacyConfiguration()
        mockConfig.subfeatureSettings = "{\"idleThresholdSeconds\": \(seconds)}"
        let mockManager = MockPrivacyConfigurationManager()
        mockManager.privacyConfig = mockConfig
        let emptyDebugStorage: any KeyedStoring<IdleReturnDebugOverridesKeys> =
            MockKeyValueStore().keyedStoring()
        return IdleReturnThresholdResolver(
            privacyConfigurationManager: mockManager,
            debugOverridesStorage: emptyDebugStorage
        )
    }

    private func makeManager(
        featureOn: Bool = true,
        effectiveOption: AfterInactivityOption = .newTab,
        thresholdSeconds: Int = 60,
        hasSeenOnboarding: Bool = true,
        isStillOnboarding: Bool = false
    ) -> IdleReturnEligibilityManager {
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: featureOn ? [.showNTPAfterIdleReturn] : [])
        let effectiveResolver = MockEffectiveOptionResolver()
        effectiveResolver.resolveEffectiveOptionResult = effectiveOption
        let thresholdResolver = makeThresholdResolver(seconds: thresholdSeconds)
        return IdleReturnEligibilityManager(
            featureFlagger: featureFlagger,
            effectiveOptionResolver: effectiveResolver,
            thresholdResolver: thresholdResolver,
            tutorialSettings: MockTutorialSettings(hasSeenOnboarding: hasSeenOnboarding),
            isStillOnboarding: { isStillOnboarding }
        )
    }

    @Test("When all conditions met then isEligibleForNTPAfterIdle returns true")
    func whenAllConditionsMetThenIsEligibleReturnsTrue() {
        let manager = makeManager(featureOn: true, effectiveOption: .newTab)
        #expect(manager.isEligibleForNTPAfterIdle())
    }

    @Test("When feature is off then isEligibleForNTPAfterIdle returns false")
    func whenFeatureOffThenIsEligibleReturnsFalse() {
        let manager = makeManager(featureOn: false, effectiveOption: .newTab)
        #expect(!manager.isEligibleForNTPAfterIdle())
    }

    @Test("When effective option is Last Used Tab then isEligibleForNTPAfterIdle returns false")
    func whenEffectiveOptionIsLastUsedTabThenIsEligibleReturnsFalse() {
        let manager = makeManager(featureOn: true, effectiveOption: .lastUsedTab)
        #expect(!manager.isEligibleForNTPAfterIdle())
    }

    @Test("When linear onboarding has not been seen then isEligibleForNTPAfterIdle returns false")
    func whenLinearOnboardingNotSeenThenIsEligibleReturnsFalse() {
        let manager = makeManager(featureOn: true, effectiveOption: .newTab, hasSeenOnboarding: false)
        #expect(!manager.isEligibleForNTPAfterIdle())
    }

    @Test("When contextual onboarding is still active then isEligibleForNTPAfterIdle returns false")
    func whenContextualOnboardingActiveReturnsFalse() {
        let manager = makeManager(featureOn: true, effectiveOption: .newTab, isStillOnboarding: true)
        #expect(!manager.isEligibleForNTPAfterIdle())
    }

    @Test("When contextual onboarding is done then isEligibleForNTPAfterIdle returns true")
    func whenContextualOnboardingDoneReturnsTrue() {
        let manager = makeManager(featureOn: true, effectiveOption: .newTab, isStillOnboarding: false)
        #expect(manager.isEligibleForNTPAfterIdle())
    }

    @Test("effectiveAfterInactivityOption returns value from resolver")
    func effectiveAfterInactivityOptionReturnsValueFromResolver() {
        let managerNewTab = makeManager(effectiveOption: .newTab)
        #expect(managerNewTab.effectiveAfterInactivityOption() == .newTab)

        let managerLastUsed = makeManager(effectiveOption: .lastUsedTab)
        #expect(managerLastUsed.effectiveAfterInactivityOption() == .lastUsedTab)
    }

    @Test("idleThresholdSeconds returns value from threshold resolver")
    func idleThresholdSecondsReturnsValueFromThresholdResolver() {
        let manager = makeManager(thresholdSeconds: 120)
        #expect(manager.idleThresholdSeconds() == 120)
    }
}
