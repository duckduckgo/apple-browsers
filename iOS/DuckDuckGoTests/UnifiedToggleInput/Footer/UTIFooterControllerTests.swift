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
    private var allowsSubscriptionUpsell = true
    private var isTrialEligible = false
    private var animationCount = 0
    private var reportedBlocks: [Bool] = []
    private var sut: UTIFooterController!
    private var privacyKind: AttachmentPrivacyPixel.Kind?
    private var privacyEnabled = true
    private var privacyDisplayStore: PrivacyDisplayStore!
    private var privacyEvents: [AttachmentPrivacyPixel.Action] = []
    private var privacyEventKinds: [AttachmentPrivacyPixel.Kind] = []

    private var now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
#if DEBUG || ALPHA
        UTIFooterDebugOverrides.clearTermsPreview()
#endif
        now = Date(timeIntervalSince1970: 1_800_000_000)
        limitsProvider = StubUsageLimitsProvider()
        dismissalStore = InMemoryDuckAiUsageWarningDismissalStore()
        presenter = SpyUTIFooterPresenter()
        measurementFiring = RecordingUsageWarningPixelFiring()
        createImagePixelFiring = MockCreateImagePixelFiring()
        selectedModel = (nil, nil)
        allowsSubscriptionUpsell = true
        isTrialEligible = false
        animationCount = 0
        reportedBlocks = []
        viewModel = makeViewModel()
        privacyKind = nil
        privacyEnabled = true
        privacyEvents = []
        privacyEventKinds = []
        privacyDisplayStore = PrivacyDisplayStore()
        let privacySource = UTIFooterAttachmentPrivacyNoticeSource(
            attachmentKind: { [unowned self] in privacyKind },
            isEnabled: { [unowned self] in privacyEnabled },
            displayStore: privacyDisplayStore)
        sut = UTIFooterController(viewModel: viewModel,
                                  highUsageNotice: makeNoticeSource(),
                                  attachmentPrivacyNotice: privacySource,
                                  measurement: DuckAiUsageWarningMeasurement(pixelFiring: measurementFiring),
                                  highUsageMeasurement: DuckAiUsageWarningMeasurement(pixelFiring: measurementFiring),
                                  createImagePixelFiring: createImagePixelFiring,
                                  allowsSubscriptionUpsell: { [unowned self] in allowsSubscriptionUpsell },
                                  animator: { [unowned self] changes in
                                      animationCount += 1
                                      changes()
                                  })
        sut.onAttachmentPrivacyEvent = { [unowned self] action, kind in
            privacyEvents.append(action)
            privacyEventKinds.append(kind)
        }
        sut.presenter = presenter
        sut.onInputBlockChanged = { [unowned self] blocked in reportedBlocks.append(blocked) }
    }

    override func tearDown() {
#if DEBUG || ALPHA
        UTIFooterDebugOverrides.clearTermsPreview()
#endif
        sut = nil
        viewModel = nil
        presenter = nil
        measurementFiring = nil
        createImagePixelFiring = nil
        dismissalStore = nil
        limitsProvider = nil
        super.tearDown()
    }

    func testPriorityResolverOrdersRequiredActionAndInformational() {
        let message = UTIFooterMessageMapper().attachmentPrivacyMessage()
        let ids: [UTIFooterItem.ID] = [.highUsage, .usageWarning, .modelSwitch, .attachmentPrivacy]
        let all = ids.map { UTIFooterItem(id: $0, message: message) }
        XCTAssertEqual(UTIFooterItem.visible(from: all, isEditing: false).map(\.id), [.attachmentPrivacy])
        let ordinary = all.filter { $0.type != .required }
        XCTAssertEqual(UTIFooterItem.visible(from: ordinary, isEditing: false).map(\.id), [.modelSwitch])
        XCTAssertTrue(UTIFooterItem.visible(from: all, isEditing: true).isEmpty)
    }

    func testHiddenHighUsageCannotBeDismissedOrReportAnImpression() {
        limitsProvider.limits = weeklyUsage(75)
        selectedModel = (id: "claude-opus-4-8", shortName: "Opus 4.8")
        sut.refresh()
        sut.footerVisibilityChanged(isVisible: true)
        sut.dismiss(.highUsage)
        XCTAssertEqual(sut.currentMessages.map(\.id), [.usageWarning])
        XCTAssertEqual(measurementFiring.events, [.shown(approachingExposure(percentBucket: 75))])

        limitsProvider.limits = .noData
        sut.refresh()
        sut.footerVisibilityChanged(isVisible: true)
        XCTAssertEqual(sut.currentMessages.map(\.id), [.highUsage])
        XCTAssertEqual(measurementFiring.events.last, .shown(DuckAiUsageWarningExposure(kind: .highUsageModelNotice,
                                                                                     modelId: "claude-opus-4-8")))
    }


    func testDismissalDoesNotFillVacancyUntilNewOccurrenceEvenWithIdenticalCopy() {
        limitsProvider.limits = weeklyUsage(75)
        sut.refresh()
        let notice = modelSwitchNotice()
        sut.showModelSwitchNotice(notice)
        sut.footerVisibilityChanged(isVisible: true)
        sut.dismiss(.modelSwitch)
        sut.refresh()
        sut.footerVisibilityChanged(isVisible: true)
        XCTAssertTrue(sut.currentMessages.isEmpty)
        XCTAssertTrue(measurementFiring.events.isEmpty)

        sut.showModelSwitchNotice(notice)
        XCTAssertEqual(sut.currentMessages.map(\.id), [.modelSwitch])
        sut.footerVisibilityChanged(isVisible: true)
        sut.dismiss(.modelSwitch)
        sut.refresh()
        XCTAssertTrue(sut.currentMessages.isEmpty)
    }

    func testAttachmentRemovalImmediatelyFillsVacancyWithoutDismissal() {
        limitsProvider.limits = weeklyUsage(75)
        privacyKind = .image
        sut.refresh()
        sut.showModelSwitchNotice(modelSwitchNotice())

        privacyKind = nil
        sut.refresh()

        XCTAssertEqual(sut.currentMessages.map(\.id), [.modelSwitch])
        XCTAssertEqual(privacyDisplayStore.displayCount, 0)
    }

    func testEndingVisibleMessageImmediatelyFillsItsSlot() {
        limitsProvider.limits = weeklyUsage(75)
        selectedModel = (id: "claude-opus-4-8", shortName: "Opus 4.8")
        sut.refresh()
        sut.showModelSwitchNotice(modelSwitchNotice())
        sut.clearModelSwitchNotice()
        XCTAssertEqual(sut.currentMessages.map(\.id), [.usageWarning])
    }

    func testAttachmentChangeAtDisplayCapDoesNotReleaseVacancy() {
        privacyDisplayStore.displayCount = 3
        limitsProvider.limits = weeklyUsage(75)
        sut.refresh()
        sut.showModelSwitchNotice(modelSwitchNotice())
        sut.footerVisibilityChanged(isVisible: true)
        sut.dismiss(.modelSwitch)
        privacyKind = .file
        sut.refresh()
        XCTAssertTrue(sut.currentMessages.isEmpty)
        XCTAssertEqual(privacyDisplayStore.displayCount, 3)
    }

    func testCountdownChangesDoNotReleaseDismissalVacancy() {
        limitsProvider.limits = weeklyUsage(75)
        sut.refresh()
        sut.showModelSwitchNotice(modelSwitchNotice())
        sut.footerVisibilityChanged(isVisible: true)
        sut.dismiss(.modelSwitch)
        let previousReset = viewModel.warning?.resetsIn

        now = now.addingTimeInterval(86_400)
        sut.refresh()

        XCTAssertNotEqual(viewModel.warning?.resetsIn, previousReset)
        XCTAssertTrue(sut.currentMessages.isEmpty)
    }

    func testPercentageChangesDoNotReleaseVacancyButNewRequiredMessageDoes() {
        limitsProvider.limits = weeklyUsage(75)
        sut.refresh()
        sut.showModelSwitchNotice(modelSwitchNotice())
        sut.footerVisibilityChanged(isVisible: true)
        sut.dismiss(.modelSwitch)
        limitsProvider.limits = weeklyUsage(90)
        sut.refresh()
        XCTAssertTrue(sut.currentMessages.isEmpty)

        limitsProvider.limits = weeklyReached()
        sut.refresh()
        XCTAssertEqual(sut.currentMessages.map(\.id), [.outOfUsage])
    }

    func testCTADoesNotRevealWaitingHighUsageEvenDuringReentrantRefresh() {
        limitsProvider.limits = weeklyUsage(75)
        selectedModel = (id: "claude-opus-4-8", shortName: "Opus 4.8")
        sut.refresh()
        sut.footerVisibilityChanged(isVisible: true)
        viewModel.onAction = { [unowned self] _ in
            limitsProvider.limits = .noData
            sut.refresh()
            XCTAssertTrue(sut.currentMessages.isEmpty)
        }
        sut.performPrimaryAction(.usageWarning)
        sut.refresh()
        XCTAssertTrue(sut.currentMessages.isEmpty)

        selectedModel = (nil, nil)
        sut.refresh()
        selectedModel = (id: "claude-opus-4-8", shortName: "Opus 4.8")
        sut.refresh()
        XCTAssertEqual(sut.currentMessages.map(\.id), [.highUsage])
    }

    func testExitingEditReevaluatesMessagesWaitingAfterDismissal() {
        limitsProvider.limits = weeklyUsage(75)
        sut.refresh()
        sut.showModelSwitchNotice(modelSwitchNotice())
        sut.footerVisibilityChanged(isVisible: true)
        sut.dismiss(.modelSwitch)

        sut.setEditing(true)
        sut.clearModelSwitchNotice()
        sut.setEditing(false)

        XCTAssertEqual(sut.currentMessages.map(\.id), [.usageWarning])
    }

    func testBlockingLimitOutranksCreateImageAndResolvingItRefillsImmediately() {
        limitsProvider.limits = dailyReachedWithWeeklyHandOff()
        sut.refresh()
        sut.showModelSwitchNotice(modelSwitchNotice())
        sut.footerVisibilityChanged(isVisible: true)
        XCTAssertEqual(sut.currentMessages.map(\.id), [.outOfUsage])
        XCTAssertFalse(sut.currentMessage?.isDismissible ?? true)
        viewModel.onAction = { [unowned self] _ in
            limitsProvider.limits = .noData
            sut.refresh()
        }

        sut.performPrimaryAction(.outOfUsage)

        XCTAssertEqual(sut.currentMessages.map(\.id), [.modelSwitch])
        XCTAssertEqual(reportedBlocks.last, false)
    }

    func testOpeningSubscriptionDoesNotDismissBlockingLimit() {
        limitsProvider.limits = weeklyReachedWithUpsell()
        sut.refresh()
        sut.showModelSwitchNotice(modelSwitchNotice())
        sut.footerVisibilityChanged(isVisible: true)
        sut.performPrimaryAction(.outOfUsage)
        XCTAssertEqual(sut.currentMessages.map(\.id), [.outOfUsage])
        XCTAssertTrue(viewModel.warning?.blocksInput == true)
    }

    func testHiddenActionEndingDoesNotReleaseDismissalVacancy() {
        limitsProvider.limits = weeklyUsage(75)
        sut.refresh()
        sut.showModelSwitchNotice(modelSwitchNotice())
        sut.footerVisibilityChanged(isVisible: true)
        sut.dismiss(.modelSwitch)
        sut.clearModelSwitchNotice()
        sut.recordPromptSubmitted()
        sut.refresh()
        XCTAssertTrue(sut.currentMessages.isEmpty)
    }

    func testNewlyApplicableMessageReleasesVacancyEvenWhenDiscoveredByRefresh() {
        limitsProvider.limits = weeklyUsage(75)
        sut.refresh()
        sut.showModelSwitchNotice(modelSwitchNotice())
        sut.footerVisibilityChanged(isVisible: true)
        sut.dismiss(.modelSwitch)
        XCTAssertTrue(sut.currentMessages.isEmpty)

        privacyKind = .file
        sut.refresh()

        XCTAssertEqual(sut.currentMessages.map(\.id), [.attachmentPrivacy])
    }

    func testPrivacyWorksWithoutUsageWarningsModel() {
        let source = UTIFooterAttachmentPrivacyNoticeSource(attachmentKind: { .image },
                                                           isEnabled: { true },
                                                           displayStore: privacyDisplayStore)
        let controller = UTIFooterController(viewModel: nil,
                                             attachmentPrivacyNotice: source,
                                             createImagePixelFiring: createImagePixelFiring,
                                             animator: { $0() })
        controller.presenter = presenter
        controller.refresh()

        XCTAssertEqual(controller.currentMessage, UTIFooterMessageMapper().attachmentPrivacyMessage())
        controller.footerVisibilityChanged(isVisible: true)
        controller.dismissCurrent()
        XCTAssertEqual(controller.currentMessages.map(\.id), [.attachmentPrivacy])
        XCTAssertEqual(privacyDisplayStore.displayCount, 1)
    }

    func testPrivacyOutranksUsageWarningAndRemovalRestoresWarning() {
        limitsProvider.limits = weeklyUsage(75)
        privacyKind = .image
        sut.refresh()
        XCTAssertEqual(sut.currentMessage, UTIFooterMessageMapper().attachmentPrivacyMessage())

        privacyKind = nil
        sut.refresh()
        XCTAssertTrue(sut.currentMessage?.title.contains("75%") == true)
        XCTAssertEqual(privacyDisplayStore.displayCount, 0)
    }

    func testPrivacyCannotBeDismissedAndDoesNotSpendUsageWarningDismissal() {
        limitsProvider.limits = weeklyUsage(75)
        privacyKind = .file
        sut.refresh()
        sut.footerVisibilityChanged(isVisible: true)
        sut.dismiss(.attachmentPrivacy)
        sut.refresh()
        XCTAssertEqual(sut.currentMessages.map(\.id), [.attachmentPrivacy])
        XCTAssertNil(dismissalStore.dismissal(for: .weekly))
        XCTAssertEqual(privacyDisplayStore.displayCount, 1)
        XCTAssertEqual(privacyEvents, [.shown])
        XCTAssertTrue(measurementFiring.events.isEmpty)
        privacyKind = nil
        sut.refresh()
        XCTAssertEqual(sut.currentMessages.map(\.id), [.usageWarning])
    }

    func testPrivacyShownOncePerAppearanceAndNotPerAttachmentChange() {
        privacyKind = .image
        sut.refresh()
        sut.footerVisibilityChanged(isVisible: true)
        sut.footerVisibilityChanged(isVisible: true)
        privacyKind = .file
        sut.refresh()
        sut.footerVisibilityChanged(isVisible: true)
        sut.recordLinkTapped()
        XCTAssertEqual(privacyEvents, [.shown, .learnMoreTapped])
        XCTAssertEqual(privacyEventKinds, [.image, .image])

        sut.footerVisibilityChanged(isVisible: false)
        sut.footerVisibilityChanged(isVisible: true)
        XCTAssertEqual(privacyEvents, [.shown, .learnMoreTapped, .shown])
        XCTAssertEqual(privacyEventKinds, [.image, .image, .file])
    }

    func testPrivacyFlagOffDoesNotResolveOrReport() {
        privacyKind = .image
        privacyEnabled = false
        sut.refresh()
        sut.footerVisibilityChanged(isVisible: true)
        sut.recordLinkTapped()
        XCTAssertNil(sut.currentMessage)
        XCTAssertTrue(privacyEvents.isEmpty)
    }

    func testPrivacyWaitsForVisibilityBeforeReporting() {
        privacyKind = .image
        sut.refresh()
        XCTAssertTrue(privacyEvents.isEmpty)
        sut.footerVisibilityChanged(isVisible: true)
        XCTAssertEqual(privacyEvents, [.shown])
    }

    func testPrivacyHidesModelSwitchWithoutDismissingItOrRepeatingImpression() {
        privacyKind = .image
        sut.refresh()
        sut.footerVisibilityChanged(isVisible: true)
        sut.showModelSwitchNotice(modelSwitchNotice())
        sut.footerVisibilityChanged(isVisible: true)
        XCTAssertEqual(sut.currentMessages.map(\.id), [.attachmentPrivacy])
        sut.dismiss(.modelSwitch)
        XCTAssertTrue(createImagePixelFiring.isEmpty)
        privacyKind = nil
        sut.refresh()
        XCTAssertEqual(sut.currentMessages.map(\.id), [.modelSwitch])
        XCTAssertEqual(privacyEvents, [.shown])
        XCTAssertEqual(privacyDisplayStore.displayCount, 1)
    }

    func testSwitchingToSuggestedModelRetiresHiddenWarningWithoutDismissal() {
        limitsProvider.limits = weeklyUsage(75)
        privacyKind = .image
        selectedModel = (id: "claude-opus-4-8", shortName: "Opus 4.8")
        sut.refresh()
        sut.footerVisibilityChanged(isVisible: true)

        sut.userSwitchedModel(from: "gpt-5.4", to: "gpt-5.4-mini")
        privacyKind = nil
        sut.refresh()

        XCTAssertEqual(sut.currentMessages.map(\.id), [.highUsage])
        XCTAssertNotNil(dismissalStore.actedSnapshot())
        XCTAssertNil(dismissalStore.dismissal(for: .weekly))
        XCTAssertTrue(measurementFiring.events.isEmpty)
    }

    func testHiddenMessagesCannotBeDismissedOrActedOn() {
        limitsProvider.limits = weeklyUsage(75)
        privacyKind = .image
        selectedModel = (id: "claude-opus-4-8", shortName: "Opus 4.8")
        sut.refresh()
        sut.showModelSwitchNotice(modelSwitchNotice())
        sut.footerVisibilityChanged(isVisible: true)
        var actions: [DuckAiUsageAction] = []
        viewModel.onAction = { actions.append($0) }

        sut.dismiss(.usageWarning)
        sut.dismiss(.highUsage)
        sut.performPrimaryAction(.usageWarning)
        XCTAssertTrue(actions.isEmpty)
        XCTAssertTrue(measurementFiring.events.isEmpty)

        sut.recordPromptSubmitted()
        privacyKind = nil
        sut.refresh()
        XCTAssertEqual(sut.currentMessages.map(\.id), [.usageWarning])
    }

    func testEditPromptHidesRequiredAndOrdinaryMessagesAndReevaluatesOnExit() {
        limitsProvider.limits = weeklyReached()
        privacyKind = .image
        sut.refresh()
        sut.showModelSwitchNotice(modelSwitchNotice())
        XCTAssertEqual(sut.currentMessages.map(\.id), [.outOfUsage])
        sut.setEditing(true)
        XCTAssertTrue(sut.currentMessages.isEmpty)
        privacyKind = nil
        sut.clearModelSwitchNotice()
        sut.refresh()
        sut.setEditing(false)
        XCTAssertEqual(sut.currentMessages.map(\.id), [.outOfUsage])
        XCTAssertEqual(privacyDisplayStore.displayCount, 0)
    }

    func testBlockedSubmissionPreventsDisclosureWithoutCountingIt() {
        limitsProvider.limits = weeklyReached()
        privacyKind = .image
        sut.refresh()
        sut.footerVisibilityChanged(isVisible: true)
        sut.dismiss(.attachmentPrivacy)
        sut.dismiss(.outOfUsage)
        sut.refresh()
        XCTAssertEqual(sut.currentMessages.map(\.id), [.outOfUsage])
        XCTAssertEqual(privacyDisplayStore.displayCount, 0)
        XCTAssertTrue(privacyEvents.isEmpty)
        XCTAssertTrue(viewModel.warning?.blocksInput == true)
        limitsProvider.limits = .noData
        sut.refresh()
        XCTAssertEqual(sut.currentMessages.map(\.id), [.attachmentPrivacy])
        sut.footerVisibilityChanged(isVisible: true)
        XCTAssertEqual(privacyDisplayStore.displayCount, 1)
    }

    func testUnseenResolvedMessageCannotBeDismissed() {
        privacyKind = .image
        sut.refresh()
        sut.dismiss(.attachmentPrivacy)
        XCTAssertEqual(privacyDisplayStore.displayCount, 0)
        XCTAssertEqual(sut.currentMessages.map(\.id), [.attachmentPrivacy])
    }

    func testPrivacySuppressionAndPoseChangeDoNotCountUnseenCards() {
        privacyKind = .image
        sut.refresh()
        sut.setSuppressed(true)
        XCTAssertNil(sut.currentMessage)
        sut.setSuppressed(false)
        XCTAssertEqual(sut.currentMessage, UTIFooterMessageMapper().attachmentPrivacyMessage())
        sut.resetForPoseChange()
        sut.refresh()
        XCTAssertEqual(sut.currentMessage, UTIFooterMessageMapper().attachmentPrivacyMessage())
        XCTAssertEqual(privacyDisplayStore.displayCount, 0)
    }

    func testPrivacySubmissionAndAttachmentRemovalClearDisplayWithoutIncrementing() {
        privacyKind = .image
        sut.refresh()
        sut.recordPromptSubmitted()
        XCTAssertEqual(privacyDisplayStore.displayCount, 0)
        privacyKind = nil
        sut.refresh()
        XCTAssertNil(sut.currentMessage)
        privacyKind = .file
        sut.refresh()
        XCTAssertEqual(sut.currentMessage, UTIFooterMessageMapper().attachmentPrivacyMessage())
    }

    func testThirdAppearanceSurvivesRefreshAndLinkThenStopsAfterRemoval() {
        privacyDisplayStore.displayCount = 2
        privacyKind = .image
        sut.refresh()
        sut.footerVisibilityChanged(isVisible: true)
        XCTAssertEqual(privacyDisplayStore.displayCount, 3)
        sut.refresh()
        sut.footerVisibilityChanged(isVisible: true)
        sut.recordLinkTapped()
        XCTAssertEqual(sut.currentMessages.map(\.id), [.attachmentPrivacy])
        XCTAssertEqual(privacyEvents, [.shown, .learnMoreTapped])
        privacyKind = nil
        sut.refresh()
        privacyKind = .file
        sut.refresh()
        XCTAssertTrue(sut.currentMessages.isEmpty)
        XCTAssertEqual(privacyDisplayStore.displayCount, 3)
    }

    func testThirdAppearanceDoesNotReturnAfterVisibilityEnds() {
        privacyDisplayStore.displayCount = 2
        privacyKind = .image
        sut.refresh()
        sut.footerVisibilityChanged(isVisible: true)
        sut.footerVisibilityChanged(isVisible: false)
        sut.refresh()
        XCTAssertTrue(sut.currentMessages.isEmpty)
        XCTAssertEqual(privacyEvents, [.shown])
    }

#if DEBUG || ALPHA
    func testTermsPreviewStacksFirstAndClearsOnSubmit() {
        UTIFooterDebugOverrides.showTermsPreview()
        privacyKind = .image
        sut.refresh()
        XCTAssertEqual(sut.currentMessages.map(\.id), [.termsConsent, .attachmentPrivacy])
        XCTAssertTrue(sut.currentMessages.allSatisfy { !$0.message.isDismissible })
        sut.footerVisibilityChanged(isVisible: true)
        sut.dismiss(.termsConsent)
        sut.dismiss(.attachmentPrivacy)
        XCTAssertEqual(sut.currentMessages.count, 2)
        XCTAssertEqual(privacyDisplayStore.displayCount, 1)
        privacyKind = nil
        sut.recordPromptSubmitted()
        XCTAssertTrue(sut.currentMessages.isEmpty)
        XCTAssertNil(UTIFooterDebugOverrides.termsMessage)
    }

    func testTermsPreviewAloneAtPrivacyCapAndHiddenWhileEditing() {
        privacyDisplayStore.displayCount = 3
        privacyKind = .image
        UTIFooterDebugOverrides.showTermsPreview()
        sut.refresh()
        XCTAssertEqual(sut.currentMessages.map(\.id), [.termsConsent])
        sut.setEditing(true)
        XCTAssertTrue(sut.currentMessages.isEmpty)
        UTIFooterDebugOverrides.clearTermsPreview()
        sut.setEditing(false)
        XCTAssertTrue(sut.currentMessages.isEmpty)
    }
#endif

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

    // MARK: - Input block

    /// The allowance is spent, so the card is the only thing left to act on.
    func test_refresh_reportsTheInputBlockedWhenTheLimitIsReached() {
        limitsProvider.limits = weeklyReachedWithUpsell()

        sut.refresh()

        XCTAssertEqual(reportedBlocks, [true])
    }

    func test_refresh_leavesTheInputLiveWhileTheWarningIsOnlyApproaching() {
        limitsProvider.limits = weeklyUsage(90)

        sut.refresh()

        XCTAssertTrue(reportedBlocks.isEmpty)
    }

    /// A block with no card on screen to explain it would read as the input having broken.
    func test_setSuppressed_liftsTheBlockWithTheCard() {
        limitsProvider.limits = weeklyReachedWithUpsell()
        sut.refresh()

        sut.setSuppressed(true)

        XCTAssertEqual(reportedBlocks, [true, false])
    }

    func test_resetForPoseChange_liftsTheBlock() {
        limitsProvider.limits = weeklyReachedWithUpsell()
        sut.refresh()

        sut.resetForPoseChange()

        XCTAssertEqual(reportedBlocks, [true, false])
    }

    /// The CTA exists to unblock the user, and since #6644 it pushes the hand-off to the live chat
    /// instead of writing an entry — so no snapshot update comes back to lift the block for it.
    func test_performPrimaryAction_liftsTheBlockWhenTheHandOffIsTaken() {
        limitsProvider.limits = dailyReachedWithWeeklyHandOff()
        sut.refresh()
        XCTAssertEqual(reportedBlocks, [true])

        sut.footerVisibilityChanged(isVisible: true)
        sut.performPrimaryAction()

        XCTAssertEqual(reportedBlocks, [true, false])
    }

    // MARK: - Dismissal

    func test_dismissCurrent_hidesTheFooter() {
        limitsProvider.limits = weeklyUsage(50)
        sut.refresh()

        sut.footerVisibilityChanged(isVisible: true)
        sut.dismissCurrent()

        XCTAssertEqual(presenter.appliedMessages.last, .some(nil))
    }

    func test_dismissCurrent_keepsTheSameWarningHiddenOnTheNextRefresh() {
        limitsProvider.limits = weeklyUsage(50)
        sut.refresh()
        sut.footerVisibilityChanged(isVisible: true)
        sut.dismissCurrent()

        sut.refresh()

        XCTAssertEqual(presenter.appliedMessages.last, .some(nil))
    }

    /// The dismissal is recorded against a rung of the redisplay ladder, so crossing the next one
    /// brings the card back.
    func test_dismissCurrent_doesNotHideTheNextThreshold() {
        limitsProvider.limits = weeklyUsage(50)
        sut.refresh()
        sut.footerVisibilityChanged(isVisible: true)
        sut.dismissCurrent()

        limitsProvider.limits = weeklyUsage(90)
        sut.refresh()

        XCTAssertTrue(presenter.appliedMessages.last??.title.contains("90%") ?? false)
    }

    /// A dismissed approaching message must not take the reached one with it.
    func test_dismissCurrent_doesNotHideADifferentNotice() {
        limitsProvider.limits = weeklyUsage(50)
        sut.refresh()
        sut.footerVisibilityChanged(isVisible: true)
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

        sut.footerVisibilityChanged(isVisible: true)
        sut.userSwitchedModel(from: "gpt-5.4", to: "gpt-5.4-mini")

        XCTAssertEqual(presenter.appliedMessages.last, .some(nil))
    }

    func test_userSwitchedModel_keepsTheMessageHiddenUntilWebPublishesAgain() {
        limitsProvider.limits = weeklyUsage(75)
        sut.refresh()
        sut.footerVisibilityChanged(isVisible: true)
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

        sut.footerVisibilityChanged(isVisible: true)
        sut.performPrimaryAction()

        XCTAssertEqual(received, [.switchToModel(DuckAiModelSuggestion(modelId: "gpt-5.4-mini", modelShortName: "5.4 mini"))])
    }

    /// Acting on the message retires it, exactly as the close button would.
    func test_performPrimaryAction_hidesTheMessageWhenItSwitchesModel() {
        limitsProvider.limits = weeklyUsage(50)
        sut.refresh()

        sut.footerVisibilityChanged(isVisible: true)
        sut.performPrimaryAction()

        XCTAssertEqual(presenter.appliedMessages.last, .some(nil))
    }

    func test_performPrimaryAction_keepsTheMessageHiddenOnTheNextRefresh() {
        limitsProvider.limits = weeklyUsage(50)
        sut.refresh()
        sut.footerVisibilityChanged(isVisible: true)
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
        sut.footerVisibilityChanged(isVisible: true)
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
        sut.footerVisibilityChanged(isVisible: true)
        sut.performPrimaryAction()

        limitsProvider.limits = weeklyUsage(50, signature: "snapshot-50-republished")
        sut.refresh()

        XCTAssertEqual(presenter.appliedMessages.last, .some(nil))
    }

    /// The debug menu clears the persisted record; the controller's own copy must not outlive it.
    func test_performPrimaryAction_showsTheMessageAgainOnceTheActedRecordIsCleared() {
        limitsProvider.limits = weeklyUsage(50)
        sut.refresh()
        sut.footerVisibilityChanged(isVisible: true)
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

        sut.footerVisibilityChanged(isVisible: true)
        sut.performPrimaryAction()

        XCTAssertEqual(presenter.appliedMessages.last??.primaryAction?.title, "Subscribe")
    }

    func test_performPrimaryAction_doesNothingWithoutAMessage() {
        var received: [DuckAiUsageAction] = []
        viewModel.onAction = { received.append($0) }

        sut.footerVisibilityChanged(isVisible: true)
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

    func test_showModelSwitchNotice_replacesUsageWarning() {
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

        sut.footerVisibilityChanged(isVisible: true)
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

        sut.footerVisibilityChanged(isVisible: true)
        sut.dismissCurrent()

        XCTAssertNil(sut.currentMessage)
        limitsProvider.limits = .noData
        sut.refresh()
        limitsProvider.limits = weeklyUsage(50)
        sut.refresh()
        XCTAssertTrue(sut.currentMessage?.title.contains("50%") == true)
    }

    func test_dismissCurrent_whileTheNoticeIsVisible_dropsTheNoticeForGood() {
        sut.showModelSwitchNotice(modelSwitchNotice())
        sut.footerVisibilityChanged(isVisible: true)
        sut.dismissCurrent()

        sut.refresh()

        XCTAssertEqual(presenter.appliedMessages.last, .some(nil))
    }

    /// The two dismissals are separate records: closing the warning must not also spend the notice's.
    func test_dismissCurrent_dismissesTheWarningWithoutSpendingTheNoticesDismissal() {
        selectedModel = (id: "claude-opus-4-8", shortName: "Opus 4.8")
        limitsProvider.limits = weeklyUsage(50)
        sut.refresh()

        sut.footerVisibilityChanged(isVisible: true)
        sut.dismissCurrent()
        sut.refresh()

        XCTAssertNil(sut.currentMessage)
        selectedModel = (nil, nil)
        sut.refresh()
        selectedModel = (id: "claude-opus-4-8", shortName: "Opus 4.8")
        sut.refresh()
        XCTAssertTrue(sut.currentMessage?.title.contains("Opus 4.8") == true)
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

        sut.footerVisibilityChanged(isVisible: true)
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
    func test_footerVisibilityChanged_doesNotReportHiddenUsageImpression() {
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

        sut.footerVisibilityChanged(isVisible: true)
        sut.dismissCurrent()

        XCTAssertEqual(measurementFiring.events, [.shown(approachingExposure(percentBucket: 75))])
    }

    // MARK: - Create Image pixels

    func test_createImagePixels_whenTheUserClosesTheNotice_reportsTheDismissal() {
        sut.showModelSwitchNotice(modelSwitchNotice())

        sut.footerVisibilityChanged(isVisible: true)
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

        sut.footerVisibilityChanged(isVisible: true)
        sut.dismissCurrent()

        XCTAssertTrue(createImagePixelFiring.isEmpty)
    }

    func test_createImagePixels_whenTheNoticeAndThenTheWarningAreClosed_reportsOneDismissal() {
        limitsProvider.limits = weeklyUsage(50)
        sut.refresh()
        sut.showModelSwitchNotice(modelSwitchNotice())

        sut.footerVisibilityChanged(isVisible: true)
        sut.dismissCurrent()
        limitsProvider.limits = .noData
        sut.refresh()
        limitsProvider.limits = weeklyUsage(50)
        sut.refresh()
        sut.footerVisibilityChanged(isVisible: true)
        sut.dismissCurrent()

        XCTAssertEqual(createImagePixelFiring.noticeDismissedCount, 1)
    }

    func test_createImagePixels_whenThePrimaryActionRunsWhileTheNoticeIsVisible_reportsNothing() {
        sut.showModelSwitchNotice(modelSwitchNotice())

        sut.footerVisibilityChanged(isVisible: true)
        sut.performPrimaryAction()

        XCTAssertTrue(createImagePixelFiring.isEmpty)
    }

    func testUnavailablePurchaseRetainsBothTrialVariantsAndInputBlocking() {
        allowsSubscriptionUpsell = false
        limitsProvider.limits = weeklyReachedWithUpsell()
        for trialEligible in [true, false] {
            isTrialEligible = trialEligible
            sut.refresh()

            XCTAssertNotNil(sut.currentMessage)
            XCTAssertNil(sut.currentMessage?.primaryAction)
            XCTAssertEqual(sut.currentMessage?.title, UserText.utiDuckAIWarningsWeeklyLimitReached)
            XCTAssertNotNil(sut.currentMessage?.subtitle)
            XCTAssertNil(presenter.appliedMessages.last??.primaryAction)
            XCTAssertEqual(reportedBlocks, [true])
        }
    }

    func testPurchaseAvailabilityRefreshRemovesAndRestoresActionWithoutRetiringCard() throws {
        limitsProvider.limits = weeklyReachedWithUpsell()
        for trialEligible in [true, false] {
            isTrialEligible = trialEligible
            allowsSubscriptionUpsell = true
            sut.refresh()
            let original = try XCTUnwrap(sut.currentMessage)
            XCTAssertEqual(original.primaryAction?.title,
                           trialEligible ? UserText.utiDuckAIWarningsTryForFree : UserText.utiDuckAIWarningsSubscribe)

            allowsSubscriptionUpsell = false
            sut.refresh()
            XCTAssertNil(presenter.appliedMessages.last??.primaryAction)
            XCTAssertEqual(sut.currentMessage?.title, original.title)
            XCTAssertEqual(sut.currentMessage?.subtitle, original.subtitle)

            allowsSubscriptionUpsell = true
            sut.refresh()
            XCTAssertEqual(sut.currentMessage, original)
            XCTAssertEqual(presenter.appliedMessages.last ?? nil, original)
            XCTAssertEqual(reportedBlocks, [true])
        }
    }

    func testUnavailablePurchaseCannotExecuteOrMeasureHiddenOrStaleAction() {
        limitsProvider.limits = weeklyReachedWithUpsell()
        var actions: [DuckAiUsageAction] = []
        viewModel.onAction = { actions.append($0) }
        sut.refresh()
        sut.footerVisibilityChanged(isVisible: true)
        let eventsBeforeTap = measurementFiring.events

        allowsSubscriptionUpsell = false
        sut.performPrimaryAction()
        sut.refresh()
        sut.performPrimaryAction()

        XCTAssertTrue(actions.isEmpty)
        XCTAssertEqual(measurementFiring.events, eventsBeforeTap)
        XCTAssertNil(sut.currentMessage?.primaryAction)
        XCTAssertEqual(reportedBlocks, [true])
    }

    func testUnavailablePurchasePreservesOtherFooterActions() {
        allowsSubscriptionUpsell = false
        var actions: [DuckAiUsageAction] = []
        viewModel.onAction = { actions.append($0) }
        limitsProvider.limits = weeklyUsage(75)
        sut.refresh()
        sut.footerVisibilityChanged(isVisible: true)
        XCTAssertNotNil(sut.currentMessage?.primaryAction)
        sut.performPrimaryAction()
        XCTAssertEqual(actions.count, 1)

        limitsProvider.limits = dailyReachedWithWeeklyHandOff()
        sut.refresh()
        sut.footerVisibilityChanged(isVisible: true)
        XCTAssertEqual(sut.currentMessage?.primaryAction?.title, UserText.utiDuckAIWarningsStartUsingWeeklyLimit)
        sut.performPrimaryAction()
        XCTAssertEqual(actions.count, 2)
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
            isTrialEligible: { [unowned self] in isTrialEligible },
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

    /// The blocked state the screenshot shows: a spent daily allowance whose only offer is the
    /// weekly hand-off.
    private func dailyReachedWithWeeklyHandOff() -> DuckAiUsageSnapshot {
        DuckAiUsageSnapshot(
            notice: DuckAiUsageNotice(id: .dailyReached,
                                      window: .daily,
                                      percentUsed: 100,
                                      resetsAt: now.addingTimeInterval(18_000),
                                      reached: true,
                                      dismissible: false),
            cta: DuckAiUsageCta(id: .bypassWeekly,
                                putEntries: [DuckAiNativeStorageEntry(key: "usageLimits", value: "{}")]),
            signature: "snapshot-daily-reached"
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

    private(set) var appliedStacks: [[UTIFooterItem]] = []

    func applyFooterMessages(_ messages: [UTIFooterItem]) {
        appliedStacks.append(messages)
        appliedMessages.append(messages.first?.message)
    }

    func clearPendingFooterMessage() {
        pendingClearCount += 1
    }
}

private final class PrivacyDisplayStore: UTIAttachmentPrivacyNoticeDisplayStoring {
    var displayCount = 0
    func recordDisplay() { displayCount += 1 }
    func reset() { displayCount = 0 }
}

@MainActor
private extension UTIFooterController {
    func dismissCurrent() {
        guard let id = currentMessages.first?.id else { return }
        dismiss(id)
    }

    func footerVisibilityChanged(isVisible: Bool) {
        footerVisibilityChanged(visible: isVisible ? currentMessages.map(\.id) : [])
    }

    func performPrimaryAction() {
        guard let id = currentMessages.first?.id else { return }
        performPrimaryAction(id)
    }
}
