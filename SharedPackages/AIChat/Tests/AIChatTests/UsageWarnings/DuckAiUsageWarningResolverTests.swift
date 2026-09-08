//
//  DuckAiUsageWarningResolverTests.swift
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
@testable import AIChat

final class DuckAiUsageWarningResolverTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_755_000_000) // 2025-08-12T12:00:00Z
    private var dismissalStore: InMemoryDuckAiUsageWarningDismissalStore!
    private let switchTarget = DuckAiModelSuggestion(modelId: "haiku", modelShortName: "Haiku")

    override func setUp() {
        super.setUp()
        dismissalStore = InMemoryDuckAiUsageWarningDismissalStore()
    }

    override func tearDown() {
        dismissalStore = nil
        super.tearDown()
    }

    // MARK: - Rendering the notice web sent

    func testWhenThereIsNoNoticeThenNothingIsShown() {
        XCTAssertEqual(reason(.noData), .noNotice)
    }

    func testTheMessageIsTheNoticeID() {
        for id in [DuckAiUsageNotice.ID.approaching, .freeReached, .dailyReached,
                   .weeklyReachedDegraded, .weeklyReached] {
            XCTAssertEqual(resolve(snapshot(notice(id: id)))?.message, id, id.rawValue)
        }
    }

    /// Web caps the percentage; native shows what it was sent rather than recomputing it.
    func testTheWindowPercentAndResetComeStraightFromTheNotice() {
        let warning = resolve(snapshot(notice(id: .approaching, window: .weekly, percentUsed: 99,
                                              resetsAt: now.addingTimeInterval(3 * 24 * 3600))))

        XCTAssertEqual(warning?.window, .weekly)
        XCTAssertEqual(warning?.percent, 99)
        XCTAssertEqual(warning?.resetsIn, .days(3))
    }

    func testDismissibilityComesStraightFromTheNotice() {
        XCTAssertEqual(resolve(snapshot(notice(id: .approaching, dismissible: true)))?.isDismissible, true)
        XCTAssertEqual(resolve(snapshot(notice(id: .approaching, dismissible: false)))?.isDismissible, false)
        XCTAssertEqual(resolve(snapshot(notice(id: .weeklyReached, reached: true)))?.isDismissible, false)
    }

    // MARK: - CTAs

    func testSwitchToCheaperOffersTheResolvedModelAndThePicker() {
        let warning = resolve(snapshot(notice(id: .approaching), cta: DuckAiUsageCta(id: .switchToCheaper)),
                              suggestion: .suggestion(switchTarget))

        XCTAssertEqual(warning?.action, .switchToModel(switchTarget))
        XCTAssertTrue(warning?.offersModelPicker ?? false)
    }

    /// The free-model CTA is still a model switch, so it carries the `>` into the native picker.
    func testSwitchToFreeOffersTheResolvedModelAndThePicker() {
        let warning = resolve(snapshot(notice(id: .weeklyReachedDegraded, reached: true),
                                       cta: DuckAiUsageCta(id: .switchToFree)),
                              suggestion: .suggestion(switchTarget))

        XCTAssertEqual(warning?.action, .switchToFreeModel(switchTarget))
        XCTAssertTrue(warning?.offersModelPicker ?? false)
    }

    /// The contract's already-on-the-cheapest-model case, and also what happens when nothing web
    /// offered can handle the current draft.
    func testWhenNoModelSurvivesThenTheButtonGoesAndTheNoticeStays() {
        let warning = resolve(snapshot(notice(id: .approaching), cta: DuckAiUsageCta(id: .switchToCheaper)),
                              suggestion: .none(reason: .noTargetForSelectedModel))

        XCTAssertEqual(warning?.message, .approaching)
        XCTAssertNil(warning?.action)
        XCTAssertFalse(warning?.offersModelPicker ?? true)
    }

    func testSubscribeCopyFollowsTrialEligibility() {
        let cta = DuckAiUsageCta(id: .subscribe)

        XCTAssertEqual(resolve(snapshot(notice(id: .freeReached, reached: true), cta: cta),
                               isTrialEligible: true)?.action,
                       .tryForFree(isTrialEligible: true))
        XCTAssertEqual(resolve(snapshot(notice(id: .freeReached, reached: true), cta: cta),
                               isTrialEligible: false)?.action,
                       .tryForFree(isTrialEligible: false))
    }

    /// Web names the key and the value; native carries them through untouched.
    func testBypassWeeklyCarriesTheEntriesWebNamed() {
        let entries = [DuckAiNativeStorageEntry(key: "duckai.fixedCostWindowBypassResetAtById",
                                                value: "{\"day\":\"2026-08-22T00:00:00.000Z\"}")]
        let warning = resolve(snapshot(notice(id: .dailyReached, reached: true),
                                       cta: DuckAiUsageCta(id: .bypassWeekly, putEntries: entries)))

        XCTAssertEqual(warning?.action, .startUsingWeeklyLimit(entries: entries))
        XCTAssertFalse(warning?.offersModelPicker ?? true)
    }

    /// Nothing to write means nothing would happen on tap.
    func testBypassWeeklyWithNoEntriesOffersNoButton() {
        let warning = resolve(snapshot(notice(id: .dailyReached, reached: true),
                                       cta: DuckAiUsageCta(id: .bypassWeekly)))

        XCTAssertEqual(warning?.message, .dailyReached)
        XCTAssertNil(warning?.action)
    }

    func testANoticeWithoutACtaOffersNoButton() {
        XCTAssertNil(resolve(snapshot(notice(id: .weeklyReached, reached: true)))?.action)
    }

    // MARK: - Dismissal

    func testADismissedNoticeStaysHiddenForThatResetPeriod() {
        let notice = notice(id: .approaching)
        dismissalStore.setDismissal(DuckAiUsageWarningDismissal(notice: notice))

        XCTAssertEqual(reason(snapshot(notice)), .dismissedUntilReset)
    }

    /// Once the window rolls over, the record is stale and the message comes back — no threshold
    /// ladder involved, because web decides when to send the next notice.
    func testADismissalDoesNotOutliveItsResetPeriod() {
        dismissalStore.setDismissal(DuckAiUsageWarningDismissal(notice: notice(id: .approaching)))

        let nextPeriod = notice(id: .approaching, resetsAt: now.addingTimeInterval(2 * 24 * 3600))
        XCTAssertEqual(resolve(snapshot(nextPeriod))?.message, .approaching)
    }

    /// A dismissed approaching message must not hide the reached one that follows it.
    func testADismissalOnlyAppliesToItsOwnNotice() {
        dismissalStore.setDismissal(DuckAiUsageWarningDismissal(notice: notice(id: .approaching)))

        XCTAssertEqual(resolve(snapshot(notice(id: .dailyReached, reached: true)))?.message, .dailyReached)
    }

    // MARK: - Acting on a notice

    /// The payload it was offered from still says the limit is hit, so the same drawer would come
    /// straight back and read as the button having done nothing.
    func testANoticeActedOnStaysHiddenUntilWebPublishesAgain() {
        let notice = notice(id: .dailyReached, reached: true)
        let acted = snapshot(notice, signature: "snapshot-1")
        dismissalStore.setActedSnapshot(DuckAiUsageWarningActedSnapshot(noticeID: notice.id.rawValue,
                                                                       signature: "snapshot-1"))

        XCTAssertEqual(reason(acted), .actedOnThisSnapshot)
        XCTAssertEqual(resolve(snapshot(notice, signature: "snapshot-2"))?.message, .dailyReached)
    }

    func testActingOnOneNoticeDoesNotHideAnother() {
        dismissalStore.setActedSnapshot(DuckAiUsageWarningActedSnapshot(noticeID: "dailyReached",
                                                                       signature: "snapshot-1"))

        XCTAssertEqual(resolve(snapshot(notice(id: .weeklyReached, reached: true),
                                        signature: "snapshot-1"))?.message, .weeklyReached)
    }

    /// An unsigned snapshot can't be compared; showing the message again is the safe failure.
    func testAnUnsignedSnapshotIsNeverSuppressed() {
        let notice = notice(id: .dailyReached, reached: true)
        dismissalStore.setActedSnapshot(DuckAiUsageWarningActedSnapshot(noticeID: notice.id.rawValue,
                                                                       signature: "snapshot-1"))

        XCTAssertEqual(resolve(snapshot(notice, signature: nil))?.message, .dailyReached)
    }

    // MARK: - Helpers

    private func resolve(_ snapshot: DuckAiUsageSnapshot,
                         suggestion: DuckAiModelSuggestionOutcome = .none(reason: .notApplicable),
                         isTrialEligible: Bool = false) -> DuckAiUsageWarning? {
        let sut = DuckAiUsageWarningResolver(dismissalStore: dismissalStore,
                                            modelSuggester: StubModelSuggester(outcome: suggestion))
        guard case .warning(let warning, _) = sut.resolve(snapshot: snapshot,
                                                          isTrialEligible: isTrialEligible,
                                                          now: now) else { return nil }
        return warning
    }

    private func reason(_ snapshot: DuckAiUsageSnapshot) -> DuckAiUsageWarningResolver.NoWarningReason? {
        let sut = DuckAiUsageWarningResolver(dismissalStore: dismissalStore)
        guard case .none(let reason) = sut.resolve(snapshot: snapshot,
                                                   isTrialEligible: false,
                                                   now: now) else { return nil }
        return reason
    }

    private func notice(id: DuckAiUsageNotice.ID,
                        window: DuckAiUsageWindow = .daily,
                        percentUsed: Int = 75,
                        resetsAt: Date? = nil,
                        reached: Bool = false,
                        dismissible: Bool? = nil) -> DuckAiUsageNotice {
        DuckAiUsageNotice(id: id,
                          window: window,
                          percentUsed: percentUsed,
                          resetsAt: resetsAt ?? now.addingTimeInterval(5 * 3600),
                          reached: reached,
                          dismissible: dismissible ?? !reached)
    }

    private func snapshot(_ notice: DuckAiUsageNotice,
                          cta: DuckAiUsageCta? = nil,
                          signature: String? = "snapshot-1") -> DuckAiUsageSnapshot {
        DuckAiUsageSnapshot(notice: notice, cta: cta, signature: signature)
    }
}

struct StubModelSuggester: DuckAiModelSuggesting {
    let outcome: DuckAiModelSuggestionOutcome

    func resolve(_ cta: DuckAiUsageCta) -> DuckAiModelSuggestionOutcome { outcome }
}
