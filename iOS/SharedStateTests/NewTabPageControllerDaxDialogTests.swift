//
//  NewTabPageControllerDaxDialogTests.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
@testable import DuckDuckGo
import Bookmarks
import Combine
import Core
import SwiftUI
import Persistence
import BrowserServicesKit
import RemoteMessaging
import RemoteMessagingTestsUtils
import SubscriptionTestingUtilities
import Onboarding

@testable import Configuration

private class MockURLBasedDebugCommands: URLBasedDebugCommands {
    func handle(url: URL) -> Bool {
        return false
    }
}

@MainActor
final class NewTabPageControllerDaxDialogTests: XCTestCase {

    var variantManager: CapturingVariantManager!
    var dialogFactory: CapturingNewTabDaxDialogProvider!
    var specProvider: MockDaxDialogsManager!
    var flowProvider: MockOnboardingFlowProvider!
    var tutorialSettings: MockTutorialSettings!
    var hvc: NewTabPageViewController!

    override func setUpWithError() throws {
        variantManager = CapturingVariantManager()
        dialogFactory = CapturingNewTabDaxDialogProvider()
        specProvider = MockDaxDialogsManager()
        flowProvider = MockOnboardingFlowProvider()
        tutorialSettings = MockTutorialSettings(hasSeenOnboarding: true)

        let homePageConfiguration = HomePageConfiguration(remoteMessagingStore: MockRemoteMessagingStore(), subscriptionDataReporter: MockSubscriptionDataReporter(), isStillOnboarding: { true }, promptExposureReporter: MockPromptExposureReporter())
        hvc = NewTabPageViewController(
            isFocussedState: false,
            dismissKeyboardOnScroll: false,
            tab: Tab(),
            interactionModel: MockFavoritesListInteracting(),
            homePageMessagesConfiguration: homePageConfiguration,
            newTabDialogFactory: dialogFactory,
            daxDialogsManager: specProvider,
            onboardingFlowProvider: flowProvider,
            faviconLoader: EmptyFaviconLoading(),
            remoteMessagingActionHandler: MockRemoteMessagingActionHandler(),
            remoteMessagingImageLoader: MockRemoteMessagingImageLoader(),
            appSettings: AppSettingsMock(),
            faviconsCache: Favicons(),
            subscriptionManager: SubscriptionManagerMock(),
            internalUserCommands: MockURLBasedDebugCommands(),
            tutorialSettings: tutorialSettings,
        )

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        window.rootViewController?.present(hvc, animated: false, completion: nil)

        let viewLoadedExpectation = expectation(description: "View is loaded")
        DispatchQueue.main.async {
            XCTAssertNotNil(self.hvc.view, "The view should be loaded")
            viewLoadedExpectation.fulfill()
        }
        waitForExpectations(timeout: 5, handler: nil)
        specProvider.nextHomeScreenMessageCalled = false
        specProvider.nextHomeScreenMessageNewCalled = false
    }

    override func tearDownWithError() throws {
        variantManager = nil
        dialogFactory = nil
        specProvider = nil
        flowProvider = nil
        tutorialSettings = nil
        hvc = nil
    }

    func testWhenFocusedContentIsConfiguredBeforeLoadingThenHostedPageIsTransparent() throws {
        let (configuration, _) = makeConfiguration(withScheduledMessage: false)
        let controller = makeNewTabPage(openedAfterIdle: false, homePageMessagesConfiguration: configuration)
        XCTAssertFalse(controller.isViewLoaded)

        controller.setFocusedContent(LegacyFocusedNewTabPageContent(isAddressBarAtBottom: false))
        XCTAssertFalse(controller.isViewLoaded)
        controller.loadViewIfNeeded()

        let page = try XCTUnwrap(controller.children.compactMap { $0 as? UIHostingController<NewTabPageView> }.first)
        XCTAssertEqual(controller.children.count, 1)
        XCTAssertTrue(page.parent === controller)
        XCTAssertTrue(page.view.superview === controller.view)
        XCTAssertEqual(controller.view.backgroundColor, .clear)
        XCTAssertEqual(page.view.backgroundColor, .clear)
    }

    func testWhenLoadedPageChangesFocusedContentThenItRetainsHostAndRestoresBackground() throws {
        let restingBackground = try XCTUnwrap(hvc.view.backgroundColor)
        let page = try XCTUnwrap(hvc.children.compactMap { $0 as? UIHostingController<NewTabPageView> }.first)

        hvc.setFocusedContent(LegacyFocusedNewTabPageContent(isAddressBarAtBottom: true))
        XCTAssertEqual(hvc.view.backgroundColor, .clear)
        XCTAssertEqual(page.view.backgroundColor, .clear)

        hvc.setFocusedContent(nil)
        let restoredBackground = try XCTUnwrap(hvc.view.backgroundColor)
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            XCTAssertEqual(restoredBackground.resolvedColor(with: traits), restingBackground.resolvedColor(with: traits))
        }
        XCTAssertEqual(page.view.backgroundColor, .clear)
        XCTAssertEqual(hvc.children.count, 1)
        XCTAssertTrue(hvc.children.first === page)
    }

    func testWhenPageResizesThenHostedContentFillsContainerAndInheritsSafeArea() throws {
        let page = try XCTUnwrap(hvc.children.compactMap { $0 as? UIHostingController<NewTabPageView> }.first)
        XCTAssertTrue(page.parent === hvc)
        XCTAssertTrue(page.view.superview === hvc.view)

        hvc.additionalSafeAreaInsets = UIEdgeInsets(top: 24, left: 0, bottom: 16, right: 0)
        for size in [CGSize(width: 390, height: 844), CGSize(width: 844, height: 390)] {
            hvc.view.frame = CGRect(origin: .zero, size: size)
            hvc.view.setNeedsLayout()
            hvc.view.layoutIfNeeded()

            XCTAssertEqual(page.view.frame, hvc.view.bounds)
            XCTAssertEqual(page.view.safeAreaInsets, hvc.view.safeAreaInsets)
            XCTAssertFalse(page.view.hasAmbiguousLayout)
        }
    }

    func testWhenDialogIsReplacedThenItRemainsAboveHostedPageInContainer() throws {
        let page = try XCTUnwrap(hvc.children.compactMap { $0 as? UIHostingController<NewTabPageView> }.first)
        specProvider.specToReturn = .initial
        hvc.showNextDaxDialog()
        let firstDialog = try XCTUnwrap(hvc.children.first { $0 !== page })

        hvc.showNextDaxDialog()
        let replacement = try XCTUnwrap(hvc.children.first { $0 !== page })
        hvc.view.layoutIfNeeded()

        XCTAssertNil(firstDialog.parent)
        XCTAssertNil(firstDialog.view.superview)
        XCTAssertEqual(hvc.children.count, 2)
        XCTAssertTrue(replacement.view.superview === page.view.superview)
        let pageIndex = try XCTUnwrap(hvc.view.subviews.firstIndex(of: page.view))
        let dialogIndex = try XCTUnwrap(hvc.view.subviews.firstIndex(of: replacement.view))
        XCTAssertGreaterThan(dialogIndex, pageIndex)
        XCTAssertEqual(replacement.view.frame, hvc.view.bounds)
        XCTAssertFalse(replacement.view.hasAmbiguousLayout)
    }

    func testWhenDialogIsDismissedThenHostedPageRemainsAttached() throws {
        let page = try XCTUnwrap(hvc.children.compactMap { $0 as? UIHostingController<NewTabPageView> }.first)
        specProvider.specToReturn = .initial
        hvc.showNextDaxDialog()
        let dialog = try XCTUnwrap(hvc.children.first { $0 !== page })

        specProvider.specToReturn = nil
        let dismiss = try XCTUnwrap(dialogFactory.onDismiss)
        dismiss(false)

        XCTAssertNil(dialog.parent)
        XCTAssertNil(dialog.view.superview)
        XCTAssertEqual(hvc.children.count, 1)
        XCTAssertTrue(page.parent === hvc)
        XCTAssertTrue(page.view.superview === hvc.view)
    }

    // MARK: - After-idle remote message signal

    /// Builds an NTP the way the focused UTI embedded surface does: a shared messages config and the
    /// after-idle signal passed in (the embedded surface suppresses its own escape hatch, so the
    /// signal can't be derived from it).
    private func makeNewTabPage(openedAfterIdle: Bool,
                                homePageMessagesConfiguration: HomePageMessagesConfiguration) -> NewTabPageViewController {
        NewTabPageViewController(
            isFocussedState: true,
            openedAfterIdle: openedAfterIdle,
            dismissKeyboardOnScroll: false,
            tab: Tab(),
            interactionModel: MockFavoritesListInteracting(),
            homePageMessagesConfiguration: homePageMessagesConfiguration,
            newTabDialogFactory: dialogFactory,
            daxDialogsManager: specProvider,
            onboardingFlowProvider: flowProvider,
            faviconLoader: EmptyFaviconLoading(),
            remoteMessagingActionHandler: MockRemoteMessagingActionHandler(),
            remoteMessagingImageLoader: MockRemoteMessagingImageLoader(),
            appSettings: AppSettingsMock(),
            faviconsCache: Favicons(),
            subscriptionManager: SubscriptionManagerMock(),
            internalUserCommands: MockURLBasedDebugCommands(),
            tutorialSettings: tutorialSettings)
    }

    private func makeConfiguration(withScheduledMessage: Bool) -> (HomePageConfiguration, MockRemoteMessagingStore) {
        let store = MockRemoteMessagingStore()
        if withScheduledMessage {
            store.scheduledRemoteMessage = RemoteMessageModel(
                id: "idle-msg", surfaces: .newTabPage, content: nil, matchingRules: [], exclusionRules: [], isMetricsEnabled: false)
        }
        let config = HomePageConfiguration(remoteMessagingStore: store,
                                           subscriptionDataReporter: MockSubscriptionDataReporter(),
                                           isStillOnboarding: { false }, promptExposureReporter: MockPromptExposureReporter())
        return (config, store)
    }

    func testWhenOpenedAfterIdleTrueThenMessagesConfigFetchesWithAfterIdleTrigger() {
        // GIVEN a shared config with a scheduled after-idle message
        let (config, store) = makeConfiguration(withScheduledMessage: true)

        // WHEN an embedded (hatch-suppressed) NTP is built seeded with the after-idle signal
        _ = makeNewTabPage(openedAfterIdle: true, homePageMessagesConfiguration: config)

        // THEN its first refresh fetches the after-idle message (not .noTrigger) and keeps it in the
        // shared config the focused-content gate reads
        XCTAssertEqual(store.capturedTriggerFilter, .specific(.afterIdle))
        XCTAssertFalse(config.homeMessages.isEmpty)
    }

    func testWhenOpenedAfterIdleFalseThenMessagesConfigFetchesWithNoTrigger() {
        // GIVEN
        let (config, store) = makeConfiguration(withScheduledMessage: true)

        // WHEN a non-after-idle NTP is built
        _ = makeNewTabPage(openedAfterIdle: false, homePageMessagesConfiguration: config)

        // THEN it fetches the standard (.noTrigger) message, not the after-idle one
        XCTAssertEqual(store.capturedTriggerFilter, .noTrigger)
    }

    func testWhenSetOpenedAfterIdleTrueThenMessagesConfigRefetchesWithAfterIdleTrigger() {
        // GIVEN a cached NTP originally built without the after-idle signal
        let (config, store) = makeConfiguration(withScheduledMessage: true)
        let controller = makeNewTabPage(openedAfterIdle: false, homePageMessagesConfiguration: config)
        store.capturedTriggerFilter = nil

        // WHEN a later after-idle session pushes the signal into the cached controller
        controller.setOpenedAfterIdle(true)

        // THEN it re-fetches with the after-idle trigger
        XCTAssertEqual(store.capturedTriggerFilter, .specific(.afterIdle))
    }

    func testWhenViewDidAppearWithInitialSpecThenDaxDialogIsCreated() throws {
        // GIVEN
        let expectedSpec = DaxDialogs.HomeScreenSpec.initial
        specProvider.specToReturn = expectedSpec

        // WHEN
        hvc.viewDidAppear(false)

        // THEN
        XCTAssertFalse(self.specProvider.nextHomeScreenMessageCalled)
        XCTAssertTrue(self.specProvider.nextHomeScreenMessageNewCalled)
        XCTAssertEqual(self.dialogFactory.homeDialog, expectedSpec)
        XCTAssertNotNil(self.dialogFactory.onDismiss)
        XCTAssertNil(self.dialogFactory.endOfJourneyContent)
    }

    func testWhenOnboardingCompletesWithInitialSpecThenDaxDialogIsCreated() throws {
        // GIVEN
        let expectedSpec = DaxDialogs.HomeScreenSpec.initial
        specProvider.specToReturn = expectedSpec

        // WHEN
        hvc.onboardingCompleted()

        // THEN
        XCTAssertFalse(self.specProvider.nextHomeScreenMessageCalled)
        XCTAssertTrue(self.specProvider.nextHomeScreenMessageNewCalled)
        XCTAssertEqual(self.dialogFactory.homeDialog, expectedSpec)
        XCTAssertNotNil(self.dialogFactory.onDismiss)
        XCTAssertNil(self.dialogFactory.endOfJourneyContent)
    }

    func testWhenOnboardingCompletesWithFinalSpecThenEndOfJourneyDialogIsCreated() throws {
        // GIVEN
        specProvider.specToReturn = .final

        // WHEN
        hvc.onboardingCompleted()

        // THEN
        XCTAssertFalse(specProvider.nextHomeScreenMessageCalled)
        XCTAssertTrue(specProvider.nextHomeScreenMessageNewCalled)
        XCTAssertNil(dialogFactory.homeDialog)
        XCTAssertNil(dialogFactory.onDismiss)
        XCTAssertNotNil(dialogFactory.endOfJourneyContent)
        XCTAssertNotNil(dialogFactory.onEndOfJourneyAction)
    }

    func testWhenShowNextDaxDialog_AndShouldShowDaxDialogs_ThenReturnTrue() {
        // WHEN
        hvc.showNextDaxDialog()

        // THEN
        XCTAssertTrue(specProvider.nextHomeScreenMessageNewCalled)
    }

    // MARK: - Duck.ai tailored flow router branches

    func testWhenDuckAITailoredFlow_AndOnboardingCompleted_AndNotSkipped_ThenDoesNotPeekRegularSpec() {
        // GIVEN
        flowProvider.currentOnboardingFlow = .duckAI
        tutorialSettings.hasSkippedOnboarding = false

        // WHEN
        hvc.onboardingCompleted()

        // THEN
        // Tailored completion routes to `showDuckAIOnboardingCompletionWithActiveAddressBar`, not
        // through the regular Dax sequence — confirms the tailored branch is taken, not default.
        XCTAssertFalse(specProvider.nextHomeScreenMessageNewCalled)
    }

    func testWhenDuckAITailoredFlow_AndOnboardingCompleted_AndSkipped_ThenDoesNotPeekRegularSpec() {
        // GIVEN
        flowProvider.currentOnboardingFlow = .duckAI
        tutorialSettings.hasSkippedOnboarding = true

        // WHEN
        hvc.onboardingCompleted()

        // THEN
        // Skip branch only calls `omniBar.beginEditing` for AI chat; no Dax dialog should be peeked.
        XCTAssertFalse(specProvider.nextHomeScreenMessageNewCalled)
    }

    func testWhenDuckAITailoredFlow_AndDialogRequested_AndSubscriptionPromoPending_ThenPeeksSpecToRenderPromo() {
        // GIVEN
        flowProvider.currentOnboardingFlow = .duckAI
        specProvider.subscriptionPromotionPending = true

        // WHEN
        hvc.showNextDaxDialog()

        // THEN
        // Tailored router only proceeds to showNextDaxDialogNew (which peeks the spec) when the
        // subscription promo is pending — confirming the gate is read and the promo path is taken.
        XCTAssertTrue(specProvider.nextHomeScreenMessageNewCalled)
    }

    func testWhenDuckAITailoredFlow_AndDialogRequested_AndSubscriptionPromoNotPending_ThenDoesNotPeekSpec() {
        // GIVEN
        flowProvider.currentOnboardingFlow = .duckAI
        specProvider.subscriptionPromotionPending = false

        // WHEN
        hvc.showNextDaxDialog()

        // THEN
        // Tailored router must NOT enter the regular Dax sequence when there is no promo — otherwise
        // a stray `.initial`/`.subsequent` dialog could leak into the Duck.ai onboarding completion UX.
        XCTAssertFalse(specProvider.nextHomeScreenMessageNewCalled)
    }
}

class CapturingVariantManager: VariantManager {
    var currentVariant: Variant?
    var capturedFeatureName: FeatureName?
    var supportedFeatures: [FeatureName] = []

    func assignVariantIfNeeded(_ newInstallCompletion: (BrowserServicesKit.VariantManager) -> Void) {
    }

    func isSupported(feature: FeatureName) -> Bool {
        capturedFeatureName = feature
        return supportedFeatures.contains(feature)
    }
}

class CapturingNewTabDaxDialogProvider: NewTabDaxDialogProviding {
    var homeDialog: DaxDialogs.HomeScreenSpec?
    var onDismiss: ((_ activateSearch: Bool) -> Void)?
    var endOfJourneyContent: OnboardingEndOfJourneyContent?
    var onEndOfJourneyAction: ((OnboardingEndOfJourneyAction) -> Void)?

    func createDaxDialog(for homeDialog: DaxDialogs.HomeScreenSpec, onCompletion: @escaping (_ activateSearch: Bool) -> Void, onManualDismiss: @escaping () -> Void) -> some View {
        self.homeDialog = homeDialog
        self.onDismiss = onCompletion
        return EmptyView()
    }

    func createDuckAIFireOnboardingCompletionDialog(message: String, onDismiss: @escaping () -> Void) -> AnyView {
        AnyView(EmptyView())
    }

    func createEndOfJourneyDialog(content: OnboardingEndOfJourneyContent, onAction: @escaping (OnboardingEndOfJourneyAction) -> Void) -> AnyView {
        endOfJourneyContent = content
        onEndOfJourneyAction = onAction
        return AnyView(EmptyView())
    }
}

final class MockOnboardingFlowProvider: OnboardingFlowProviding {
    var currentOnboardingFlow: OnboardingFlowType = .default
}

struct MockVariant: Variant {
    var name: String = ""
    var weight: Int = 0
    var isIncluded: () -> Bool = { false }
    var features: [BrowserServicesKit.FeatureName] = []

    init(features: [BrowserServicesKit.FeatureName]) {
        self.features = features
    }
}
