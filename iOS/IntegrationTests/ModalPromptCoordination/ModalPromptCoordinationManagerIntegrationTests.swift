//
//  ModalPromptCoordinationManagerIntegrationTests.swift
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

import UIKit
import Foundation
import Testing
import Persistence
import PersistenceTestingUtils
@testable import DuckDuckGo

@MainActor
@Suite("Modal Prompt Coordination - Integration Tests")
final class ModalPromptCoordinationManagerIntegrationTests {
    private let timeTraveller: TimeTraveller
    private let keyValueStore: MockKeyValueFileStore
    private let cooldownStore: PromptCooldownKeyValueFilesStore
    private let cooldownIntervalProvider: MockPromptCooldownIntervalProvider
    private let cooldownManager: PromptCooldownManager
    private let schedulerMock: ImmediateScheduler
    private let presenterMock: MockModalPromptPresenter
    private var sut: ModalPromptCoordinationManager!

    init() throws {
        let startDate = Date(timeIntervalSince1970: 1761091200) // 22 October 2025 12:00:00 AM GMT
        timeTraveller = TimeTraveller(date: startDate)
        keyValueStore = try MockKeyValueFileStore()
        cooldownStore = PromptCooldownKeyValueFilesStore(
            keyValueStore: keyValueStore,
            eventMapper: .init(mapping: { _, _, _, _ in })
        )
        cooldownIntervalProvider = MockPromptCooldownIntervalProvider() // Cooldown Interval 24h
        cooldownManager = PromptCooldownManager(
            presentationStore: cooldownStore,
            cooldownIntervalProvider: cooldownIntervalProvider,
            dateProvider: timeTraveller.getDate
        )
        schedulerMock = ImmediateScheduler()
        presenterMock = MockModalPromptPresenter()
    }

    @Test("Check Is In Cooldown After Presenting Prompt")
    func whenPromptIsPresentedThenIsInCooldown() {
        // GIVEN
        let provider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManager,
            modalPromptScheduling: schedulerMock
        )
        #expect(!cooldownManager.isInCooldownPeriod)

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN
        #expect(cooldownManager.isInCooldownPeriod)
    }

    @Test(
        "Check Modal Is Blocked During Cooldown Period",
        arguments: [1, 6, 12, 18, 23]  // Hours after first presentation
    )
    func whenWithinCooldownPeriodThenModalIsBlocked(hoursAfterPresentation: Int) {
        // GIVEN
        cooldownStore.lastPresentationTimestamp = timeTraveller.getDate().timeIntervalSince1970
        let firstProvider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [firstProvider],
            cooldownManager: cooldownManager,
            modalPromptScheduling: schedulerMock
        )
        #expect(cooldownManager.isInCooldownPeriod)

        // WHEN - Advance time but stay within 24-hour cooldown
        timeTraveller.advanceBy(.hours(hoursAfterPresentation))
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN
        #expect(cooldownManager.isInCooldownPeriod)
        #expect(!firstProvider.didCallProvideModalPrompt)
        #expect(!firstProvider.didCallDidPresentModal)
        #expect(!presenterMock.didCallPresent)
    }

    @Test(
        "Check Modal Is Allowed After Cooldown Period Expires",
        arguments: [24, 25, 30, 48, 72]  // Hours after first presentation
    )
    func whenAfterCooldownPeriodThenModalIsAllowed(hoursAfterPresentation: Int) {
        // GIVEN
        cooldownStore.lastPresentationTimestamp = timeTraveller.getDate().timeIntervalSince1970
        let firstProvider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [firstProvider],
            cooldownManager: cooldownManager,
            modalPromptScheduling: schedulerMock
        )
        #expect(cooldownManager.isInCooldownPeriod)

        // WHEN - Advance time past cooldown period
        timeTraveller.advanceBy(.hours(hoursAfterPresentation))

        // THEN
        #expect(!cooldownManager.isInCooldownPeriod)

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)
        #expect(firstProvider.didCallProvideModalPrompt)
        #expect(presenterMock.didCallPresent)
        #expect(firstProvider.didCallDidPresentModal)
    }

    // MARK: - Multiple Presentations Over Time

    @Test("Check Multiple Modals Can Be Presented After Cooldown Interval")
    func whenCooldownIntervalPassAllModalArePresented() {
        // GIVEN
        let provider1 = MockModalPromptProvider()
        let provider2 = MockModalPromptProvider()
        let provider3 = MockModalPromptProvider()

        sut = ModalPromptCoordinationManager(
            providers: [provider1, provider2, provider3],
            cooldownManager: cooldownManager,
            modalPromptScheduling: schedulerMock
        )

        // WHEN presenting the first prompt
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN first prompt is presented
        #expect(provider1.didCallDidPresentModal)
        #expect(!provider2.didCallDidPresentModal)
        #expect(!provider3.didCallDidPresentModal)
        #expect(cooldownManager.isInCooldownPeriod)

        // Advance time to 24 hours after presentation (cooldown expired)
        timeTraveller.advanceBy(.hours(24))
        #expect(!cooldownManager.isInCooldownPeriod)

        // Simulate first provider does not have a modal to show
        provider1.modalConfigurationToReturn = nil
        provider1.reset()

        // WHEN presenting the modal again
        provider1.modalConfigurationToReturn = nil
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN second prompt is presented
        #expect(!provider1.didCallDidPresentModal)
        #expect(provider2.didCallDidPresentModal)
        #expect(!provider3.didCallDidPresentModal)
        #expect(cooldownManager.isInCooldownPeriod)

        // Simulate second provider does not have a modal to show
        provider2.modalConfigurationToReturn = nil
        provider2.reset()

        // Advance time to 24 hours after presentation (cooldown expired)
        timeTraveller.advanceBy(.hours(24))
        #expect(!cooldownManager.isInCooldownPeriod)

        // WHEN presenting the first prompt
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN third prompt is presented
        #expect(!provider1.didCallDidPresentModal)
        #expect(!provider2.didCallDidPresentModal)
        #expect(provider3.didCallDidPresentModal)
        #expect(cooldownManager.isInCooldownPeriod)
    }

    @Test("Check Prompt Is Not Presented If Presented During Cooldown")
    func whenModalIsPresentedTooSoonThenItIsNotPresented() {
        // GIVEN
        let provider1 = MockModalPromptProvider()
        let provider2 = MockModalPromptProvider()

        sut = ModalPromptCoordinationManager(
            providers: [provider1, provider2],
            cooldownManager: cooldownManager,
            modalPromptScheduling: schedulerMock
        )

        // WHEN presenting the first modal
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN
        #expect(provider1.didCallDidPresentModal)
        #expect(!provider2.didCallDidPresentModal)
        #expect(presenterMock.didCallPresent)
        #expect(cooldownManager.isInCooldownPeriod)

        // Advance time to 12 hours later (still in cooldown)
        timeTraveller.advanceBy(.hours(12))
        #expect(cooldownManager.isInCooldownPeriod)

        // Simulate first provider does not have modal to show
        provider1.reset()
        provider1.modalConfigurationToReturn = nil
        presenterMock.reset()

        // WHEN trying to present again during cooldown
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN no modals are presented
        #expect(!provider1.didCallDidPresentModal)
        #expect(!provider2.didCallDidPresentModal)
        #expect(!presenterMock.didCallPresent)
    }

    // MARK: - Cooldown Info Integration

    @Test("Check Cooldown Info Reports Correct Dates After Presentation")
    func whenModalPresentedThenCooldownInfoIsCorrect() {
        // GIVEN
        let provider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManager,
            modalPromptScheduling: schedulerMock
        )
        let presentationTime = timeTraveller.getDate()

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN
        let info = cooldownManager.cooldownInfo
        #expect(info.isInCooldownPeriod)
        #expect(info.lastPresentationDate == presentationTime)
        #expect(info.nextPresentationDate == presentationTime.addingTimeInterval(.hours(24)))
    }

    @Test("Check Cooldown Info Updates After Time Advances")
    func whenTimeAdvancesThenCooldownInfoReflectsNewState() {
        // GIVEN
        let provider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManager,
            modalPromptScheduling: schedulerMock
        )
        var lastPresentationTime = timeTraveller.getDate()
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // Advance time to 12 hours later (still in cooldown)
        timeTraveller.advanceBy(.hours(12))

        // WHEN
        let infoWhileInCooldown = cooldownManager.cooldownInfo

        // THEN
        #expect(infoWhileInCooldown.isInCooldownPeriod)
        #expect(infoWhileInCooldown.lastPresentationDate == lastPresentationTime)
        #expect(infoWhileInCooldown.nextPresentationDate == lastPresentationTime.addingTimeInterval(.hours(24)))

        // Advance time to 24 hours after presentation (cooldown expired)
        timeTraveller.advanceBy(.hours(12))

        // WHEN
        let infoAfterCooldownBeforePresentingModalAgain = cooldownManager.cooldownInfo

        // THEN
        #expect(!infoAfterCooldownBeforePresentingModalAgain.isInCooldownPeriod)
        #expect(infoAfterCooldownBeforePresentingModalAgain.lastPresentationDate == lastPresentationTime)
        #expect(infoAfterCooldownBeforePresentingModalAgain.nextPresentationDate == lastPresentationTime.addingTimeInterval(.hours(24)))

        // WHEN
        lastPresentationTime = timeTraveller.getDate()
        sut.presentModalPromptIfNeeded(from: presenterMock)

        let infoAfterCooldownAfterPresentingModalAgain = cooldownManager.cooldownInfo

        // THEN
        #expect(infoAfterCooldownAfterPresentingModalAgain.isInCooldownPeriod)
        #expect(infoAfterCooldownAfterPresentingModalAgain.lastPresentationDate == lastPresentationTime)
        #expect(infoAfterCooldownAfterPresentingModalAgain.nextPresentationDate == lastPresentationTime.addingTimeInterval(.hours(24)))
    }

    // MARK: - Persistence Tests

    @Test("Check Cooldown Persists In Storage")
    func whenModalPresentedThenTimestampIsPersisted() throws {
        // GIVEN
        let provider = MockModalPromptProvider()
        sut = ModalPromptCoordinationManager(
            providers: [provider],
            cooldownManager: cooldownManager,
            modalPromptScheduling: schedulerMock
        )
        let presentationTime = timeTraveller.getDate()

        // WHEN
        sut.presentModalPromptIfNeeded(from: presenterMock)

        // THEN
        let storedTimestamp = try keyValueStore.object(forKey: PromptCooldownKeyValueFilesStore.StorageKey.lastPromptShownTimestamp) as? TimeInterval
        #expect(storedTimestamp == presentationTime.timeIntervalSince1970)
    }

    @Test("Check Cooldown Is Read From Storage")
    func whenManagerCreatedThenCooldownIsReadFromStorage() throws {
        // GIVEN
        #expect(!cooldownManager.isInCooldownPeriod)

        // WHEN
        let pastTime = timeTraveller.getDate().addingTimeInterval(-.hours(12))
        try keyValueStore.set(pastTime.timeIntervalSince1970, forKey: PromptCooldownKeyValueFilesStore.StorageKey.lastPromptShownTimestamp)

        // THEN
        #expect(cooldownManager.isInCooldownPeriod)
        #expect(cooldownManager.cooldownInfo.lastPresentationDate == pastTime)
    }
}

// MARK: - Helpers

private final class ImmediateScheduler: ModalPromptScheduling {
    func schedule(after delay: TimeInterval, execute: @escaping @MainActor () -> Void) {
        MainActor.assumeIsolated {
            execute()
        }
    }
}
