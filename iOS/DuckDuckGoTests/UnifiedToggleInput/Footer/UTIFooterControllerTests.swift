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
    private var dismissalStore: InMemoryDuckAiUsageWarningDismissalStore!
    private var presenter: SpyUTIFooterPresenter!
    private var viewModel: DuckAiUsageWarningViewModel!
    private var measurementFiring: RecordingUsageWarningPixelFiring!
    private var createImagePixelFiring: MockCreateImagePixelFiring!
    private var selectedModel: (id: String?, shortName: String?) = (nil, nil)
    private var animationCount = 0
    private var sut: UTIFooterController!

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        limitsProvider = StubUsageLimitsProvider()
        dismissalStore = InMemoryDuckAiUsageWarningDismissalStore()
        presenter = SpyUTIFooterPresenter()
        measurementFiring = RecordingUsageWarningPixelFiring()
        createImagePixelFiring = MockCreateImagePixelFiring()
        selectedModel = (nil, nil)
        animationCount = 0
        viewModel = makeViewModel()
        sut = UTIFooterController(viewModel: viewModel,
                                  highUsageNotice: makeNoticeSource(),
                                  measurement: DuckAiUsageWarningMeasurement(pixelFiring: measurementFiring),
                                  createImagePixelFiring: createImagePixelFiring,
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
        measurementFiring = nil
        createImagePixelFiring = nil
        dismissalStore = nil
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
    /// Per the spec an approaching message is suppressed until `resetsAt`, so a higher percentage in
    /// the same period is the same message and stays gone.
    func test_dismissCurrent_keepsTheSameNoticeHiddenForThatResetPeriod() {
        limitsProvider.limits = weeklyUsage(50)
        sut.refresh()
        sut.dismissCurrent()

        limitsProvider.limits = weeklyUsage(90)
        sut.refresh()

        XCTAssertEqual(presenter.appliedMessages.last, .some(nil))
    }

    /// A dismissed approaching message must not take the reached one with it.
    func test_dismissCurrent_doesNotHideADifferentNotice() {
        limitsProvider.limits = weeklyUsage(50)
        sut.refresh()
        sut.dismissCurrent()

        limitsProvider.limits = weeklyReached()
        sut.refresh()

        XCTAssertTrue(presenter.appliedMessages.last??.title.contains("Weekly usage limit reached") ?? false)
    }

    // MARK: - Model switch

    /// Picking the model the message offered from the bar's picker settles it as the CTA would.
    func test_userSwitchedModel_hidesTheFooterWhenTheModelIsTheOneOffered() {
        limitsProvider.limits = weeklyUsage(75)
        sut.refresh()

        sut.userSwitchedModel(from: "gpt-5.4", to: "gpt-5.4-mini")

        XCTAssertEqual(presenter.appliedMessages.last, .some(nil))
    }

    func test_userSwitchedModel_keepsTheMessageHiddenUntilWebPublishesAgain() {
        limitsProvider.limits = weeklyUsage(75)
        sut.refresh()
        sut.userSwitchedModel(from: "gpt-5.4", to: "gpt-5.4-mini")

        sut.refresh()
        XCTAssertEqual(presenter.appliedMessages.last, .some(nil))

        limitsProvider.limits = weeklyUsage(80)
        sut.refresh()
        XCTAssertTrue(presenter.appliedMessages.last??.title.contains("80%") ?? false)
    }

    /// A heavier or sideways switch has not dealt with the message.
    func test_userSwitchedModel_leavesTheFooterUpWhenTheModelIsNotOneOffered() {
        limitsProvider.limits = weeklyUsage(75)
        sut.refresh()

        sut.userSwitchedModel(from: "gpt-5.4", to: "claude-opus")

        XCTAssertEqual(presenter.appliedMessages.count, 1)
        XCTAssertNotNil(presenter.appliedMessages.last ?? nil)
    }

    func test_userSwitchedModel_leavesAMessageThatAskedForNoSwitchUp() {
        limitsProvider.limits = weeklyReachedWithUpsell()
        sut.refresh()

        sut.userSwitchedModel(from: "gpt-5.4", to: "gpt-5.4-mini")

        XCTAssertEqual(presenter.appliedMessages.count, 1)
        XCTAssertNotNil(presenter.appliedMessages.last ?? nil)
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

    /// Acting on the message retires it, exactly as the close button would.
    func test_performPrimaryAction_hidesTheMessageWhenItSwitchesModel() {
        limitsProvider.limits = weeklyUsage(50)
        sut.refresh()

        sut.performPrimaryAction()

        XCTAssertEqual(presenter.appliedMessages.last, .some(nil))
    }

    func test_performPrimaryAction_keepsTheMessageHiddenOnTheNextRefresh() {
        limitsProvider.limits = weeklyUsage(50)
        sut.refresh()
        sut.performPrimaryAction()

        sut.refresh()

        XCTAssertEqual(presenter.appliedMessages.last, .some(nil))
    }

    /// Recorded against a rung like a close, not a blanket kill, so the next one still shows.
    /// Acting is keyed to the snapshot, not the reset period: a republished snapshot is web's answer
    /// to what the user just did, so the message it carries is shown.
    func test_performPrimaryAction_showsTheMessageAgainWhenWebRepublishes() {
        limitsProvider.limits = weeklyUsage(50)
        sut.refresh()
        sut.performPrimaryAction()
        XCTAssertEqual(presenter.appliedMessages.last, .some(nil))

        limitsProvider.limits = weeklyUsage(90)
        sut.refresh()

        XCTAssertTrue(presenter.appliedMessages.last??.title.contains("90%") ?? false)
    }

    /// Web republishing the same message under a new payload right after the switch must not read as
    /// the button having done nothing.
    func test_performPrimaryAction_keepsAnIdenticalRepublishedMessageHidden() {
        limitsProvider.limits = weeklyUsage(50)
        sut.refresh()
        sut.performPrimaryAction()

        limitsProvider.limits = weeklyUsage(50, signature: "snapshot-50-republished")
        sut.refresh()

        XCTAssertEqual(presenter.appliedMessages.last, .some(nil))
    }

    /// The debug menu clears the persisted record; the controller's own copy must not outlive it.
    func test_performPrimaryAction_showsTheMessageAgainOnceTheActedRecordIsCleared() {
        limitsProvider.limits = weeklyUsage(50)
        sut.refresh()
        sut.performPrimaryAction()
        XCTAssertEqual(presenter.appliedMessages.last, .some(nil))

        dismissalStore.setActedSnapshot(nil)
        sut.refresh()

        XCTAssertTrue(presenter.appliedMessages.last??.title.contains("50%") ?? false)
    }

    /// The upsell is not a switch: the user is still blocked, so the message stays up.
    func test_performPrimaryAction_keepsTheMessageWhenTheActionIsTheUpsell() {
        limitsProvider.limits = DuckAiUsageSnapshot(
            notice: DuckAiUsageNotice(id: .freeReached,
                                      window: .daily,
                                      percentUsed: 100,
                                      resetsAt: now.addingTimeInterval(172_800),
                                      reached: true,
                                      dismissible: false),
            cta: DuckAiUsageCta(id: .subscribe),
            signature: "snapshot-free-reached"
        )
        sut.refresh()

        sut.performPrimaryAction()

        XCTAssertEqual(presenter.appliedMessages.last??.primaryAction?.title, "Subscribe")
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

    // MARK: - Create Image model switch notice

    func test_showModelSwitchNotice_presentsTheNotice() {
        sut.showModelSwitchNotice(modelSwitchNotice())

        XCTAssertEqual(presenter.appliedMessages.last??.icon, .modelSwitch)
        XCTAssertEqual(presenter.appliedMessages.last??.title, "Now using 5.6 Luna")
    }

    /// One slot, two sources. The switch is something the app just did to the user's selection, so it
    /// outranks a usage warning that will still be there afterwards.
    func test_showModelSwitchNotice_takesTheSlotFromAVisibleUsageWarning() {
        limitsProvider.limits = weeklyUsage(50)
        sut.refresh()

        sut.showModelSwitchNotice(modelSwitchNotice())

        XCTAssertEqual(presenter.appliedMessages.last??.icon, .modelSwitch)
    }

    func test_clearModelSwitchNotice_handsTheSlotBackToTheUsageWarning() {
        limitsProvider.limits = weeklyUsage(50)
        sut.refresh()
        sut.showModelSwitchNotice(modelSwitchNotice())

        sut.clearModelSwitchNotice()

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

    func test_clearModelSwitchNotice_hidesTheFooterWhenThereIsNoWarningBehindIt() {
        sut.showModelSwitchNotice(modelSwitchNotice())

        sut.clearModelSwitchNotice()

        XCTAssertEqual(presenter.appliedMessages.last, .some(nil))
    }

    /// Called on every tools refresh, so it has to be free when there is nothing to clear.
    func test_clearModelSwitchNotice_doesNothingWhenNoNoticeIsStored() {
        limitsProvider.limits = weeklyUsage(50)
        sut.refresh()

        sut.clearModelSwitchNotice()

        XCTAssertEqual(presenter.appliedMessages.count, 1)
        XCTAssertEqual(animationCount, 1)
    }

    /// The usage-warning dismissal is persisted. Routing the notice's close button into it would
    /// silently retire a limit warning the user never saw.
    func test_dismissCurrent_whileTheNoticeIsVisible_doesNotDismissTheUsageWarning() {
        limitsProvider.limits = weeklyUsage(50)
        sut.refresh()
        sut.showModelSwitchNotice(modelSwitchNotice())

        sut.dismissCurrent()

        XCTAssertTrue(presenter.appliedMessages.last??.title.contains("50%") ?? false)
    }

    func test_dismissCurrent_whileTheNoticeIsVisible_dropsTheNoticeForGood() {
        sut.showModelSwitchNotice(modelSwitchNotice())
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

    // MARK: - Measurement

    /// The card is resolved while the input is still collapsed and revealed inside the expand
    /// animation, so resolving a message is not yet an appearance.
    func test_refresh_reportsNoImpressionUntilTheCardIsOnScreen() {
        limitsProvider.limits = weeklyUsage(75)

        sut.refresh()

        XCTAssertTrue(measurementFiring.events.isEmpty)
    }

    func test_footerVisibilityChanged_reportsAnImpressionForTheVisibleMessage() {
        limitsProvider.limits = weeklyUsage(75)
        sut.refresh()

        sut.footerVisibilityChanged(isVisible: true)

        XCTAssertEqual(measurementFiring.events, [.shown(approachingExposure(percentBucket: 75))])
    }

    func test_footerVisibilityChanged_reportsTheNoticesModelWhenTheNoticeIsVisible() {
        selectedModel = (id: "claude-opus-4-8", shortName: "Opus 4.8")
        limitsProvider.limits = .noData
        sut.refresh()

        sut.footerVisibilityChanged(isVisible: true)

        XCTAssertEqual(measurementFiring.events,
                       [.shown(DuckAiUsageWarningExposure(kind: .highUsageModelNotice, modelId: "claude-opus-4-8"))])
    }

    func test_dismissCurrent_reportsADismissal() {
        limitsProvider.limits = weeklyUsage(75)
        sut.refresh()
        sut.footerVisibilityChanged(isVisible: true)

        sut.dismissCurrent()

        XCTAssertEqual(measurementFiring.events.last, .dismissed(approachingExposure(percentBucket: 75)))
    }

    /// Acting on the message retires it internally, which is not the user closing it.
    func test_performPrimaryAction_reportsTheCTATapAndNoDismissal() {
        limitsProvider.limits = weeklyUsage(75)
        sut.refresh()
        sut.footerVisibilityChanged(isVisible: true)

        sut.performPrimaryAction()

        XCTAssertEqual(measurementFiring.events,
                       [.shown(approachingExposure(percentBucket: 75)),
                        .switchModelTapped(approachingExposure(percentBucket: 75))])
    }

    func test_performPrimaryAction_reportsTheUpsellCTAWhenTheBlockedStateOffersTheSubscription() {
        limitsProvider.limits = weeklyReachedWithUpsell()
        sut.refresh()
        sut.footerVisibilityChanged(isVisible: true)

        sut.performPrimaryAction()

        XCTAssertEqual(measurementFiring.events.last,
                       .upsellTapped(DuckAiUsageWarningExposure(kind: .limitReached, window: .weekly)))
    }

    func test_recordPromptSubmitted_reportsAgainstTheWarningTheUserSaw() {
        limitsProvider.limits = weeklyUsage(75)
        sut.refresh()
        sut.footerVisibilityChanged(isVisible: true)

        sut.recordPromptSubmitted()

        XCTAssertEqual(measurementFiring.events.last, .promptSubmitted(approachingExposure(percentBucket: 75)))
    }

    func test_userSwitchedModel_reportsAgainstTheWarningTheUserSaw() {
        limitsProvider.limits = weeklyUsage(75)
        sut.refresh()
        sut.footerVisibilityChanged(isVisible: true)

        sut.userSwitchedModel(from: "gpt-5.4", to: "gpt-5.4-mini")

        XCTAssertEqual(measurementFiring.events.last, .modelSwitched(approachingExposure(percentBucket: 75)))
    }

    /// The pixel is about what the user did, not whether it settled the message.
    func test_userSwitchedModel_reportsASwitchThatLeavesTheMessageUp() {
        limitsProvider.limits = weeklyUsage(75)
        sut.refresh()
        sut.footerVisibilityChanged(isVisible: true)

        sut.userSwitchedModel(from: "gpt-5.4", to: "claude-opus")

        XCTAssertEqual(measurementFiring.events.last, .modelSwitched(approachingExposure(percentBucket: 75)))
    }

    func test_resetForPoseChange_endsTheExposureWithNoFollowThrough() {
        limitsProvider.limits = weeklyUsage(75)
        sut.refresh()
        sut.footerVisibilityChanged(isVisible: true)

        sut.resetForPoseChange()

        XCTAssertEqual(measurementFiring.events.last, .abandoned(approachingExposure(percentBucket: 75)))
    }

    func test_setSuppressed_endsTheExposure() {
        limitsProvider.limits = weeklyUsage(75)
        sut.refresh()
        sut.footerVisibilityChanged(isVisible: true)

        sut.setSuppressed(true)

        XCTAssertEqual(measurementFiring.events.last, .abandoned(approachingExposure(percentBucket: 75)))
    }

    /// The notice carries no action, so the existing CTA guard already filters it out.
    func test_performPrimaryAction_whileTheNoticeIsVisible_doesNothing() {
        var received: [DuckAiUsageAction] = []
        viewModel.onAction = { received.append($0) }
        limitsProvider.limits = weeklyUsage(50)
        sut.refresh()
        sut.showModelSwitchNotice(modelSwitchNotice())

        sut.performPrimaryAction()

        XCTAssertTrue(received.isEmpty)
    }

    func test_setSuppressed_hidesTheNoticeToo() {
        sut.showModelSwitchNotice(modelSwitchNotice())

        sut.setSuppressed(true)

        XCTAssertEqual(presenter.appliedMessages.last, .some(nil))
    }

    /// A pose change is not a dismissal — collapsing and expanding must not eat the notice.
    /// The count matters: had the reset dropped the notice, `refresh` would resolve to nil, no-op on
    /// the unchanged comparison, and leave the first apply as `last` — passing for the wrong reason.
    func test_resetForPoseChange_keepsTheNoticeForTheNextRefresh() {
        sut.showModelSwitchNotice(modelSwitchNotice())
        sut.resetForPoseChange()

        sut.refresh()

        XCTAssertEqual(presenter.appliedMessages.count, 2)
        XCTAssertEqual(presenter.appliedMessages.last??.icon, .modelSwitch)
        XCTAssertEqual(sut.currentMessage?.icon, .modelSwitch)
    }

    /// The switch card is not one of the three usage-warning states, so it carries no exposure.
    func test_footerVisibilityChanged_reportsNoImpressionForTheModelSwitchNotice() {
        limitsProvider.limits = weeklyUsage(75)
        sut.refresh()
        sut.showModelSwitchNotice(modelSwitchNotice())

        sut.footerVisibilityChanged(isVisible: true)

        XCTAssertTrue(measurementFiring.events.isEmpty)
    }

    /// The warning's exposure outlives its card. Closing the switch card must not spend it as a
    /// dismissal the user never made.
    func test_dismissCurrent_whileTheNoticeIsVisible_reportsNoDismissal() {
        limitsProvider.limits = weeklyUsage(75)
        sut.refresh()
        sut.footerVisibilityChanged(isVisible: true)
        sut.showModelSwitchNotice(modelSwitchNotice())

        sut.dismissCurrent()

        XCTAssertEqual(measurementFiring.events, [.shown(approachingExposure(percentBucket: 75))])
    }

    // MARK: - Create Image pixels

    func test_createImagePixels_whenTheUserClosesTheNotice_reportsTheDismissal() {
        sut.showModelSwitchNotice(modelSwitchNotice())

        sut.dismissCurrent()

        XCTAssertEqual(createImagePixelFiring.noticeDismissedCount, 1)
    }

    func test_createImagePixels_whenTheNoticeIsClearedAutomatically_reportsNothing() {
        sut.showModelSwitchNotice(modelSwitchNotice())

        sut.clearModelSwitchNotice()

        XCTAssertTrue(createImagePixelFiring.isEmpty)
    }

    func test_createImagePixels_whenThePoseChangesWhileTheNoticeIsStored_reportsNothing() {
        sut.showModelSwitchNotice(modelSwitchNotice())

        sut.resetForPoseChange()

        XCTAssertTrue(createImagePixelFiring.isEmpty)
    }

    func test_createImagePixels_whenTheInputIsSuppressedWhileTheNoticeIsStored_reportsNothing() {
        sut.showModelSwitchNotice(modelSwitchNotice())

        sut.setSuppressed(true)

        XCTAssertTrue(createImagePixelFiring.isEmpty)
    }

    func test_createImagePixels_whenTheUserClosesAUsageWarning_reportsNothing() {
        limitsProvider.limits = weeklyUsage(50)
        sut.refresh()

        sut.dismissCurrent()

        XCTAssertTrue(createImagePixelFiring.isEmpty)
    }

    func test_createImagePixels_whenTheNoticeAndThenTheWarningAreClosed_reportsOneDismissal() {
        limitsProvider.limits = weeklyUsage(50)
        sut.refresh()
        sut.showModelSwitchNotice(modelSwitchNotice())

        sut.dismissCurrent()
        sut.dismissCurrent()

        XCTAssertEqual(createImagePixelFiring.noticeDismissedCount, 1)
    }

    func test_createImagePixels_whenThePrimaryActionRunsWhileTheNoticeIsVisible_reportsNothing() {
        sut.showModelSwitchNotice(modelSwitchNotice())

        sut.performPrimaryAction()

        XCTAssertTrue(createImagePixelFiring.isEmpty)
    }

    // MARK: - Helpers

    private func approachingExposure(percentBucket: Int) -> DuckAiUsageWarningExposure {
        DuckAiUsageWarningExposure(kind: .approaching, window: .weekly, percentBucket: percentBucket)
    }

    private func makeNoticeSource() -> UTIFooterHighUsageNoticeSource {
        UTIFooterHighUsageNoticeSource(dismissalStore: InMemoryDuckAiHighUsageNoticeDismissalStore(),
                                       modelProvider: { [unowned self] in selectedModel })
    }

    private func modelSwitchNotice(previousShortName: String = "Mistral",
                                   newShortName: String = "5.6 Luna") -> CreateImageModelSwitchNotice {
        CreateImageModelSwitchNotice(
            previousModel: model(shortName: previousShortName, provider: .mistral),
            newModel: model(shortName: newShortName, provider: .openAI)
        )
    }

    private func model(shortName: String, provider: AIChatModel.ModelProvider) -> AIChatModel {
        AIChatModel(id: shortName.lowercased(),
                    name: shortName,
                    shortName: shortName,
                    provider: provider,
                    supportsImageUpload: false,
                    entityHasAccess: true)
    }

    private func makeViewModel() -> DuckAiUsageWarningViewModel {
        DuckAiUsageWarningViewModel(
            snapshotProvider: limitsProvider,
            dismissalStore: dismissalStore,
            modelSuggester: StubCheaperModelSuggester(),
            dateProvider: { [unowned self] in now }
        )
    }

    /// An approaching notice with a cheaper-model CTA — what the footer shows most of the time.
    private func weeklyUsage(_ percent: Int, signature: String? = nil) -> DuckAiUsageSnapshot {
        DuckAiUsageSnapshot(
            notice: DuckAiUsageNotice(id: .approaching,
                                      window: .weekly,
                                      percentUsed: percent,
                                      resetsAt: now.addingTimeInterval(172_800),
                                      reached: false,
                                      dismissible: true),
            cta: DuckAiUsageCta(id: .switchToCheaper,
                                target: .init(modelId: "gpt-5.4-mini", modelIds: ["gpt-5.4-mini"])),
            signature: signature ?? "snapshot-\(percent)"
        )
    }

    /// A blocked state whose only offer is the subscription upsell.
    private func weeklyReachedWithUpsell() -> DuckAiUsageSnapshot {
        DuckAiUsageSnapshot(
            notice: DuckAiUsageNotice(id: .weeklyReached,
                                      window: .weekly,
                                      percentUsed: 100,
                                      resetsAt: now.addingTimeInterval(172_800),
                                      reached: true,
                                      dismissible: false),
            cta: DuckAiUsageCta(id: .subscribe),
            signature: "snapshot-reached-upsell"
        )
    }

    private func weeklyReached() -> DuckAiUsageSnapshot {
        DuckAiUsageSnapshot(
            notice: DuckAiUsageNotice(id: .weeklyReached,
                                      window: .weekly,
                                      percentUsed: 100,
                                      resetsAt: now.addingTimeInterval(172_800),
                                      reached: true,
                                      dismissible: false),
            cta: nil,
            signature: "snapshot-reached"
        )
    }
}

// MARK: - Test doubles

private final class StubUsageLimitsProvider: DuckAiUsageSnapshotProviding {
    var limits: DuckAiUsageSnapshot = .noData
    var readCount = 0

    func currentSnapshot() -> DuckAiUsageSnapshot {
        readCount += 1
        return limits
    }
}

private struct StubCheaperModelSuggester: DuckAiModelSuggesting {
    func resolve(_ cta: DuckAiUsageCta) -> DuckAiModelSuggestionOutcome {
        .suggestion(DuckAiModelSuggestion(modelId: "gpt-5.4-mini", modelShortName: "5.4 mini"))
    }
}

private final class RecordingUsageWarningPixelFiring: DuckAiUsageWarningPixelFiring {
    private(set) var events: [DuckAiUsageWarningMeasurementEvent] = []

    func fire(_ event: DuckAiUsageWarningMeasurementEvent) {
        events.append(event)
    }
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
