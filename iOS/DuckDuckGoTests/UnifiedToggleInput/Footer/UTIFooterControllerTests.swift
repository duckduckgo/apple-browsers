//
//  UTIFooterControllerTests.swift
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

import AIChat
import XCTest
@testable import DuckDuckGo

@MainActor
final class UTIFooterControllerTests: XCTestCase {

    private var limitsProvider: StubUsageLimitsProvider!
    private var presenter: SpyUTIFooterPresenter!
    private var viewModel: DuckAiUsageWarningViewModel!
    private var selectedModel: (id: String?, shortName: String?) = (nil, nil)
    private var animationCount = 0
    private var sut: UTIFooterController!

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        limitsProvider = StubUsageLimitsProvider()
        presenter = SpyUTIFooterPresenter()
        selectedModel = (nil, nil)
        animationCount = 0
        viewModel = makeViewModel()
        sut = UTIFooterController(viewModel: viewModel,
                                  highUsageNotice: makeNoticeSource(),
                                  animator: { [unowned self] changes in
                                      animationCount += 1
                                      changes()
                                  })
        sut.presenter = presenter
    }

    override func tearDown() {
        sut = nil
        viewModel = nil
        presenter = nil
        limitsProvider = nil
        super.tearDown()
    }

    // MARK: - Refresh

    func test_refresh_presentsAMessageForTheResolvedWarning() {
        limitsProvider.limits = weeklyUsage(50)

        sut.refresh()

        XCTAssertEqual(presenter.appliedMessages.count, 1)
        XCTAssertTrue(presenter.appliedMessages.last??.title.contains("50%") ?? false)
    }

    func test_refresh_presentsNothingWhenThereIsNoWarning() {
        limitsProvider.limits = .noData

        sut.refresh()

        XCTAssertTrue(presenter.appliedMessages.isEmpty)
    }

    func test_refresh_doesNotReapplyAnUnchangedMessage() {
        limitsProvider.limits = weeklyUsage(50)

        sut.refresh()
        sut.refresh()

        XCTAssertEqual(presenter.appliedMessages.count, 1)
        XCTAssertEqual(animationCount, 1)
    }

    func test_refresh_animatesEveryVisibleChange() {
        limitsProvider.limits = weeklyUsage(50)
        sut.refresh()

        limitsProvider.limits = weeklyUsage(90)
        sut.refresh()

        XCTAssertEqual(animationCount, 2)
    }

    // MARK: - Dismissal

    func test_dismissCurrent_hidesTheFooter() {
        limitsProvider.limits = weeklyUsage(50)
        sut.refresh()

        sut.dismissCurrent()

        XCTAssertEqual(presenter.appliedMessages.last, .some(nil))
    }

    func test_dismissCurrent_keepsTheSameWarningHiddenOnTheNextRefresh() {
        limitsProvider.limits = weeklyUsage(50)
        sut.refresh()
        sut.dismissCurrent()

        sut.refresh()

        XCTAssertEqual(presenter.appliedMessages.last, .some(nil))
    }

    /// The dismissal is recorded against a rung of the redisplay ladder, so crossing the next one
    /// brings the card back.
    func test_dismissCurrent_doesNotHideTheNextThreshold() {
        limitsProvider.limits = weeklyUsage(50)
        sut.refresh()
        sut.dismissCurrent()

        limitsProvider.limits = weeklyUsage(90)
        sut.refresh()

        XCTAssertTrue(presenter.appliedMessages.last??.title.contains("90%") ?? false)
    }

    // MARK: - Suppression

    func test_setSuppressed_hidesTheFooterWithoutForgettingTheWarning() {
        limitsProvider.limits = weeklyUsage(50)
        sut.refresh()

        sut.setSuppressed(true)

        XCTAssertEqual(presenter.appliedMessages.last, .some(nil))
    }

    func test_setSuppressed_restoresTheWarningWithoutReadingTheSnapshotAgain() {
        limitsProvider.limits = weeklyUsage(50)
        sut.refresh()
        sut.setSuppressed(true)
        limitsProvider.readCount = 0

        sut.setSuppressed(false)

        XCTAssertEqual(limitsProvider.readCount, 0)
        XCTAssertTrue(presenter.appliedMessages.last??.title.contains("50%") ?? false)
    }

    func test_refresh_presentsNothingWhileSuppressed() {
        sut.setSuppressed(true)
        limitsProvider.limits = weeklyUsage(50)

        sut.refresh()

        XCTAssertTrue(presenter.appliedMessages.allSatisfy { $0 == nil })
    }

    // MARK: - Pose changes

    func test_resetForPoseChange_neverAppliesOrAnimatesAMessage() {
        limitsProvider.limits = weeklyUsage(50)
        sut.refresh()

        sut.resetForPoseChange()

        XCTAssertEqual(presenter.appliedMessages.count, 1)
        XCTAssertEqual(animationCount, 1)
    }

    func test_resetForPoseChange_dropsTheViewsPendingMessage() {
        limitsProvider.limits = weeklyUsage(50)
        sut.refresh()

        sut.resetForPoseChange()

        XCTAssertEqual(presenter.pendingClearCount, 1)
    }

    func test_refresh_afterAPoseResetWithTheWarningGone_hasNothingLeftToResurrect() {
        limitsProvider.limits = weeklyUsage(50)
        sut.refresh()
        sut.resetForPoseChange()

        limitsProvider.limits = .noData
        sut.refresh()

        // No second apply is needed precisely because the reset already dropped the view's pending copy.
        XCTAssertEqual(presenter.appliedMessages.count, 1)
        XCTAssertEqual(presenter.pendingClearCount, 1)
        XCTAssertNil(sut.currentMessage)
    }

    /// A pose reset is not a dismissal, so the same message comes back.
    func test_resetForPoseChange_reappliesTheWarningOnTheNextRefresh() {
        limitsProvider.limits = weeklyUsage(50)
        sut.refresh()
        sut.resetForPoseChange()

        sut.refresh()

        XCTAssertEqual(presenter.appliedMessages.count, 2)
        XCTAssertTrue(presenter.appliedMessages.last??.title.contains("50%") ?? false)
    }

    // MARK: - Actions

    func test_performPrimaryAction_forwardsTheResolvedAction() {
        var received: [DuckAiUsageAction] = []
        viewModel.onAction = { received.append($0) }
        limitsProvider.limits = weeklyUsage(50)
        sut.refresh()

        sut.performPrimaryAction()

        XCTAssertEqual(received, [.switchToModel(DuckAiModelSuggestion(modelId: "gpt-5.4-mini", modelShortName: "5.4 mini"))])
    }

    func test_performPrimaryAction_doesNothingWithoutAMessage() {
        var received: [DuckAiUsageAction] = []
        viewModel.onAction = { received.append($0) }

        sut.performPrimaryAction()

        XCTAssertTrue(received.isEmpty)
    }

    // MARK: - High-usage model notice

    func test_refresh_presentsTheHighUsageNoticeWhenThereIsNoWarning() {
        selectedModel = (id: "claude-opus-4-8", shortName: "Opus 4.8")
        limitsProvider.limits = .noData

        sut.refresh()

        XCTAssertTrue(presenter.appliedMessages.last??.title.contains("Opus 4.8") ?? false)
    }

    /// One slot: an actionable warning outranks the informational notice.
    func test_refresh_prefersTheUsageWarningOverTheNotice() {
        selectedModel = (id: "claude-opus-4-8", shortName: "Opus 4.8")
        limitsProvider.limits = weeklyUsage(50)

        sut.refresh()

        XCTAssertTrue(presenter.appliedMessages.last??.title.contains("50%") ?? false)
    }

    func test_refresh_presentsNothingForAModelThatIsNotHighUsage() {
        selectedModel = (id: "gpt-5.4-mini", shortName: "5.4 mini")
        limitsProvider.limits = .noData

        sut.refresh()

        XCTAssertTrue(presenter.appliedMessages.isEmpty)
    }

    /// Re-read per refresh, so switching onto a high-usage model mid-session surfaces the notice.
    func test_refresh_picksUpAModelChange() {
        limitsProvider.limits = .noData
        sut.refresh()

        selectedModel = (id: "claude-opus-4-8", shortName: "Opus 4.8")
        sut.refresh()

        XCTAssertTrue(presenter.appliedMessages.last??.title.contains("Opus 4.8") ?? false)
    }

    func test_dismissCurrent_keepsTheNoticeHiddenOnTheNextRefresh() {
        selectedModel = (id: "claude-opus-4-8", shortName: "Opus 4.8")
        limitsProvider.limits = .noData
        sut.refresh()

        sut.dismissCurrent()
        sut.refresh()

        XCTAssertEqual(presenter.appliedMessages.last, .some(nil))
    }

    /// The two dismissals are separate records: closing the warning must not also spend the notice's.
    func test_dismissCurrent_dismissesTheWarningWithoutSpendingTheNoticesDismissal() {
        selectedModel = (id: "claude-opus-4-8", shortName: "Opus 4.8")
        limitsProvider.limits = weeklyUsage(50)
        sut.refresh()

        sut.dismissCurrent()
        sut.refresh()

        XCTAssertTrue(presenter.appliedMessages.last??.title.contains("Opus 4.8") ?? false)
    }

    // MARK: - Helpers

    private func makeNoticeSource() -> UTIFooterHighUsageNoticeSource {
        UTIFooterHighUsageNoticeSource(dismissalStore: InMemoryDuckAiHighUsageNoticeDismissalStore(),
                                       modelProvider: { [unowned self] in selectedModel })
    }

    private func makeViewModel() -> DuckAiUsageWarningViewModel {
        DuckAiUsageWarningViewModel(
            limitsProvider: limitsProvider,
            tierProvider: { .plus },
            isInternalUser: { false },
            dismissalStore: InMemoryDuckAiUsageWarningDismissalStore(),
            modelSuggester: StubCheaperModelSuggester(),
            dateProvider: { [unowned self] in now }
        )
    }

    private func weeklyUsage(_ percent: Double) -> DuckAiUsageLimits {
        DuckAiUsageLimits(daily: nil,
                          weekly: DuckAiUsageLimitWindow(percentUsed: percent,
                                                         resetsAt: now.addingTimeInterval(172_800)))
    }
}

// MARK: - Test doubles

private final class StubUsageLimitsProvider: DuckAiUsageLimitsProviding {
    var limits: DuckAiUsageLimits = .noData
    var readCount = 0

    func currentUsageLimits() -> DuckAiUsageLimits {
        readCount += 1
        return limits
    }
}

private struct StubCheaperModelSuggester: DuckAiModelSuggesting {
    func cheaperModel() -> DuckAiModelSuggestionOutcome {
        .suggestion(DuckAiModelSuggestion(modelId: "gpt-5.4-mini", modelShortName: "5.4 mini"))
    }

    func freeModel() -> DuckAiModelSuggestionOutcome { .none(reason: .notApplicable) }
}

@MainActor
private final class SpyUTIFooterPresenter: UTIFooterPresenting {
    private(set) var appliedMessages: [UTIFooterMessage?] = []
    private(set) var pendingClearCount = 0

    func applyFooterMessage(_ message: UTIFooterMessage?) {
        appliedMessages.append(message)
    }

    func clearPendingFooterMessage() {
        pendingClearCount += 1
    }
}
