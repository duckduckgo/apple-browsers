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
@testable import DuckDuckGo

final class SubscriptionOnboardingProgressTests: XCTestCase {

    private var keyValueStore: InMemoryThrowingStore!
    private var sut: SubscriptionOnboardingProgressPersistor!

    override func setUp() {
        super.setUp()
        keyValueStore = InMemoryThrowingStore()
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
        XCTAssertEqual(makeProgress(isPIRAvailable: true).checklist,
                       [.vpn, .vpnWidget, .idtr, .duckAI, .pir])
    }

    /// `.vpnTips` is a real checklist item (so its section can carry a `.kind`), but it must never be
    /// counted: it exists purely so the tips screen piggybacks on `.vpnWidget`'s gating/step number.
    func testVpnTipsIsExcludedFromTheChecklistRegardlessOfPIRAvailability() {
        XCTAssertFalse(makeProgress(isPIRAvailable: true).checklist.contains(.vpnTips))
        XCTAssertFalse(makeProgress(isPIRAvailable: false).checklist.contains(.vpnTips))
        XCTAssertEqual(makeProgress(isPIRAvailable: true).checklist.count, 5)
        XCTAssertEqual(makeProgress(isPIRAvailable: false).checklist.count, 4)
    }

    func testWhenVpnTipsAloneIsCompleteThenPercentageIsUnaffected() {
        let progress = makeProgress(isPIRAvailable: false, completed: [.vpnTips])

        XCTAssertEqual(progress.percentage, 0)
    }

    func testWhenPIRIsUnavailableThenTheChecklistDropsIt() {
        XCTAssertEqual(makeProgress(isPIRAvailable: false).checklist,
                       [.vpn, .vpnWidget, .idtr, .duckAI])
    }

    func testWhenNothingIsCompleteThenPercentageIsZero() {
        XCTAssertEqual(makeProgress(isPIRAvailable: true).percentage, 0)
    }

    func testWhenOneOfFiveIsCompleteThenPercentageIsTwenty() {
        XCTAssertEqual(makeProgress(isPIRAvailable: true, completed: [.vpn]).percentage, 20)
    }

    func testWhenEverythingButPIRIsCompleteThenPercentageIsEighty() {
        let progress = makeProgress(isPIRAvailable: true, completed: [.vpn, .vpnWidget, .idtr, .duckAI])

        XCTAssertEqual(progress.percentage, 80)
    }

    /// The denominator is this customer's checklist, so a PIR-ineligible customer can still reach 100%.
    func testWhenPIRIsUnavailableThenTheSameFourItemsReachOneHundred() {
        let progress = makeProgress(isPIRAvailable: false, completed: [.vpn, .vpnWidget, .idtr, .duckAI])

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
        var progress = makeProgress(isPIRAvailable: false, completed: [.vpn, .vpnWidget, .idtr, .duckAI])
        let session = SubscriptionOnboardingSessionState()

        XCTAssertTrue(progress.shouldShowSetupCard(now: Date(), session: session))
        XCTAssertTrue(session.didCompleteDuringThisSession)
        // Asked again within the same session, so it must still show.
        XCTAssertTrue(progress.shouldShowSetupCard(now: Date(), session: session))
    }

    func testWhenCompletionHappenedInAnEarlierSessionThenTheCardIsHidden() {
        var progress = makeProgress(isPIRAvailable: false, completed: [.vpn, .vpnWidget, .idtr, .duckAI])
        _ = progress.shouldShowSetupCard(now: Date(), session: SubscriptionOnboardingSessionState())

        // A fresh session object is what the next app launch supplies.
        XCTAssertFalse(progress.shouldShowSetupCard(now: Date(), session: SubscriptionOnboardingSessionState()))
    }

    func testWhenReachingOneHundredThenTheCompletionDateIsRecordedOnce() {
        var progress = makeProgress(isPIRAvailable: false, completed: [.vpn, .vpnWidget, .idtr, .duckAI])
        let first = Date(timeIntervalSince1970: 1_000)

        _ = progress.shouldShowSetupCard(now: first, session: SubscriptionOnboardingSessionState())
        _ = progress.shouldShowSetupCard(now: first.addingTimeInterval(3_600),
                                        session: SubscriptionOnboardingSessionState())

        XCTAssertEqual(SubscriptionOnboardingProgressPersistor(keyValueStore: keyValueStore).fullyCompletedAt, first)
    }

    // MARK: - Setup card criteria ordering (three independent ORs; whichever fires first hides it)

    /// No relaunch happens here, so the view cap must be what hides it, not the session latch.
    func testWhenTwoViewsHappenWithinTheCompletingSessionThenTheViewCapHidesItFirst() {
        var progress = makeProgress(isPIRAvailable: false, completed: [.vpn, .vpnWidget, .idtr, .duckAI])
        let session = SubscriptionOnboardingSessionState()

        XCTAssertTrue(progress.shouldShowSetupCard(now: Date(), session: session))
        XCTAssertTrue(progress.shouldShowSetupCard(now: Date(), session: session))
        XCTAssertFalse(progress.shouldShowSetupCard(now: Date(), session: session))
        XCTAssertTrue(session.didCompleteDuringThisSession)
    }

    /// Below the view cap here, so the next-launch rule must be what hides it.
    func testWhenOnlyOneViewHappensBeforeARelaunchThenTheNextLaunchRuleHidesItFirst() {
        var progress = makeProgress(isPIRAvailable: false, completed: [.vpn, .vpnWidget, .idtr, .duckAI])
        _ = progress.shouldShowSetupCard(now: Date(), session: SubscriptionOnboardingSessionState())

        // A fresh session object is what the next app launch supplies.
        XCTAssertFalse(progress.shouldShowSetupCard(now: Date(), session: SubscriptionOnboardingSessionState()))
        XCTAssertEqual(SubscriptionOnboardingProgressPersistor(keyValueStore: keyValueStore).completionViewCount, 1)
    }

    /// The 14-day check is independent of the other two, so it can fire before either of them would.
    func testWhenFourteenDaysHavePassedThenTheWindowHidesItEvenBelowTheViewCapAndWithinTheCompletingSession() {
        var progress = makeProgress(isPIRAvailable: false, completed: [.vpn, .vpnWidget, .idtr, .duckAI])
        let firstShown = Date(timeIntervalSince1970: 1_000_000)
        let session = SubscriptionOnboardingSessionState()
        XCTAssertTrue(progress.shouldShowSetupCard(now: firstShown, session: session))

        XCTAssertFalse(progress.shouldShowSetupCard(now: firstShown.addingTimeInterval(14 * day), session: session))
        XCTAssertTrue(session.didCompleteDuringThisSession)
        XCTAssertEqual(SubscriptionOnboardingProgressPersistor(keyValueStore: keyValueStore).completionViewCount, 1)
    }

    // MARK: - Setup card visibility preview (never writes)

    /// Seeded from a View `init`, which SwiftUI can re-run many times per session, so this must never write.
    func testPreviewNeverWritesEvenAtOneHundredPercent() {
        let progress = makeProgress(isPIRAvailable: false, completed: [.vpn, .vpnWidget, .idtr, .duckAI])
        let session = SubscriptionOnboardingSessionState()

        _ = progress.previewShouldShowSetupCard(now: Date(), session: session)

        XCTAssertFalse(session.didCompleteDuringThisSession)
        XCTAssertNil(SubscriptionOnboardingProgressPersistor(keyValueStore: keyValueStore).fullyCompletedAt)
        XCTAssertNil(SubscriptionOnboardingProgressPersistor(keyValueStore: keyValueStore).cardFirstShownDate)
    }

    func testPreviewMatchesTheRealAnswerBelowOneHundredPercent() {
        let progress = makeProgress(isPIRAvailable: true, completed: [.vpn])

        XCTAssertTrue(progress.previewShouldShowSetupCard(now: Date(), session: SubscriptionOnboardingSessionState()))
    }

    /// Nothing has recorded completion yet, and the preview cannot record it itself, so it must assume "not shown".
    func testPreviewIsPessimisticAtOneHundredPercentUntilTheRealDecisionHasRun() {
        let progress = makeProgress(isPIRAvailable: false, completed: [.vpn, .vpnWidget, .idtr, .duckAI])

        XCTAssertFalse(progress.previewShouldShowSetupCard(now: Date(), session: SubscriptionOnboardingSessionState()))
    }

    func testPreviewAgreesWithTheRealAnswerAfterCompletionInAnEarlierSession() {
        var progress = makeProgress(isPIRAvailable: false, completed: [.vpn, .vpnWidget, .idtr, .duckAI])
        _ = progress.shouldShowSetupCard(now: Date(), session: SubscriptionOnboardingSessionState())

        // A fresh session, as the next launch would supply. The preview must hide here too, or the
        // real, .onAppear-driven decision would immediately override it and the card would flash.
        XCTAssertFalse(progress.previewShouldShowSetupCard(now: Date(), session: SubscriptionOnboardingSessionState()))
    }

    // MARK: - Setup card 14-day window

    func testWhenTheCardWindowIsStillOpenThenTheCardShows() {
        var progress = makeProgress(isPIRAvailable: true, completed: [.vpn])
        let firstShown = Date(timeIntervalSince1970: 1_000_000)

        XCTAssertTrue(progress.shouldShowSetupCard(now: firstShown,
                                                   session: SubscriptionOnboardingSessionState()))
        XCTAssertTrue(progress.shouldShowSetupCard(now: firstShown.addingTimeInterval(13 * day),
                                                   session: SubscriptionOnboardingSessionState()))
    }

    /// Expiry beats incompleteness: 20% complete, but the window has closed.
    func testWhenFourteenDaysHavePassedSinceFirstDisplayThenTheCardIsHidden() {
        var progress = makeProgress(isPIRAvailable: true, completed: [.vpn])
        let firstShown = Date(timeIntervalSince1970: 1_000_000)
        _ = progress.shouldShowSetupCard(now: firstShown, session: SubscriptionOnboardingSessionState())

        XCTAssertFalse(progress.shouldShowSetupCard(now: firstShown.addingTimeInterval(14 * day),
                                                    session: SubscriptionOnboardingSessionState()))
    }

    func testWhenTheCardIsShownAgainThenTheWindowIsNotExtended() {
        var progress = makeProgress(isPIRAvailable: true, completed: [.vpn])
        let firstShown = Date(timeIntervalSince1970: 1_000_000)
        _ = progress.shouldShowSetupCard(now: firstShown, session: SubscriptionOnboardingSessionState())
        _ = progress.shouldShowSetupCard(now: firstShown.addingTimeInterval(10 * day),
                                         session: SubscriptionOnboardingSessionState())

        XCTAssertEqual(SubscriptionOnboardingProgressPersistor(keyValueStore: keyValueStore).cardFirstShownDate,
                       firstShown)
        XCTAssertFalse(progress.shouldShowSetupCard(now: firstShown.addingTimeInterval(15 * day),
                                                    session: SubscriptionOnboardingSessionState()))
    }

    /// The anchor is the first *display*, not the purchase, so a delayed first look still gets a full window.
    func testWhenTheCardIsFirstShownLateThenTheWindowStartsThen() {
        var progress = makeProgress(isPIRAvailable: true, completed: [.vpn])
        let late = Date(timeIntervalSince1970: 1_000_000).addingTimeInterval(60 * day)

        XCTAssertTrue(progress.shouldShowSetupCard(now: late, session: SubscriptionOnboardingSessionState()))
        XCTAssertTrue(progress.shouldShowSetupCard(now: late.addingTimeInterval(13 * day),
                                                   session: SubscriptionOnboardingSessionState()))
    }

    // MARK: - Progress helpers

    private let day: TimeInterval = 24 * 60 * 60

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

/// A local stub rather than `PersistenceTestingUtils`
private final class InMemoryThrowingStore: ThrowingKeyValueStoring {

    private var values: [String: Any] = [:]

    func object(forKey key: String) throws -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) throws { values[key] = value }
    func removeObject(forKey key: String) throws { values.removeValue(forKey: key) }
}
