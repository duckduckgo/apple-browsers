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

        let homePageConfiguration = HomePageConfiguration(remoteMessagingStore: MockRemoteMessagingStore(), subscriptionDataReporter: MockSubscriptionDataReporter(), isStillOnboarding: { true })
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

    func testWhenViewDidAppear_CorrectTypePassedToDialogFactory() throws {
        // GIVEN
        let expectedSpec = randomDialogType()
        specProvider.specToReturn = expectedSpec

        // WHEN
        hvc.viewDidAppear(false)

        // THEN
        XCTAssertFalse(self.specProvider.nextHomeScreenMessageCalled)
        XCTAssertTrue(self.specProvider.nextHomeScreenMessageNewCalled)
        XCTAssertEqual(self.dialogFactory.homeDialog, expectedSpec)
        XCTAssertNotNil(self.dialogFactory.onDismiss)
    }

    func testWhenOnboardingComplete_CorrectTypePassedToDialogFactory() throws {
        // GIVEN
        let expectedSpec = randomDialogType()
        specProvider.specToReturn = expectedSpec

        // WHEN
        hvc.onboardingCompleted()

        // THEN
        XCTAssertFalse(self.specProvider.nextHomeScreenMessageCalled)
        XCTAssertTrue(self.specProvider.nextHomeScreenMessageNewCalled)
        XCTAssertEqual(self.dialogFactory.homeDialog, expectedSpec)
        XCTAssertNotNil(self.dialogFactory.onDismiss)
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

    private func randomDialogType() -> DaxDialogs.HomeScreenSpec {
        let specs: [DaxDialogs.HomeScreenSpec] = [.initial, .subsequent, .final, .addFavorite]
        return specs.randomElement()!
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
    func createDaxDialog(for homeDialog: DaxDialogs.HomeScreenSpec, onCompletion: @escaping (_ activateSearch: Bool) -> Void, onManualDismiss: @escaping () -> Void) -> some View {
        self.homeDialog = homeDialog
        self.onDismiss = onCompletion
        return EmptyView()
    }

    func createExperimentCompletionDialog(message: String, onDismiss: @escaping () -> Void) -> AnyView {
        AnyView(EmptyView())
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
