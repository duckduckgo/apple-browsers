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
import Subscription
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

    func testWhenPIRIsAvailableThenTheChecklistHasAllFourItems() {
        XCTAssertEqual(makeProgress(isPIRAvailable: true).checklist,
                       [.vpn, .idtr, .duckAI, .pir])
    }

    func testWhenPIRIsUnavailableThenTheChecklistDropsIt() {
        XCTAssertEqual(makeProgress(isPIRAvailable: false).checklist,
                       [.vpn, .idtr, .duckAI])
    }

    // MARK: - Entitlement gating

    func testWhenEntitlementExcludesVPNThenTheChecklistDropsItAndItsWidget() {
        let entitlement = EntitlementStatus(networkProtection: false, dataBrokerProtection: true,
                                            identityTheftRestoration: true, identityTheftRestorationGlobal: true,
                                            paidAIChat: true)

        XCTAssertEqual(makeProgress(isPIRAvailable: true, entitlement: entitlement).checklist,
                       [.idtr, .duckAI, .pir])
    }

    func testWhenEntitlementExcludesIDTRThenTheChecklistDropsIt() {
        let entitlement = EntitlementStatus(networkProtection: true, dataBrokerProtection: true,
                                            identityTheftRestoration: false, identityTheftRestorationGlobal: false,
                                            paidAIChat: true)

        XCTAssertEqual(makeProgress(isPIRAvailable: true, entitlement: entitlement).checklist,
                       [.vpn, .duckAI, .pir])
    }

    /// Either the regional or the global entitlement is enough to keep the step.
    func testWhenOnlyGlobalIDTREntitlementIsPresentThenTheStepIsKept() {
        let entitlement = EntitlementStatus(networkProtection: true, dataBrokerProtection: true,
                                            identityTheftRestoration: false, identityTheftRestorationGlobal: true,
                                            paidAIChat: true)

        XCTAssertTrue(makeProgress(isPIRAvailable: true, entitlement: entitlement).checklist.contains(.idtr))
    }

    func testWhenEntitlementExcludesDuckAIThenTheChecklistDropsIt() {
        let entitlement = EntitlementStatus(networkProtection: true, dataBrokerProtection: true,
                                            identityTheftRestoration: true, identityTheftRestorationGlobal: true,
                                            paidAIChat: false)

        XCTAssertEqual(makeProgress(isPIRAvailable: true, entitlement: entitlement).checklist,
                       [.vpn, .idtr, .pir])
    }

    /// No fallback: every case is gated independently, so excluding all four core items just leaves whatever
    /// else survives (here, `.pir` alone).
    func testWhenEntitlementExcludesEveryCoreItemThenOnlyWhatSurvivesRemains() {
        let entitlement = EntitlementStatus(networkProtection: false, dataBrokerProtection: true,
                                            identityTheftRestoration: false, identityTheftRestorationGlobal: false,
                                            paidAIChat: false)

        XCTAssertEqual(makeProgress(isPIRAvailable: true, entitlement: entitlement).checklist, [.pir])
    }

    /// PIR has its own entitlement gate, independent of the other four: excluding only PIR's entitlement
    /// drops PIR without affecting the other four items.
    func testWhenEntitlementExcludesPIRThenTheChecklistDropsItEvenWhenAvailable() {
        let entitlement = EntitlementStatus(networkProtection: true, dataBrokerProtection: false,
                                            identityTheftRestoration: true, identityTheftRestorationGlobal: true,
                                            paidAIChat: true)

        XCTAssertEqual(makeProgress(isPIRAvailable: true, entitlement: entitlement).checklist,
                       [.vpn, .idtr, .duckAI])
    }

    /// `isPIRAvailable` and PIR's own entitlement are ANDed: either alone excludes it.
    func testWhenPIRIsUnavailableButEverythingElseIsEntitledThenPIRStillDrops() {
        XCTAssertEqual(makeProgress(isPIRAvailable: false, entitlement: .mockAllEnabled).checklist,
                       [.vpn, .idtr, .duckAI])
    }

    /// Nothing entitled and PIR unavailable: the checklist comes back genuinely empty. `Progress` doesn't
    /// recover from this itself — the launcher treats an empty checklist as an error and refuses to present
    /// the flow (see `SubscriptionOnboardingLauncherTests`).
    func testWhenNothingIsEntitledAndPIRIsUnavailableThenTheChecklistIsEmpty() {
        XCTAssertTrue(makeProgress(isPIRAvailable: false, entitlement: .empty).checklist.isEmpty)
    }

    func testWhenNothingIsCompleteThenPercentageIsZero() {
        XCTAssertEqual(makeProgress(isPIRAvailable: true).percentage, 0)
    }

    func testWhenOneOfFourIsCompleteThenPercentageIsTwentyFive() {
        XCTAssertEqual(makeProgress(isPIRAvailable: true, completed: [.vpn]).percentage, 25)
    }

    func testWhenEverythingButPIRIsCompleteThenPercentageIsSeventyFive() {
        let progress = makeProgress(isPIRAvailable: true, completed: [.vpn, .idtr, .duckAI])

        XCTAssertEqual(progress.percentage, 75)
    }

    /// The denominator is this customer's checklist, so a PIR-ineligible customer can still reach 100%.
    func testWhenPIRIsUnavailableThenTheSameThreeItemsReachOneHundred() {
        let progress = makeProgress(isPIRAvailable: false, completed: [.vpn, .idtr, .duckAI])

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

    // MARK: - Duck.ai fake completion

    func testWhenDuckAIIsDisabledAndNotYetCompleteThenItBecomesFakeCompleted() {
        sut.reconcileDuckAICompletion(isAIChatEnabled: false)

        XCTAssertTrue(sut.completedItems.contains(.duckAI))
        XCTAssertTrue(sut.reversibleCompletedItems.contains(.duckAI))
    }

    func testWhenDuckAIIsDisabledButAlreadyReallyCompleteThenItIsLeftAlone() {
        sut.markComplete(.duckAI)

        sut.reconcileDuckAICompletion(isAIChatEnabled: false)

        XCTAssertTrue(sut.completedItems.contains(.duckAI))
        XCTAssertFalse(sut.reversibleCompletedItems.contains(.duckAI))
    }

    func testWhenDuckAIIsReEnabledAndTheFlagIsSetThenItIsUncompletedAndTheFlagClears() {
        sut.reconcileDuckAICompletion(isAIChatEnabled: false)

        sut.reconcileDuckAICompletion(isAIChatEnabled: true)

        XCTAssertFalse(sut.completedItems.contains(.duckAI))
        XCTAssertFalse(sut.reversibleCompletedItems.contains(.duckAI))
    }

    func testWhenDuckAIIsReEnabledAndTheFlagIsNotSetThenItIsLeftAlone() {
        sut.markComplete(.duckAI)

        sut.reconcileDuckAICompletion(isAIChatEnabled: true)

        XCTAssertTrue(sut.completedItems.contains(.duckAI))
    }

    func testWhenCyclingDisabledAndEnabledRepeatedlyWithoutARealCompletionThenEachDirectionIsIdempotent() {
        sut.reconcileDuckAICompletion(isAIChatEnabled: false)
        sut.reconcileDuckAICompletion(isAIChatEnabled: false)
        XCTAssertTrue(sut.completedItems.contains(.duckAI))
        XCTAssertTrue(sut.reversibleCompletedItems.contains(.duckAI))

        sut.reconcileDuckAICompletion(isAIChatEnabled: true)
        sut.reconcileDuckAICompletion(isAIChatEnabled: true)
        XCTAssertFalse(sut.completedItems.contains(.duckAI))
        XCTAssertFalse(sut.reversibleCompletedItems.contains(.duckAI))

        sut.reconcileDuckAICompletion(isAIChatEnabled: false)
        XCTAssertTrue(sut.completedItems.contains(.duckAI))
        XCTAssertTrue(sut.reversibleCompletedItems.contains(.duckAI))
    }

    /// A real completion must win even while the flag is stale, so a later reconcile can't undo it.
    func testWhenARealCompletionArrivesWhileTheFlagIsStaleThenItWinsAndIsNotLaterUndone() {
        sut.reconcileDuckAICompletion(isAIChatEnabled: false)

        sut.markComplete(.duckAI)

        XCTAssertFalse(sut.reversibleCompletedItems.contains(.duckAI))

        sut.reconcileDuckAICompletion(isAIChatEnabled: true)

        XCTAssertTrue(sut.completedItems.contains(.duckAI))
    }

    /// `nil` must be a true no-op — passing `true` instead when reconciliation shouldn't run at all would
    /// incorrectly un-complete an item that's still fake-completed (e.g. a checklist already at 100%).
    func testWhenIsAIChatEnabledIsNilThenNothingChanges() {
        sut.reconcileDuckAICompletion(isAIChatEnabled: false)

        sut.reconcileDuckAICompletion(isAIChatEnabled: nil)

        XCTAssertTrue(sut.completedItems.contains(.duckAI))
        XCTAssertTrue(sut.reversibleCompletedItems.contains(.duckAI))
    }

    func testWhenProgressIsInitializedWithDuckAIDisabledThenDuckAIIsFakeCompleted() {
        let progress = makeProgress(isPIRAvailable: true, isAIChatEnabled: false)

        XCTAssertTrue(progress.completedItems.contains(.duckAI))
    }

    // MARK: - Reset

    func testWhenResettingThenEverythingReturnsToItsDefault() {
        sut.completedItems = [.vpn, .idtr, .duckAI, .pir]
        sut.reversibleCompletedItems = [.duckAI]
        sut.recordCardFirstShownIfNeeded(now: Date())
        _ = sut.recordFullyCompletedIfNeeded(now: Date())
        sut.recordCompletionView()
        sut.recordPostCheckoutFlowStartedIfNeeded(now: Date())

        sut.reset()

        XCTAssertTrue(sut.completedItems.isEmpty)
        XCTAssertTrue(sut.reversibleCompletedItems.isEmpty)
        XCTAssertNil(sut.cardFirstShownDate)
        XCTAssertNil(sut.fullyCompletedAt)
        XCTAssertEqual(sut.completionViewCount, 0)
        XCTAssertNil(sut.postCheckoutFlowStartedAt)
    }

    // MARK: - Setup card visibility

    func testWhenBelowOneHundredThenTheCardShowsAndTheSessionIsUntouched() {
        var progress = makeProgress(isPIRAvailable: true, completed: [.vpn])
        let session = SubscriptionOnboardingSessionState()

        XCTAssertTrue(progress.shouldShowSetupCard(now: Date(), session: session))
        XCTAssertFalse(session.didCompleteDuringThisSession)
    }

    func testWhenReachingOneHundredThenTheCardStillShowsForTheRestOfTheSession() {
        var progress = makeProgress(isPIRAvailable: false, completed: [.vpn, .idtr, .duckAI])
        let session = SubscriptionOnboardingSessionState()

        XCTAssertTrue(progress.shouldShowSetupCard(now: Date(), session: session))
        XCTAssertTrue(session.didCompleteDuringThisSession)
        // Asked again within the same session, so it must still show.
        XCTAssertTrue(progress.shouldShowSetupCard(now: Date(), session: session))
    }

    func testWhenCompletionHappenedInAnEarlierSessionThenTheCardIsHidden() {
        var progress = makeProgress(isPIRAvailable: false, completed: [.vpn, .idtr, .duckAI])
        _ = progress.shouldShowSetupCard(now: Date(), session: SubscriptionOnboardingSessionState())

        // A fresh session object is what the next app launch supplies.
        XCTAssertFalse(progress.shouldShowSetupCard(now: Date(), session: SubscriptionOnboardingSessionState()))
    }

    func testWhenReachingOneHundredThenTheCompletionDateIsRecordedOnce() {
        var progress = makeProgress(isPIRAvailable: false, completed: [.vpn, .idtr, .duckAI])
        let first = Date(timeIntervalSince1970: 1_000)

        _ = progress.shouldShowSetupCard(now: first, session: SubscriptionOnboardingSessionState())
        _ = progress.shouldShowSetupCard(now: first.addingTimeInterval(3_600),
                                        session: SubscriptionOnboardingSessionState())

        XCTAssertEqual(SubscriptionOnboardingProgressPersistor(keyValueStore: keyValueStore).fullyCompletedAt, first)
    }

    // MARK: - Setup card criteria ordering (three independent ORs; whichever fires first hides it)

    /// No relaunch happens here, so the view cap must be what hides it, not the session latch.
    func testWhenTwoViewsHappenWithinTheCompletingSessionThenTheViewCapHidesItFirst() {
        var progress = makeProgress(isPIRAvailable: false, completed: [.vpn, .idtr, .duckAI])
        let session = SubscriptionOnboardingSessionState()

        XCTAssertTrue(progress.shouldShowSetupCard(now: Date(), session: session))
        XCTAssertTrue(progress.shouldShowSetupCard(now: Date(), session: session))
        XCTAssertFalse(progress.shouldShowSetupCard(now: Date(), session: session))
        XCTAssertTrue(session.didCompleteDuringThisSession)
    }

    /// Below the view cap here, so the next-launch rule must be what hides it.
    func testWhenOnlyOneViewHappensBeforeARelaunchThenTheNextLaunchRuleHidesItFirst() {
        var progress = makeProgress(isPIRAvailable: false, completed: [.vpn, .idtr, .duckAI])
        _ = progress.shouldShowSetupCard(now: Date(), session: SubscriptionOnboardingSessionState())

        // A fresh session object is what the next app launch supplies.
        XCTAssertFalse(progress.shouldShowSetupCard(now: Date(), session: SubscriptionOnboardingSessionState()))
        XCTAssertEqual(SubscriptionOnboardingProgressPersistor(keyValueStore: keyValueStore).completionViewCount, 1)
    }

    /// The 14-day check is independent of the other two, so it can fire before either of them would.
    func testWhenFourteenDaysHavePassedThenTheWindowHidesItEvenBelowTheViewCapAndWithinTheCompletingSession() {
        var progress = makeProgress(isPIRAvailable: false, completed: [.vpn, .idtr, .duckAI])
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
        let progress = makeProgress(isPIRAvailable: false, completed: [.vpn, .idtr, .duckAI])
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
        let progress = makeProgress(isPIRAvailable: false, completed: [.vpn, .idtr, .duckAI])

        XCTAssertFalse(progress.previewShouldShowSetupCard(now: Date(), session: SubscriptionOnboardingSessionState()))
    }

    func testPreviewAgreesWithTheRealAnswerAfterCompletionInAnEarlierSession() {
        var progress = makeProgress(isPIRAvailable: false, completed: [.vpn, .idtr, .duckAI])
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
                              completed: Set<SubscriptionOnboardingChecklistItem> = [],
                              entitlement: EntitlementStatus = .mockAllEnabled,
                              isAIChatEnabled: Bool = true) -> SubscriptionOnboardingProgress {
        sut.completedItems = completed
        return SubscriptionOnboardingProgress(persistor: sut, isPIRAvailable: isPIRAvailable, entitlement: entitlement, isAIChatEnabled: isAIChatEnabled)
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

    // MARK: - Fully completed

    func testWhenNeverFullyCompletedThenTheDateIsNil() {
        XCTAssertNil(sut.fullyCompletedAt)
    }

    func testWhenRecordingFullyCompletedThenTheDateIsStoredAndTrueIsReturned() {
        let now = Date(timeIntervalSince1970: 1_000_000)

        let recorded = sut.recordFullyCompletedIfNeeded(now: now)

        XCTAssertTrue(recorded)
        XCTAssertEqual(sut.fullyCompletedAt, now)
    }

    func testWhenRecordingFullyCompletedAgainThenTheOriginalDateIsKeptAndFalseIsReturned() {
        let first = Date(timeIntervalSince1970: 1_000_000)
        let later = Date(timeIntervalSince1970: 2_000_000)

        let firstRecorded = sut.recordFullyCompletedIfNeeded(now: first)
        let secondRecorded = sut.recordFullyCompletedIfNeeded(now: later)

        XCTAssertTrue(firstRecorded)
        XCTAssertFalse(secondRecorded)
        XCTAssertEqual(sut.fullyCompletedAt, first)
    }

    // MARK: - Storage failures

    func testWhenReadFailsThenCompletedItemsIsEmptyRatherThanCrashing() {
        sut.completedItems = [.vpn]
        keyValueStore.errorToThrow = InMemoryThrowingStore.StubError.forced

        XCTAssertTrue(sut.completedItems.isEmpty)
    }

    func testWhenReadFailsThenDatesAreNilRatherThanCrashing() {
        sut.recordCardFirstShownIfNeeded(now: Date())
        keyValueStore.errorToThrow = InMemoryThrowingStore.StubError.forced

        XCTAssertNil(sut.cardFirstShownDate)
        XCTAssertNil(sut.fullyCompletedAt)
    }

    func testWhenWriteFailsThenTheValueIsSilentlyNotPersisted() {
        keyValueStore.errorToThrow = InMemoryThrowingStore.StubError.forced

        sut.completedItems = [.vpn]

        keyValueStore.errorToThrow = nil
        XCTAssertTrue(sut.completedItems.isEmpty)
    }

    // MARK: - Post-checkout flow started

    func testWhenFlowHasNeverStartedThenTheDateIsNil() {
        XCTAssertNil(sut.postCheckoutFlowStartedAt)
    }

    func testWhenRecordingFlowStartedThenTheDateIsStored() {
        let now = Date(timeIntervalSince1970: 1_000_000)

        sut.recordPostCheckoutFlowStartedIfNeeded(now: now)

        XCTAssertEqual(sut.postCheckoutFlowStartedAt, now)
    }

    func testWhenRecordingFlowStartedAgainThenTheOriginalDateIsKept() {
        let first = Date(timeIntervalSince1970: 1_000_000)
        let later = Date(timeIntervalSince1970: 2_000_000)

        sut.recordPostCheckoutFlowStartedIfNeeded(now: first)
        sut.recordPostCheckoutFlowStartedIfNeeded(now: later)

        XCTAssertEqual(sut.postCheckoutFlowStartedAt, first)
    }
}

/// A local stub rather than `PersistenceTestingUtils`
private final class InMemoryThrowingStore: ThrowingKeyValueStoring {

    enum StubError: Error {
        case forced
    }

    private var values: [String: Any] = [:]
    var errorToThrow: Error?

    func object(forKey key: String) throws -> Any? {
        if let errorToThrow { throw errorToThrow }
        return values[key]
    }

    func set(_ value: Any?, forKey key: String) throws {
        if let errorToThrow { throw errorToThrow }
        values[key] = value
    }

    func removeObject(forKey key: String) throws {
        if let errorToThrow { throw errorToThrow }
        values.removeValue(forKey: key)
    }
}
