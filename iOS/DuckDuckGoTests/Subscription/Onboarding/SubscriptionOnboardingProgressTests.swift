//
//  SubscriptionOnboardingProgressTests.swift
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

import XCTest
import Persistence
import PersistenceTestingUtils
@testable import DuckDuckGo

final class SubscriptionOnboardingProgressTests: XCTestCase {

    private var keyValueStore: InMemoryThrowingKeyValueStore!
    private var sut: SubscriptionOnboardingProgressPersistor!

    override func setUp() {
        super.setUp()
        keyValueStore = InMemoryThrowingKeyValueStore()
        sut = SubscriptionOnboardingProgressPersistor(keyValueStore: keyValueStore)
    }

    override func tearDown() {
        keyValueStore = nil
        sut = nil
        super.tearDown()
    }

    // MARK: - Completed items

    func testWhenNothingIsStoredThenNoItemsAreComplete() {
        XCTAssertTrue(sut.completedItems.isEmpty)
    }

    func testWhenItemsAreStoredThenTheyRoundTrip() {
        sut.completedItems = [.vpn, .duckAI]

        XCTAssertEqual(SubscriptionOnboardingProgressPersistor(keyValueStore: keyValueStore).completedItems,
                       [.vpn, .duckAI])
    }

    func testWhenMarkingCompleteThenTheItemIsAddedWithoutDisturbingTheOthers() {
        sut.completedItems = [.vpn]

        sut.markComplete(.idtr)

        XCTAssertEqual(sut.completedItems, [.vpn, .idtr])
    }

    func testWhenMarkingTheSameItemTwiceThenTheSetIsUnchanged() {
        sut.markComplete(.vpn)
        sut.markComplete(.vpn)

        XCTAssertEqual(sut.completedItems, [.vpn])
    }

    func testWhenStoredValueContainsAnUnknownItemThenTheRestSurvive() {
        // A downgrade after a new checklist item ships must not wipe the progress that still makes sense.
        try? keyValueStore.set(["vpn", "teleportation", "pir"],
                               forKey: SubscriptionOnboardingProgressPersistor.Key.completedItems.rawValue)

        XCTAssertEqual(sut.completedItems, [.vpn, .pir])
    }

    func testWhenStoredValueIsTheWrongTypeThenNoItemsAreComplete() {
        try? keyValueStore.set(42, forKey: SubscriptionOnboardingProgressPersistor.Key.completedItems.rawValue)

        XCTAssertTrue(sut.completedItems.isEmpty)
    }

    // MARK: - Progress

    func testWhenPIRIsAvailableThenTheChecklistHasAllFiveItems() {
        XCTAssertEqual(makeProgress(isPIRAvailable: true).checklistItems,
                       SubscriptionOnboardingChecklistItem.allCases)
    }

    func testWhenPIRIsUnavailableThenTheChecklistDropsIt() {
        XCTAssertEqual(makeProgress(isPIRAvailable: false).checklistItems,
                       [.vpn, .widget, .idtr, .duckAI])
    }

    func testWhenNothingIsCompleteThenPercentageIsZero() {
        XCTAssertEqual(makeProgress(isPIRAvailable: true).percentage, 0)
    }

    func testWhenOneOfFiveIsCompleteThenPercentageIsTwenty() {
        XCTAssertEqual(makeProgress(isPIRAvailable: true, completed: [.vpn]).percentage, 20)
    }

    func testWhenEverythingButPIRIsCompleteThenPercentageIsEighty() {
        let progress = makeProgress(isPIRAvailable: true, completed: [.vpn, .widget, .idtr, .duckAI])

        XCTAssertEqual(progress.percentage, 80)
    }

    /// The denominator is this customer's checklist, so a PIR-ineligible customer can still reach 100%.
    func testWhenPIRIsUnavailableThenTheSameFourItemsReachOneHundred() {
        let progress = makeProgress(isPIRAvailable: false, completed: [.vpn, .widget, .idtr, .duckAI])

        XCTAssertEqual(progress.percentage, 100)
    }

    func testWhenACompletedItemIsNotOnTheChecklistThenItDoesNotCount() {
        let progress = makeProgress(isPIRAvailable: false, completed: [.pir])

        XCTAssertEqual(progress.percentage, 0)
    }

    func testWhenMarkingCompleteThenItIsWrittenThroughToTheStore() {
        var progress = makeProgress(isPIRAvailable: true)

        progress.markComplete(.idtr)

        XCTAssertEqual(progress.completedItems, [.idtr])
        XCTAssertEqual(SubscriptionOnboardingProgressPersistor(keyValueStore: keyValueStore).completedItems, [.idtr])
    }

    // MARK: - Setup card visibility

    func testWhenBelowOneHundredThenTheCardShowsAndTheSessionIsUntouched() {
        var progress = makeProgress(isPIRAvailable: true, completed: [.vpn])
        let session = SubscriptionOnboardingSessionState()

        XCTAssertTrue(progress.shouldShowSetupCard(now: Date(), session: session))
        XCTAssertFalse(session.didCompleteDuringThisSession)
    }

    func testWhenReachingOneHundredThenTheCardStillShowsForTheRestOfTheSession() {
        var progress = makeProgress(isPIRAvailable: false, completed: [.vpn, .widget, .idtr, .duckAI])
        let session = SubscriptionOnboardingSessionState()

        XCTAssertTrue(progress.shouldShowSetupCard(now: Date(), session: session))
        XCTAssertTrue(session.didCompleteDuringThisSession)
        // Asking again within the same session must not hide it.
        XCTAssertTrue(progress.shouldShowSetupCard(now: Date(), session: session))
    }

    func testWhenCompletionHappenedInAnEarlierSessionThenTheCardIsHidden() {
        var progress = makeProgress(isPIRAvailable: false, completed: [.vpn, .widget, .idtr, .duckAI])
        _ = progress.shouldShowSetupCard(now: Date(), session: SubscriptionOnboardingSessionState())

        // A fresh session object is what the next app launch supplies.
        XCTAssertFalse(progress.shouldShowSetupCard(now: Date(), session: SubscriptionOnboardingSessionState()))
    }

    func testWhenReachingOneHundredThenTheCompletionDateIsRecordedOnce() {
        var progress = makeProgress(isPIRAvailable: false, completed: [.vpn, .widget, .idtr, .duckAI])
        let first = Date(timeIntervalSince1970: 1_000)

        _ = progress.shouldShowSetupCard(now: first, session: SubscriptionOnboardingSessionState())
        _ = progress.shouldShowSetupCard(now: first.addingTimeInterval(3_600),
                                        session: SubscriptionOnboardingSessionState())

        XCTAssertEqual(SubscriptionOnboardingProgressPersistor(keyValueStore: keyValueStore).fullyCompletedAt, first)
    }

    // MARK: - Progress helpers

    private func makeProgress(isPIRAvailable: Bool,
                              completed: Set<SubscriptionOnboardingChecklistItem> = []) -> SubscriptionOnboardingProgress {
        sut.completedItems = completed
        return SubscriptionOnboardingProgress(persistor: sut, isPIRAvailable: isPIRAvailable)
    }

    // MARK: - Card first shown

    func testWhenCardHasNeverBeenShownThenTheDateIsNil() {
        XCTAssertNil(sut.cardFirstShownDate)
    }

    func testWhenRecordingFirstShownThenTheDateIsStored() {
        let now = Date(timeIntervalSince1970: 1_000_000)

        sut.recordCardFirstShownIfNeeded(now: now)

        XCTAssertEqual(sut.cardFirstShownDate, now)
    }

    func testWhenRecordingFirstShownAgainThenTheOriginalDateIsKept() {
        // The 14-day window is anchored to the first display; a later one must not extend it.
        let first = Date(timeIntervalSince1970: 1_000_000)
        let later = Date(timeIntervalSince1970: 2_000_000)

        sut.recordCardFirstShownIfNeeded(now: first)
        sut.recordCardFirstShownIfNeeded(now: later)

        XCTAssertEqual(sut.cardFirstShownDate, first)
    }

    func testWhenClearingFirstShownThenItIsRemoved() {
        sut.recordCardFirstShownIfNeeded(now: Date())

        sut.cardFirstShownDate = nil

        XCTAssertNil(sut.cardFirstShownDate)
    }
}
