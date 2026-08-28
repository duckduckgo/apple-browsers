//
//  DuckAiUsageWarningViewModelTests.swift
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

final class DuckAiUsageWarningViewModelTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_755_000_000) // 2025-08-12T12:00:00Z
    private var snapshotProvider: StubUsageSnapshotProvider!
    private var dismissalStore: InMemoryDuckAiUsageWarningDismissalStore!

    override func setUp() {
        super.setUp()
        snapshotProvider = StubUsageSnapshotProvider()
        dismissalStore = InMemoryDuckAiUsageWarningDismissalStore()
    }

    override func tearDown() {
        snapshotProvider = nil
        dismissalStore = nil
        super.tearDown()
    }

    // MARK: - Gates

    /// The factory builds the view model with no provider at all when the flag is off, which has to
    /// stay distinguishable from having nothing to show.
    func testWhenTheFeatureIsInactiveThenNothingIsReadOrShown() {
        snapshotProvider.snapshot = snapshot(notice(id: .dailyReached, reached: true))
        let sut = makeSUT(isFeatureActive: false)

        sut.refresh()

        XCTAssertNil(sut.warning)
        XCTAssertEqual(snapshotProvider.readCount, 0)
    }

    /// An isolated session must never surface the regular session's usage.
    func testWhenInFireModeThenNothingIsReadOrShown() {
        snapshotProvider.snapshot = snapshot(notice(id: .dailyReached, reached: true))
        let sut = makeSUT(isFireMode: true)

        sut.refresh()

        XCTAssertNil(sut.warning)
        XCTAssertEqual(snapshotProvider.readCount, 0)
    }

    /// One coordinator serves both normal and fire tabs, so the state is re-read per refresh.
    func testFireStateIsReReadOnEveryRefresh() {
        snapshotProvider.snapshot = snapshot(notice(id: .dailyReached, reached: true))
        var isFireMode = false
        let sut = makeSUT(isFireMode: { isFireMode })

        sut.refresh()
        XCTAssertNotNil(sut.warning)

        isFireMode = true
        sut.refresh()
        XCTAssertNil(sut.warning)
    }

    // MARK: - Publishing

    func testPublishesTheNoticeWebSent() {
        snapshotProvider.snapshot = snapshot(notice(id: .weeklyReachedDegraded, window: .weekly, reached: true))
        let sut = makeSUT()

        sut.refresh()

        XCTAssertEqual(sut.warning?.message, .weeklyReachedDegraded)
        XCTAssertEqual(sut.warning?.window, .weekly)
    }

    func testClearDropsTheMessageWithoutRecordingAnything() {
        snapshotProvider.snapshot = snapshot(notice(id: .approaching))
        let sut = makeSUT()
        sut.refresh()

        sut.clear()

        XCTAssertNil(sut.warning)
        XCTAssertNil(dismissalStore.dismissal())
        XCTAssertNil(dismissalStore.actedSnapshot())
    }

    // MARK: - Dismissal

    func testDismissRecordsTheNoticeAndHidesIt() {
        snapshotProvider.snapshot = snapshot(notice(id: .approaching))
        let sut = makeSUT()
        sut.refresh()

        sut.dismiss()

        XCTAssertNil(sut.warning)
        XCTAssertEqual(dismissalStore.dismissal()?.noticeID, "approaching")
    }

    func testDismissIsANoOpForAStickyMessage() {
        snapshotProvider.snapshot = snapshot(notice(id: .dailyReached, reached: true))
        let sut = makeSUT()
        sut.refresh()

        sut.dismiss()

        XCTAssertNotNil(sut.warning)
        XCTAssertNil(dismissalStore.dismissal())
    }

    // MARK: - Actions

    func testPerformActionHandsTheActionToThePlatform() {
        let entries = [DuckAiNativeStorageEntry(key: "duckai.a", value: "{}")]
        snapshotProvider.snapshot = snapshot(notice(id: .dailyReached, reached: true),
                                             cta: DuckAiUsageCta(id: .bypassWeekly, putEntries: entries))
        let sut = makeSUT()
        var performed: [DuckAiUsageAction] = []
        sut.onAction = { performed.append($0) }
        sut.refresh()

        sut.performAction()

        XCTAssertEqual(performed, [.startUsingWeeklyLimit(entries: entries)])
    }

    /// The hand-off writes an opt-in the payload can't reflect until web republishes, so the same
    /// drawer must not come straight back — that would read as the tap having done nothing.
    func testTheWeeklyHandOffStandsItsMessageDownUntilWebPublishesAgain() {
        let entries = [DuckAiNativeStorageEntry(key: "duckai.a", value: "{}")]
        let reached = notice(id: .dailyReached, reached: true)
        snapshotProvider.snapshot = snapshot(reached,
                                             cta: DuckAiUsageCta(id: .bypassWeekly, putEntries: entries),
                                             signature: "snapshot-1")
        let sut = makeSUT()
        sut.refresh()

        sut.performAction()
        XCTAssertNil(sut.warning)

        // Same payload on the next activation: still nothing.
        sut.refresh()
        XCTAssertNil(sut.warning)

        // Web publishes again — whatever it now says is shown.
        snapshotProvider.snapshot = snapshot(notice(id: .weeklyReached, window: .weekly, reached: true),
                                             signature: "snapshot-2")
        sut.refresh()
        XCTAssertEqual(sut.warning?.message, .weeklyReached)
    }

    /// Switching is the whole point of the message, so leaving it up would read as the tap having done
    /// nothing — the payload still says 75% until web republishes against the new model.
    func testAModelSwitchStandsItsMessageDown() {
        let suggestion = DuckAiModelSuggestion(modelId: "haiku", modelShortName: "Haiku")
        snapshotProvider.snapshot = snapshot(notice(id: .approaching),
                                             cta: DuckAiUsageCta(id: .switchToCheaper),
                                             signature: "snapshot-1")
        let sut = makeSUT(suggestion: .suggestion(suggestion))
        sut.refresh()

        sut.performAction()
        XCTAssertNil(sut.warning)

        // Still nothing on the next activation, and back when web publishes against the new model.
        sut.refresh()
        XCTAssertNil(sut.warning)

        snapshotProvider.snapshot = snapshot(notice(id: .approaching), signature: "snapshot-2")
        sut.refresh()
        XCTAssertEqual(sut.warning?.message, .approaching)
    }

    /// The `>` applies the model itself, so it has to stand the message down the same way the button
    /// does — otherwise switching from the chevron reads as the tap having done nothing.
    func testAModelSwitchFromTheChevronStandsItsMessageDown() {
        snapshotProvider.snapshot = snapshot(notice(id: .approaching),
                                             cta: DuckAiUsageCta(id: .switchToCheaper),
                                             signature: "snapshot-1")
        let sut = makeSUT(suggestion: .suggestion(DuckAiModelSuggestion(modelId: "haiku", modelShortName: "Haiku")))
        sut.refresh()

        sut.modelSwitchedFromMessage()

        XCTAssertNil(sut.warning)
        XCTAssertEqual(dismissalStore.actedSnapshot()?.noticeID, "approaching")
    }

    /// Only a message that offers the picker can be stood down by it.
    func testAChevronSwitchIsIgnoredWhenTheMessageOffersNoPicker() {
        snapshotProvider.snapshot = snapshot(notice(id: .freeReached, reached: true),
                                             cta: DuckAiUsageCta(id: .subscribe))
        let sut = makeSUT()
        sut.refresh()

        sut.modelSwitchedFromMessage()

        XCTAssertEqual(sut.warning?.message, .freeReached)
        XCTAssertNil(dismissalStore.actedSnapshot())
    }

    /// The free-model switch behaves the same way.
    func testTheFreeModelSwitchStandsItsMessageDown() {
        let suggestion = DuckAiModelSuggestion(modelId: "mistral-small", modelShortName: "Mistral Small")
        snapshotProvider.snapshot = snapshot(notice(id: .weeklyReachedDegraded, window: .weekly, reached: true),
                                             cta: DuckAiUsageCta(id: .switchToFree))
        let sut = makeSUT(suggestion: .suggestion(suggestion))
        sut.refresh()

        sut.performAction()

        XCTAssertNil(sut.warning)
    }

    /// The upsell opens a flow the user may never finish, and their usage is exactly as it was until
    /// they do.
    func testTheUpsellDoesNotStandItsMessageDown() {
        snapshotProvider.snapshot = snapshot(notice(id: .freeReached, reached: true),
                                             cta: DuckAiUsageCta(id: .subscribe))
        let sut = makeSUT()
        sut.refresh()

        sut.performAction()

        XCTAssertEqual(sut.warning?.message, .freeReached)
        XCTAssertNil(dismissalStore.actedSnapshot())
    }

    func testPerformActionIsANoOpWithoutAButton() {
        snapshotProvider.snapshot = snapshot(notice(id: .weeklyReached, window: .weekly, reached: true))
        let sut = makeSUT()
        var performed = 0
        sut.onAction = { _ in performed += 1 }
        sut.refresh()

        sut.performAction()

        XCTAssertEqual(performed, 0)
    }

    func testTheModelPickerOnlyOpensForAModelSwitch() {
        snapshotProvider.snapshot = snapshot(notice(id: .freeReached, reached: true),
                                             cta: DuckAiUsageCta(id: .subscribe))
        let sut = makeSUT()
        var opened = 0
        sut.onOpenModelPicker = { opened += 1 }
        sut.refresh()

        sut.openModelPicker()

        XCTAssertEqual(opened, 0)
    }

    // MARK: - Helpers

    private func makeSUT(isFeatureActive: Bool = true,
                         suggestion: DuckAiModelSuggestionOutcome = .none(reason: .notApplicable),
                         isTrialEligible: Bool = false,
                         isFireMode: Bool) -> DuckAiUsageWarningViewModel {
        makeSUT(isFeatureActive: isFeatureActive,
                suggestion: suggestion,
                isTrialEligible: isTrialEligible,
                isFireMode: { isFireMode })
    }

    private func makeSUT(isFeatureActive: Bool = true,
                         suggestion: DuckAiModelSuggestionOutcome = .none(reason: .notApplicable),
                         isTrialEligible: Bool = false,
                         isFireMode: @escaping () -> Bool = { false }) -> DuckAiUsageWarningViewModel {
        DuckAiUsageWarningViewModel(
            snapshotProvider: isFeatureActive ? snapshotProvider : nil,
            dismissalStore: dismissalStore,
            modelSuggester: StubModelSuggester(outcome: suggestion),
            isTrialEligible: { isTrialEligible },
            isFireMode: isFireMode,
            dateProvider: { self.now }
        )
    }

    private func notice(id: DuckAiUsageNotice.ID,
                        window: DuckAiUsageWindow = .daily,
                        resetsAt: Date? = nil,
                        reached: Bool = false) -> DuckAiUsageNotice {
        DuckAiUsageNotice(id: id,
                          window: window,
                          percentUsed: reached ? 100 : 75,
                          resetsAt: resetsAt ?? now.addingTimeInterval(5 * 3600),
                          reached: reached,
                          dismissible: !reached)
    }

    private func snapshot(_ notice: DuckAiUsageNotice,
                          cta: DuckAiUsageCta? = nil,
                          signature: String? = "snapshot-1") -> DuckAiUsageSnapshot {
        DuckAiUsageSnapshot(notice: notice, cta: cta, signature: signature)
    }
}

private final class StubUsageSnapshotProvider: DuckAiUsageSnapshotProviding {
    var snapshot: DuckAiUsageSnapshot = .noData
    private(set) var readCount = 0

    func currentSnapshot() -> DuckAiUsageSnapshot {
        readCount += 1
        return snapshot
    }
}
