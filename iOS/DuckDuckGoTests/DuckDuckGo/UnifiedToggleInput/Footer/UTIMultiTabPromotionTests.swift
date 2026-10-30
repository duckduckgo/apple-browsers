//
//  UTIMultiTabPromotionTests.swift
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
import Common
import XCTest
@testable import DuckDuckGo

@MainActor
final class UTIMultiTabPromotionTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var clock: PromotionDateProvider!
    private var settings: MockAIChatSettingsProvider!
    private var flagger: MockFeatureFlagger!
    private var displayStore: UTIMultiTabPromotionDisplayStore!
    private var feature: AIChatContextualAttachMoreTabsFeature!
    private var source: UTIFooterMultiTabPromotionSource!
    private var controller: UTIFooterController!
    private var isNewContextualChat = true
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        suiteName = "UTIMultiTabPromotionTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        clock = PromotionDateProvider(currentDate: start)
        settings = MockAIChatSettingsProvider()
        settings.aiChatAttachMoreTabsPromotionStartDate = start
        flagger = MockFeatureFlagger(enabledFeatureFlags: [.aiChatContextualAttachMoreTabs])
        displayStore = UTIMultiTabPromotionDisplayStore(keyValueStore: defaults, dateProvider: clock)
        feature = makeFeature()
        isNewContextualChat = true
        source = UTIFooterMultiTabPromotionSource(feature: { [unowned self] in feature },
                                                  isEligible: { [unowned self] in isNewContextualChat })
        controller = makeController()
    }

    override func tearDown() {
        controller = nil
        source = nil
        feature = nil
        displayStore = nil
        settings = nil
        flagger = nil
        clock = nil
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func makeFeature() -> AIChatContextualAttachMoreTabsFeature {
        AIChatContextualAttachMoreTabsFeature(
            featureFlagger: flagger, aiChatSettings: settings, devicePlatform: PromotionPhone.self,
            promotionStore: displayStore)
    }

    func testCompactAttachmentLayoutFollowsFlagEvenWhenTabAttachmentsAreUnavailableOnIPad() {
        let padFeature = AIChatContextualAttachMoreTabsFeature(
            featureFlagger: flagger, aiChatSettings: settings, devicePlatform: PromotionPad.self,
            promotionStore: displayStore)

        XCTAssertEqual(padFeature.state, .unavailable)
        XCTAssertTrue(padFeature.usesCompactAttachmentLayout)
        XCTAssertTrue(feature.usesCompactAttachmentLayout)

        flagger.enabledFeatureFlags = []

        XCTAssertEqual(padFeature.state, .unavailable)
        XCTAssertFalse(padFeature.usesCompactAttachmentLayout)
        XCTAssertFalse(feature.usesCompactAttachmentLayout)
    }

    private func makeController(terms: DuckAiTermsOfServiceStore? = nil) -> UTIFooterController {
        UTIFooterController(viewModel: nil, termsOfServiceStore: terms, multiTabPromotion: source,
                            createImagePixelFiring: MockCreateImagePixelFiring(), animator: { $0() })
    }

    private func open() {
        source.beginPresentation()
        controller.refresh()
    }

    private func reportVisible() {
        controller.footerVisibilityChanged(visible: controller.currentMessages.map(\.id))
    }

    func testPeriodStartsInclusivelyAndEndsAfterThirtyDaysExclusively() {
        clock.currentDate = start.addingTimeInterval(-1)
        XCTAssertFalse(feature.isDrawerPromoAvailable(isCurrentDisplay: false))
        clock.currentDate = start
        XCTAssertTrue(feature.isDrawerPromoAvailable(isCurrentDisplay: false))
        clock.currentDate = start.addingTimeInterval(30 * 24 * 60 * 60 - 1)
        XCTAssertTrue(feature.isDrawerPromoAvailable(isCurrentDisplay: false))
        clock.currentDate = clock.currentDate.addingTimeInterval(1)
        XCTAssertFalse(feature.isDrawerPromoAvailable(isCurrentDisplay: true))
    }

    func testMissingDateAndDisabledFeatureSuppressEvenCurrentDisplay() {
        settings.aiChatAttachMoreTabsPromotionStartDate = nil
        XCTAssertFalse(feature.isDrawerPromoAvailable(isCurrentDisplay: true))
        settings.aiChatAttachMoreTabsPromotionStartDate = start
        flagger.enabledFeatureFlags = []
        XCTAssertFalse(feature.isDrawerPromoAvailable(isCurrentDisplay: true))
    }

    func testCurrentConfigurationDateIsReadWithoutRecreatingFeature() {
        open()
        reportVisible()
        settings.aiChatAttachMoreTabsPromotionStartDate = start.addingTimeInterval(14 * 24 * 60 * 60)
        controller.refresh()
        XCTAssertTrue(controller.currentMessages.isEmpty)
        XCTAssertEqual(displayStore.displayCount, 1)
        clock.currentDate = settings.aiChatAttachMoreTabsPromotionStartDate!
        controller.refresh()
        reportVisible()
        XCTAssertEqual(controller.currentMessages.map(\.id), [.multiTabPromotion])
        XCTAssertEqual(displayStore.displayCount, 1)
    }

    func testFirstUseHidesPromotionAndPersistsEvenWithoutConfiguredStartDate() {
        open()
        reportVisible()
        settings.aiChatAttachMoreTabsPromotionStartDate = nil
        feature.recordTabAttachment()
        settings.aiChatAttachMoreTabsPromotionStartDate = start
        controller.refresh()
        XCTAssertTrue(controller.currentMessages.isEmpty)
        XCTAssertFalse(makeFeature().isDrawerPromoAvailable(isCurrentDisplay: false))
        let otherStore = UTIMultiTabPromotionDisplayStore(keyValueStore: defaults, dateProvider: clock)
        XCTAssertTrue(otherStore.hasAttachedTab)
        XCTAssertFalse(otherStore.isAvailable(startDate: start, isCurrentDisplay: true))
        XCTAssertEqual(otherStore.displayCount, 1)
    }

    func testOnlyActualVisibilityCountsAndRepeatedVisibilityCountsOnce() {
        controller.refresh()
        XCTAssertTrue(controller.currentMessages.isEmpty)
        reportVisible()
        XCTAssertEqual(displayStore.displayCount, 0)

        open()
        XCTAssertEqual(controller.currentMessages.map(\.id), [.multiTabPromotion])
        XCTAssertEqual(displayStore.displayCount, 0)
        reportVisible()
        controller.footerVisibilityChanged(visible: [])
        reportVisible()
        XCTAssertEqual(displayStore.displayCount, 1)

        isNewContextualChat = false
        controller.refreshMultiTabPromotion()
        XCTAssertTrue(controller.currentMessages.isEmpty)

        isNewContextualChat = true
        controller.refreshMultiTabPromotion()
        XCTAssertEqual(controller.currentMessages.map(\.id), [.multiTabPromotion])
        reportVisible()
        XCTAssertEqual(displayStore.displayCount, 1)
    }

    func testRequiredMessageSuppressesPromotionWithoutCountingIt() {
        controller = makeController(terms: DuckAiTermsOfServiceStore(keyValueStore: defaults))
        open()
        reportVisible()
        XCTAssertEqual(controller.currentMessages.map(\.id), [.termsConsent])
        XCTAssertEqual(displayStore.displayCount, 0)
        controller.acceptTermsIfDisclaimerShown()
        reportVisible()
        XCTAssertEqual(controller.currentMessages.map(\.id), [.multiTabPromotion])
        XCTAssertEqual(displayStore.displayCount, 1)
    }

    func testPromotionHasLowerPriorityThanEveryExistingMessage() {
        let message = UTIFooterMessageMapper().multiTabPromotionMessage()
        let promotion = UTIFooterItem(id: .multiTabPromotion, message: message)
        for id in UTIFooterItem.ID.allCases where id != .multiTabPromotion {
            let existing = UTIFooterItem(id: id, message: message)
            XCTAssertFalse(UTIFooterItem.visible(from: [promotion, existing], isEditing: false).contains(promotion))
        }
    }

    func testThirdDisplaySurvivesOcclusionPoseChangesAndHandoverButNotNextOpening() {
        displayStore.recordDisplay()
        displayStore.recordDisplay()
        open()
        reportVisible()
        XCTAssertEqual(displayStore.displayCount, 3)
        controller.setEditing(true)
        controller.setEditing(false)
        controller.setSuppressed(true)
        controller.setSuppressed(false)
        controller.resetForPoseChange()
        source.beginPresentation()
        controller.refresh()
        reportVisible()
        XCTAssertEqual(controller.currentMessages.map(\.id), [.multiTabPromotion])
        XCTAssertEqual(displayStore.displayCount, 3)
        source.endPresentation()
        controller.refresh()
        open()
        XCTAssertTrue(controller.currentMessages.isEmpty)
    }

    func testSubmissionSuppressesReopenedConversationButAllowsNewChat() {
        open()
        reportVisible()
        controller.recordPromptSubmitted()
        XCTAssertTrue(controller.currentMessages.isEmpty)
        isNewContextualChat = false
        source.endPresentation()
        controller.refresh()
        open()
        reportVisible()
        XCTAssertTrue(controller.currentMessages.isEmpty)
        XCTAssertEqual(displayStore.displayCount, 1)
        isNewContextualChat = true
        source.startNewChat()
        controller.refreshMultiTabPromotion()
        reportVisible()
        XCTAssertEqual(controller.currentMessages.map(\.id), [.multiTabPromotion])
        XCTAssertEqual(displayStore.displayCount, 2)
    }

    func testDismissalPersistsAcrossInstancesAndDateChanges() {
        open()
        reportVisible()
        controller.dismiss(.multiTabPromotion)
        XCTAssertTrue(controller.currentMessages.isEmpty)
        settings.aiChatAttachMoreTabsPromotionStartDate = start.addingTimeInterval(-1)
        XCTAssertFalse(makeFeature().isDrawerPromoAvailable(isCurrentDisplay: true))
        XCTAssertEqual(displayStore.displayCount, 1)
    }

    func testConsumersShareCountAndPrivacyResetDoesNotResetPromotion() {
        let otherStore = UTIMultiTabPromotionDisplayStore(keyValueStore: defaults, dateProvider: clock)
        displayStore.recordDisplay()
        XCTAssertEqual(otherStore.displayCount, 1)
        let privacyStore = UTIAttachmentPrivacyNoticeDisplayStore(keyValueStore: defaults)
        privacyStore.markShown()
        feature.recordTabAttachment()
        feature.dismissDrawerPromo()
        privacyStore.reset()
        XCTAssertFalse(privacyStore.hasShown)
        XCTAssertEqual(otherStore.displayCount, 1)
        XCTAssertFalse(otherStore.isAvailable(startDate: start, isCurrentDisplay: true))
        XCTAssertTrue(otherStore.hasAttachedTab)
    }

}

private final class PromotionDateProvider: CurrentDateProviding {
    var currentDate: Date
    init(currentDate: Date) { self.currentDate = currentDate }
}

private struct PromotionPhone: DevicePlatformProviding {
    static var isIphone: Bool { true }
}

private struct PromotionPad: DevicePlatformProviding {
    static var isIphone: Bool { false }
}
