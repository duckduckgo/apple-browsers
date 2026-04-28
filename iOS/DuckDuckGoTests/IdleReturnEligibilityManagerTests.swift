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

    @available(iOS 16, *)
    @Test("isFeatureAvailable is true when flag is on and onboarding is complete", .timeLimit(.minutes(1)))
    func isFeatureAvailableTrueWhenAllPreconditionsMet() {
        let manager = makeManager(featureOn: true, hasSeenOnboarding: true, isStillOnboarding: false)
        #expect(manager.isFeatureAvailable())
    }

    @available(iOS 16, *)
    @Test("isFeatureAvailable is independent of effective After-Inactivity option", .timeLimit(.minutes(1)))
    func isFeatureAvailableIgnoresEffectiveOption() {
        let managerNewTab = makeManager(featureOn: true, effectiveOption: .newTab)
        let managerLastUsed = makeManager(featureOn: true, effectiveOption: .lastUsedTab)
        #expect(managerNewTab.isFeatureAvailable())
        #expect(managerLastUsed.isFeatureAvailable())
    }

    @available(iOS 16, *)
    @Test("isFeatureAvailable is false when feature flag is off", .timeLimit(.minutes(1)))
    func isFeatureAvailableFalseWhenFlagOff() {
        let manager = makeManager(featureOn: false)
        #expect(!manager.isFeatureAvailable())
    }

    @available(iOS 16, *)
    @Test("isFeatureAvailable is false when linear onboarding has not been seen", .timeLimit(.minutes(1)))
    func isFeatureAvailableFalseWhenOnboardingNotSeen() {
        let manager = makeManager(featureOn: true, hasSeenOnboarding: false)
        #expect(!manager.isFeatureAvailable())
    }

    @available(iOS 16, *)
    @Test("isFeatureAvailable is false when contextual onboarding still active", .timeLimit(.minutes(1)))
    func isFeatureAvailableFalseWhenContextualOnboardingActive() {
        let manager = makeManager(featureOn: true, isStillOnboarding: true)
        #expect(!manager.isFeatureAvailable())
    }

    @available(iOS 16, *)
    @Test("When all conditions met then isEligibleForNTPAfterIdle returns true", .timeLimit(.minutes(1)))
    func whenAllConditionsMetThenIsEligibleReturnsTrue() {
        let manager = makeManager(featureOn: true, effectiveOption: .newTab)
        #expect(manager.isEligibleForNTPAfterIdle())
    }

    @available(iOS 16, *)
    @Test("When feature is off then isEligibleForNTPAfterIdle returns false", .timeLimit(.minutes(1)))
    func whenFeatureOffThenIsEligibleReturnsFalse() {
        let manager = makeManager(featureOn: false, effectiveOption: .newTab)
        #expect(!manager.isEligibleForNTPAfterIdle())
    }

    @available(iOS 16, *)
    @Test("When effective option is Last Used Tab then isEligibleForNTPAfterIdle returns false", .timeLimit(.minutes(1)))
    func whenEffectiveOptionIsLastUsedTabThenIsEligibleReturnsFalse() {
        let manager = makeManager(featureOn: true, effectiveOption: .lastUsedTab)
        #expect(!manager.isEligibleForNTPAfterIdle())
    }

    @available(iOS 16, *)
    @Test("When linear onboarding has not been seen then isEligibleForNTPAfterIdle returns false", .timeLimit(.minutes(1)))
    func whenLinearOnboardingNotSeenThenIsEligibleReturnsFalse() {
        let manager = makeManager(featureOn: true, effectiveOption: .newTab, hasSeenOnboarding: false)
        #expect(!manager.isEligibleForNTPAfterIdle())
    }

    @available(iOS 16, *)
    @Test("When contextual onboarding is still active then isEligibleForNTPAfterIdle returns false", .timeLimit(.minutes(1)))
    func whenContextualOnboardingActiveReturnsFalse() {
        let manager = makeManager(featureOn: true, effectiveOption: .newTab, isStillOnboarding: true)
        #expect(!manager.isEligibleForNTPAfterIdle())
    }

    @available(iOS 16, *)
    @Test("When contextual onboarding is done then isEligibleForNTPAfterIdle returns true", .timeLimit(.minutes(1)))
    func whenContextualOnboardingDoneReturnsTrue() {
        let manager = makeManager(featureOn: true, effectiveOption: .newTab, isStillOnboarding: false)
        #expect(manager.isEligibleForNTPAfterIdle())
    }

    @available(iOS 16, *)
    @Test("effectiveAfterInactivityOption returns value from resolver", .timeLimit(.minutes(1)))
    func effectiveAfterInactivityOptionReturnsValueFromResolver() {
        let managerNewTab = makeManager(effectiveOption: .newTab)
        #expect(managerNewTab.effectiveAfterInactivityOption() == .newTab)

        let managerLastUsed = makeManager(effectiveOption: .lastUsedTab)
        #expect(managerLastUsed.effectiveAfterInactivityOption() == .lastUsedTab)
    }

    @available(iOS 16, *)
    @Test("idleThresholdSeconds returns value from threshold resolver", .timeLimit(.minutes(1)))
    func idleThresholdSecondsReturnsValueFromThresholdResolver() {
        let manager = makeManager(thresholdSeconds: 120)
        #expect(manager.idleThresholdSeconds() == 120)
    }
}
