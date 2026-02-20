//
//  ContextualDaxDialogsProviderTests.swift
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

import Testing
import Core
@testable import DuckDuckGo

@MainActor
@Suite("Onboarding Tests - ContextualDaxDialogsProvider")
struct ContextualDaxDialogsProviderTests {

    @Test(
        "Check Rebranding Factory is Used When Onboarding Rebranding Feature Flag is On",
        arguments: [DaxDialogs.BrowsingSpec.afterSearch, .visitWebsite, .withoutTrackers, .siteIsMajorTracker, .siteOwnedByMajorTracker, .withOneTracker, .withMultipleTrackers, .fire, .final]
    )
    func checkRebrandingFactoryIsUsedWhenOnboardingRebrandingFlagIsOn(browsingSpec: DaxDialogs.BrowsingSpec) throws {
        // GIVEN
        let featureFlaggerMock = MockFeatureFlagger(enabledFeatureFlags: [.onboardingRebranding])
        let legacyDaxDialogFactoryMock = MockContextualDaxDialogsFactory()
        let rebrandedDaxDialogFactoryMock = MockContextualDaxDialogsFactory()
        let sut = ContextualDaxDialogsProvider(featureFlagger: featureFlaggerMock, legacyDaxDialogsFactory: legacyDaxDialogFactoryMock, rebrandedDaxDialogsFactory: rebrandedDaxDialogFactoryMock)

        // WHEN
        _ = sut.makeView(for: browsingSpec, delegate: ContextualOnboardingDelegateMock(), onSizeUpdate: {})

        // THEN
        #expect(rebrandedDaxDialogFactoryMock.didCallMakeView)
        #expect(rebrandedDaxDialogFactoryMock.capturedSpec == browsingSpec)
        #expect(!legacyDaxDialogFactoryMock.didCallMakeView)
        #expect(legacyDaxDialogFactoryMock.capturedSpec == nil)
    }

    @Test(
        "Check Legacy Factory is Used When Onboarding Rebranding Feature Flag is Off",
        arguments: [DaxDialogs.BrowsingSpec.afterSearch, .visitWebsite, .withoutTrackers, .siteIsMajorTracker, .siteOwnedByMajorTracker, .withOneTracker, .withMultipleTrackers, .fire, .final]
    )
    func checkLegacyFactoryIsUsedWhenOnboardingRebrandingFlagIsOff(browsingSpec: DaxDialogs.BrowsingSpec) throws {
        // GIVEN
        let featureFlaggerMock = MockFeatureFlagger(enabledFeatureFlags: [])
        let legacyDaxDialogFactoryMock = MockContextualDaxDialogsFactory()
        let rebrandedDaxDialogFactoryMock = MockContextualDaxDialogsFactory()
        let sut = ContextualDaxDialogsProvider(featureFlagger: featureFlaggerMock, legacyDaxDialogsFactory: legacyDaxDialogFactoryMock, rebrandedDaxDialogsFactory: rebrandedDaxDialogFactoryMock)

        // WHEN
        _ = sut.makeView(for: browsingSpec, delegate: ContextualOnboardingDelegateMock(), onSizeUpdate: {})

        // THEN
        #expect(legacyDaxDialogFactoryMock.didCallMakeView)
        #expect(legacyDaxDialogFactoryMock.capturedSpec == browsingSpec)
        #expect(!rebrandedDaxDialogFactoryMock.didCallMakeView)
        #expect(rebrandedDaxDialogFactoryMock.capturedSpec == nil)
    }
}
