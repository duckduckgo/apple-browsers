//
//  AppRatingPromptCoordinatorTests.swift
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

import FeatureFlags_iOS
import Foundation
@_spi(Testing) import Persistence
import Testing
@testable import DuckDuckGo

/// A storage double. `AppRatingPromptStorageStub` is `fileprivate` to `AppRatingPromptTests`.
private final class InMemoryAppRatingPromptStorage: AppRatingPromptStorage {
    var firstShown: Date?
    var lastAccess: Date?
    var uniqueAccessDays: Int? = 0
    var lastShown: Date?
}

private struct StubAppRatingPromptCoordinationPolicy: AppRatingPromptCoordinationPolicying {
    let isCoordinationEnabled: Bool
    var maxUnredeemedSlots: Int = 3
}

@MainActor
@Suite("App Rating Prompt - Coordinator")
final class AppRatingPromptCoordinatorTests {
    private let keyValueStore: MockKeyValueFileStore
    private let storage = InMemoryAppRatingPromptStorage()
    private let featureFlagger = MockFeatureFlagger()

    init() {
        keyValueStore = MockKeyValueFileStore()
        featureFlagger.enabledFeatureFlags = [.appRatingPrompt]
    }

    // MARK: - Eligibility

    @Test("Eligible for the slot once the prompt is due and coordination is on")
    func eligibleWhenDueAndCoordinationOn() {
        let sut = makeCoordinator(isCoordinationEnabled: true)
        accrueUsageDays(3)

        #expect(sut.isEligibleToPresent(isOnboardingComplete: true))
    }

    @Test("Not eligible before the prompt is due")
    func notEligibleBeforeDue() {
        let sut = makeCoordinator(isCoordinationEnabled: true)
        accrueUsageDays(2)

        #expect(!sut.isEligibleToPresent(isOnboardingComplete: true))
    }

    @Test("Not eligible when coordination is off")
    func notEligibleWhenCoordinationOff() {
        let sut = makeCoordinator(isCoordinationEnabled: false)
        accrueUsageDays(3)

        #expect(!sut.isEligibleToPresent(isOnboardingComplete: true))
        // The uncoordinated path is unaffected, so the prompt still works.
        #expect(sut.shouldRequestUncoordinated())
    }

    @Test("Not eligible when the prompt feature flag is off")
    func notEligibleWhenPromptFlagOff() {
        featureFlagger.enabledFeatureFlags = []
        let sut = makeCoordinator(isCoordinationEnabled: true)
        accrueUsageDays(3)

        #expect(!sut.isEligibleToPresent(isOnboardingComplete: true))
        #expect(!sut.shouldRequestUncoordinated())
    }

    @Test("Incomplete onboarding does not block the prompt", arguments: [true, false])
    func onboardingDoesNotBlockThePrompt(_ isOnboardingComplete: Bool) {
        let sut = makeCoordinator(isCoordinationEnabled: true)
        accrueUsageDays(3)

        #expect(sut.isEligibleToPresent(isOnboardingComplete: isOnboardingComplete))
    }

    @Test("A deferred provider is never asked for a configuration")
    func providerIsDeferredAndSuppliesNoConfiguration() {
        let sut = makeCoordinator(isCoordinationEnabled: true)

        #expect(sut.presentationKind == .deferred)
        #expect(sut.provideModalPrompt() == nil)
    }

    @Test("Redeeming a slot does not consume eligibility on its own")
    func didPresentModalDoesNotConsumeEligibility() {
        let sut = makeCoordinator(isCoordinationEnabled: true)
        accrueUsageDays(3)

        sut.didPresentModal()

        // Only called when a slot was taken and redeemed, so it can never be where eligibility
        // is consumed. The request site does that.
        #expect(sut.isEligibleToPresent(isOnboardingComplete: true))
        #expect(storage.firstShown == nil)
    }

    // MARK: - Redemption

    @Test("Requesting the rating consumes eligibility")
    func requestingConsumesEligibility() {
        let sut = makeCoordinator(isCoordinationEnabled: true)
        accrueUsageDays(3)
        #expect(sut.isEligibleToPresent(isOnboardingComplete: true))

        sut.didRequestRating()

        #expect(!sut.isEligibleToPresent(isOnboardingComplete: true))
        #expect(storage.firstShown != nil)
    }

    @Test("The second request becomes due after four more usage days")
    func secondRequestBecomesDueLater() {
        let sut = makeCoordinator(isCoordinationEnabled: true)
        accrueUsageDays(3)
        sut.didRequestRating()

        // `shown()` resets the counter, so the second needs four fresh days.
        accrueUsageDays(4)

        #expect(sut.isEligibleToPresent(isOnboardingComplete: true))

        sut.didRequestRating()

        #expect(!sut.isEligibleToPresent(isOnboardingComplete: true))
        #expect(storage.lastShown != nil)
    }

    // MARK: - Unredeemed slot cap

    @Test("Stops taking the slot once the unredeemed cap is reached")
    func stopsTakingSlotAtCap() {
        let sut = makeCoordinator(isCoordinationEnabled: true)
        accrueUsageDays(3)

        sut.didReleaseDeferredSlot()
        #expect(sut.unredeemedSlotCount == 1)
        #expect(sut.isEligibleToPresent(isOnboardingComplete: true))

        sut.didReleaseDeferredSlot()
        #expect(sut.unredeemedSlotCount == 2)
        #expect(sut.isEligibleToPresent(isOnboardingComplete: true))

        sut.didReleaseDeferredSlot()
        #expect(sut.unredeemedSlotCount == 3)
        #expect(!sut.isEligibleToPresent(isOnboardingComplete: true))
    }

    @Test("Redeeming clears the unredeemed count")
    func redeemingClearsTheCount() {
        let sut = makeCoordinator(isCoordinationEnabled: true)
        accrueUsageDays(3)
        sut.didReleaseDeferredSlot()

        sut.didRequestRating()

        #expect(sut.unredeemedSlotCount == 0)
    }

    @Test("A configured cap of zero removes the limit")
    func zeroCapRemovesTheLimit() {
        let sut = makeCoordinator(isCoordinationEnabled: true, maxUnredeemedSlots: 0)
        accrueUsageDays(3)

        for _ in 0..<10 {
            sut.didReleaseDeferredSlot()
        }

        #expect(sut.unredeemedSlotCount == 10)
        #expect(sut.isEligibleToPresent(isOnboardingComplete: true))
    }

    @Test("The cap honours a remotely configured value")
    func capHonoursRemoteValue() {
        let sut = makeCoordinator(isCoordinationEnabled: true, maxUnredeemedSlots: 1)
        accrueUsageDays(3)

        sut.didReleaseDeferredSlot()

        #expect(!sut.isEligibleToPresent(isOnboardingComplete: true))
    }

    // MARK: - Debug reset

    @Test("The debug reset clears both the count and the eligibility state")
    func debugResetClearsEverything() {
        let sut = makeCoordinator(isCoordinationEnabled: true)
        accrueUsageDays(3)
        sut.didRequestRating()
        sut.didReleaseDeferredSlot()

        sut.resetForDebug()

        #expect(sut.unredeemedSlotCount == 0)
        #expect(storage.firstShown == nil)
        #expect(storage.lastShown == nil)
        #expect(!sut.isEligibleToPresent(isOnboardingComplete: true))

        accrueUsageDays(3)
        #expect(sut.isEligibleToPresent(isOnboardingComplete: true))
    }

    // MARK: - Helpers

    private func makeCoordinator(
        isCoordinationEnabled: Bool,
        maxUnredeemedSlots: Int = 3
    ) -> AppRatingPromptCoordinator {
        AppRatingPromptCoordinator(
            appRatingPrompt: AppRatingPrompt(storage: storage, featureFlagger: featureFlagger),
            coordinationPolicy: StubAppRatingPromptCoordinationPolicy(
                isCoordinationEnabled: isCoordinationEnabled,
                maxUnredeemedSlots: maxUnredeemedSlots
            ),
            store: AppRatingPromptSlotStore(keyValueStore: keyValueStore)
        )
    }

    /// Sets the day count directly; the counting itself is covered by `AppRatingPromptTests`.
    private func accrueUsageDays(_ count: Int) {
        storage.uniqueAccessDays = count
    }
}
