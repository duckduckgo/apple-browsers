//
//  PromptCooldownManagerTests.swift
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
@testable import DuckDuckGo

@Suite("Modal Prompt Coordination - Cooldown Manager")
final class PromptCooldownManagerTests {
    private let cooldownStoreMock: MockPromptCooldownStore
    private let cooldownIntervalProviderMock: MockPromptCooldownIntervalProvider
    private let currentDate: Date
    private var sut: PromptCooldownManager!

    init() {
        cooldownStoreMock = MockPromptCooldownStore()
        cooldownIntervalProviderMock = MockPromptCooldownIntervalProvider()
        currentDate = Date(timeIntervalSince1970: 1761091200) // 22 October 2025 12:00:00 AM GMT
        sut = PromptCooldownManager(
            presentationStore: cooldownStoreMock,
            cooldownIntervalProvider: cooldownIntervalProviderMock,
            dateProvider: { self.currentDate }
        )
    }

    @Test("Check Is Not In Cooldown Period When No Timestamp Is Stored")
    func whenNoTimestampStoredThenIsNotInCooldownPeriod() {
        // GIVEN
        cooldownStoreMock.lastPresentationTimestamp = nil
        cooldownIntervalProviderMock.cooldownInterval = 24

        // WHEN
        let result = sut.isInCooldownPeriod

        // THEN
        #expect(!result)
    }

    @Test(
        "Check Is In Cooldown Period When Last Presentation Was Within Cooldown Interval",
        arguments: zip(
            [24, 48, 72],  // Cooldown intervals in hours
            [1, 12, 23]    // Hours since last presentation
        )
    )
    func whenLastPresentationWithinCooldownThenIsInCooldownPeriod(cooldownHours: Int, hoursSincePresentation: Int) {
        // GIVEN
        cooldownIntervalProviderMock.cooldownInterval = cooldownHours
        let lastPresentationDate = currentDate.addingTimeInterval(-.hours(hoursSincePresentation))
        cooldownStoreMock.lastPresentationTimestamp = lastPresentationDate.timeIntervalSince1970

        // WHEN
        let result = sut.isInCooldownPeriod

        // THEN
        #expect(result)
    }

    @Test(
        "Check Is Not In Cooldown Period When Last Presentation Was Outside Cooldown Interval",
        arguments: zip(
            [24, 48, 72],   // Cooldown intervals in hours
            [25, 49, 73]    // Hours since last presentation
        )
    )
    func whenLastPresentationOutsideCooldownThenIsNotInCooldownPeriod(cooldownHours: Int, hoursSincePresentation: Int) {
        // GIVEN
        cooldownIntervalProviderMock.cooldownInterval = cooldownHours
        let lastPresentationDate = currentDate.addingTimeInterval(-.hours(hoursSincePresentation))
        cooldownStoreMock.lastPresentationTimestamp = lastPresentationDate.timeIntervalSince1970

        // WHEN
        let result = sut.isInCooldownPeriod

        // THEN
        #expect(!result)
    }

    @Test("Check Is Not In Cooldown Period When Last Presentation Was Exactly At Cooldown Interval")
    func whenLastPresentationExactlyAtCooldownThenIsNotInCooldownPeriod() {
        // GIVEN
        cooldownIntervalProviderMock.cooldownInterval = 24
        let lastPresentationDate = currentDate.addingTimeInterval(-.hours(24))
        cooldownStoreMock.lastPresentationTimestamp = lastPresentationDate.timeIntervalSince1970

        // WHEN
        let result = sut.isInCooldownPeriod

        // THEN
        #expect(!result)
    }

    @Test("Check Cooldown Info Is Correct When No Timestamp Is Stored")
    func whenNoTimestampStoredThenCooldownInfoReflectsNoLastPresentation() {
        // GIVEN
        cooldownStoreMock.lastPresentationTimestamp = nil
        cooldownIntervalProviderMock.cooldownInterval = 24

        // WHEN
        let info = sut.cooldownInfo

        // THEN
        #expect(!info.isInCooldownPeriod)
        #expect(info.lastPresentationDate == nil)
        #expect(info.nextPresentationDate == currentDate)
    }

    @Test("Check Cooldown Info Is Correct When In Cooldown Period")
    func whenInCooldownPeriodThenCooldownInfoReflectsCorrectDates() {
        // GIVEN
        cooldownIntervalProviderMock.cooldownInterval = 24
        let lastPresentationDate = currentDate.addingTimeInterval(-.hours(12))
        let expectedNextPresentationDate = lastPresentationDate.addingTimeInterval(.hours(cooldownIntervalProviderMock.cooldownInterval))
        cooldownStoreMock.lastPresentationTimestamp = lastPresentationDate.timeIntervalSince1970

        // WHEN
        let info = sut.cooldownInfo

        // THEN
        #expect(info.isInCooldownPeriod)
        #expect(info.lastPresentationDate == lastPresentationDate)
        #expect(info.nextPresentationDate == expectedNextPresentationDate)
    }

    @Test("Check Cooldown Info Is Correct When Outside Cooldown Period")
    func whenOutsideCooldownPeriodThenCooldownInfoReflectsCorrectDates() {
        // GIVEN
        cooldownIntervalProviderMock.cooldownInterval = 24
        let lastPresentationDate = currentDate.addingTimeInterval(-.hours(25))
        let expectedNextPresentationDate = lastPresentationDate.addingTimeInterval(.hours(cooldownIntervalProviderMock.cooldownInterval))
        cooldownStoreMock.lastPresentationTimestamp = lastPresentationDate.timeIntervalSince1970

        // WHEN
        let info = sut.cooldownInfo

        // THEN
        #expect(!info.isInCooldownPeriod)
        #expect(info.lastPresentationDate == lastPresentationDate)
        #expect(info.nextPresentationDate == expectedNextPresentationDate)
    }


    @Test("Check Record Last Prompt Presentation Saves Current Date")
    func whenRecordingPresentationThenCurrentDateIsSaved() {
        // GIVEN
        cooldownStoreMock.lastPresentationTimestamp = nil
        cooldownIntervalProviderMock.cooldownInterval = 24
        #expect(cooldownStoreMock.lastPresentationTimestamp == nil)

        // WHEN
        sut.recordLastPromptPresentationTimestamp()

        // THEN
        #expect(cooldownStoreMock.lastPresentationTimestamp == currentDate.timeIntervalSince1970)
    }

    @Test("Check Record Last Prompt Presentation Overwrites Previous Date")
    func whenRecordingPresentationAgainThenPreviousDateIsOverwritten() {
        // GIVEN
        let oldDate = currentDate.addingTimeInterval(-.hours(48))
        cooldownStoreMock.lastPresentationTimestamp = oldDate.timeIntervalSince1970
        cooldownIntervalProviderMock.cooldownInterval = 24

        // WHEN
        sut.recordLastPromptPresentationTimestamp()

        // THEN
        #expect(cooldownStoreMock.lastPresentationTimestamp != oldDate.timeIntervalSince1970)
        #expect(cooldownStoreMock.lastPresentationTimestamp == currentDate.timeIntervalSince1970)
    }

    @Test("Check Recording Presentation Sets Manager In Cooldown Period")
    func whenRecordingPresentationThenManagerEntersCooldownPeriod() {
        // GIVEN
        cooldownStoreMock.lastPresentationTimestamp = nil
        cooldownIntervalProviderMock.cooldownInterval = 24
        #expect(!sut.isInCooldownPeriod)

        // WHEN
        sut.recordLastPromptPresentationTimestamp()

        // THEN
        #expect(sut.isInCooldownPeriod)
    }

    // MARK: - Edge Cases

    @Test("Check Cooldown With Zero Hour Interval")
    func whenCooldownIntervalIsZeroThenAlwaysOutOfCooldown() {
        // GIVEN
        cooldownIntervalProviderMock.cooldownInterval = 0
        cooldownStoreMock.lastPresentationTimestamp = currentDate.timeIntervalSince1970

        // WHEN
        let result = sut.isInCooldownPeriod

        // THEN
        #expect(!result)
    }

    @Test(
        "Check Cooldown Info Calculates Next Presentation Date Correctly With Different Intervals",
        arguments: [
            (12, .hours(12)),
            (24, .hours(24)),
            (48, .hours(48)),
            (72, .hours(72))
        ] as [(Int, TimeInterval)]
    )
    func whenDifferentCooldownIntervalsThenNextPresentationDateCalculatedCorrectly(cooldownHours: Int, expectedOffset: TimeInterval) {
        // GIVEN
        cooldownIntervalProviderMock.cooldownInterval = cooldownHours
        let lastPresentationDate = currentDate
        cooldownStoreMock.lastPresentationTimestamp = lastPresentationDate.timeIntervalSince1970

        // WHEN
        let info = sut.cooldownInfo

        // THEN
        let expectedNextDate = lastPresentationDate.addingTimeInterval(expectedOffset)
        #expect(info.nextPresentationDate == expectedNextDate)
    }
}
