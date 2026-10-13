//
//  NewTabPageOnboardingCoordinatorTests.swift
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
import SwiftUI
import Onboarding
@testable import DuckDuckGo

@MainActor
final class NewTabPageOnboardingCoordinatorTests: XCTestCase {
    private var dialogs: MockDaxDialogsManager!
    private var factory: DialogFactory!
    private var tutorial: MockTutorialSettings!
    private var flow: FlowProvider!
    private var coordinator: NewTabPageOnboardingCoordinator!
    private var page: RedesignedNewTabPageViewController!

    override func setUp() {
        super.setUp()
        dialogs = MockDaxDialogsManager()
        factory = DialogFactory()
        tutorial = MockTutorialSettings(hasSeenOnboarding: true)
        flow = FlowProvider()
        coordinator = NewTabPageOnboardingCoordinator(newTabDialogFactory: factory,
                                                      daxDialogsManager: dialogs,
                                                      onboardingFlowProvider: flow,
                                                      floatingUIManager: FloatingUIManager(isFloatingUIFeatureEnabled: false),
                                                      tutorialSettings: tutorial,
                                                      unifiedToggleInputFeature: InputFeature())
        page = RedesignedNewTabPageViewController(blocks: [], onboardingCoordinator: coordinator)
        page.loadViewIfNeeded()
    }

    override func tearDown() {
        page = nil
        coordinator = nil
        flow = nil
        tutorial = nil
        factory = nil
        dialogs = nil
        super.tearDown()
    }

    func testWhenLinearOnboardingIsIncompleteThenNoDialogIsPresented() {
        tutorial.hasSeenOnboarding = false
        dialogs.specToReturn = .initial

        page.showNextDaxDialog()

        XCTAssertFalse(dialogs.nextHomeScreenMessageNewCalled)
        XCTAssertFalse(coordinator.isPresentingDialog)
        XCTAssertTrue(page.canAnimateSearchInput)
    }

    func testWhenOnboardingCompletesThenDialogReplacesRestingContent() {
        dialogs.specToReturn = .initial

        page.onboardingCompleted()

        XCTAssertEqual(factory.specs, [.initial])
        XCTAssertEqual(page.children.count, 1)
        XCTAssertFalse(page.canAnimateSearchInput)
        XCTAssertTrue(coordinator.isPresentingDialog)
    }

    func testWhenDialogIsDismissedThenRestingContentIsRestored() {
        dialogs.specToReturn = .initial
        page.showNextDaxDialog()
        dialogs.specToReturn = nil

        factory.onCompletion?(false)

        XCTAssertTrue(dialogs.dismissCalled)
        XCTAssertTrue(page.children.isEmpty)
        XCTAssertTrue(page.canAnimateSearchInput)
    }

    func testWhenPageAppearsAgainThenDialogIsRebuiltWithoutStacking() {
        dialogs.specToReturn = .initial
        page.showNextDaxDialog()

        dialogs.nextHomeScreenMessageNewCalled = false
        coordinator.pageDidAppear()

        XCTAssertTrue(dialogs.nextHomeScreenMessageNewCalled)
        XCTAssertEqual(factory.specs, [.initial, .initial])
        XCTAssertEqual(page.children.count, 1)
    }

    func testWhenDefaultFlowPromotionIsNoLongerDueThenRestingContentReturns() {
        dialogs.subscriptionPromotionPending = true
        dialogs.specToReturn = .subscriptionPromotion
        page.showNextDaxDialog()
        XCTAssertTrue(page.isPresentingOnboardingDialog)

        dialogs.subscriptionPromotionPending = false
        dialogs.specToReturn = nil
        coordinator.pageDidAppear()

        XCTAssertFalse(page.isPresentingOnboardingDialog)
        XCTAssertTrue(page.children.isEmpty)
        XCTAssertTrue(page.canAnimateSearchInput)
    }

    func testWhenPageDetachesThenDialogStateIsKeptUntilReappearance() {
        dialogs.specToReturn = .initial
        page.showNextDaxDialog()

        page.dismiss()

        XCTAssertTrue(coordinator.isPresentingDialog)
        XCTAssertEqual(page.children.count, 1)
        XCTAssertFalse(dialogs.dismissCalled, "Leaving a tab must not complete contextual onboarding")
        coordinator.pageDidAppear()
        XCTAssertTrue(coordinator.isPresentingDialog)
        XCTAssertEqual(factory.specs, [.initial, .initial])
    }

    func testWhenInputIsFocusedThenOnboardingRemainsAccessible() {
        page.setSearchInputEditing(true)
        XCTAssertTrue(page.view.accessibilityElementsHidden)
        dialogs.specToReturn = .initial

        page.showNextDaxDialog()

        XCTAssertFalse(page.view.accessibilityElementsHidden)
        dialogs.specToReturn = nil
        factory.onCompletion?(false)
        XCTAssertTrue(page.view.accessibilityElementsHidden)
        page.setSearchInputEditing(false)
        XCTAssertFalse(page.view.accessibilityElementsHidden)
    }

    func testWhenTailoredFlowHasNoPromotionThenRegularDaxSequenceIsSkipped() {
        flow.currentOnboardingFlow = .duckAI
        dialogs.specToReturn = .initial
        dialogs.subscriptionPromotionPending = false

        page.showNextDaxDialog()

        XCTAssertFalse(dialogs.nextHomeScreenMessageNewCalled)
        XCTAssertFalse(coordinator.isPresentingDialog)
    }

    func testWhenTailoredFlowHasPendingPromotionThenItIsPresented() {
        flow.currentOnboardingFlow = .duckAI
        dialogs.specToReturn = .subscriptionPromotion
        dialogs.subscriptionPromotionPending = true

        page.showNextDaxDialog()

        XCTAssertEqual(factory.specs, [.subscriptionPromotion])
        XCTAssertTrue(coordinator.isPresentingDialog)
    }

    func testWhenFinalDialogIsRequestedThenContentDrivenCompletionIsUsed() {
        dialogs.specToReturn = .final

        page.showNextDaxDialog()

        XCTAssertTrue(factory.specs.isEmpty)
        XCTAssertNotNil(factory.onEndOfJourneyAction)
        XCTAssertTrue(coordinator.isPresentingDialog)
    }

    func testFinalDuckAIInputActivationCannotCaptureRestingPageContent() {
        let input = MockOmniBar()
        let chrome = DuckPlayerBrowserChromeDelegateMock()
        chrome.omniBar = input
        coordinator = NewTabPageOnboardingCoordinator(newTabDialogFactory: factory,
                                                      daxDialogsManager: dialogs,
                                                      onboardingFlowProvider: flow,
                                                      floatingUIManager: FloatingUIManager(isFloatingUIFeatureEnabled: false),
                                                      tutorialSettings: tutorial,
                                                      unifiedToggleInputFeature: InputFeature(isAvailable: true))
        page = RedesignedNewTabPageViewController(blocks: [], onboardingCoordinator: coordinator)
        page.loadViewIfNeeded()
        page.chromeDelegate = chrome
        dialogs.specToReturn = .final
        var didBeginEditing = false
        input.onBeginEditing = { [unowned self] in
            didBeginEditing = true
            XCTAssertFalse(page.canAnimateSearchInput)
            XCTAssertTrue(page.isPresentingOnboardingDialog)
            XCTAssertTrue(chrome.isUnifiedInputContentOverlaySuppressed)
        }

        page.showNextDaxDialog()

        XCTAssertTrue(didBeginEditing)
    }

    func testIdlePageClearsOverlaySuppressionLeftByAnotherOnboardingPresenter() {
        let chrome = DuckPlayerBrowserChromeDelegateMock()
        chrome.isUnifiedInputContentOverlaySuppressed = true
        page.chromeDelegate = chrome

        coordinator.pageDidAppear()

        XCTAssertFalse(chrome.isUnifiedInputContentOverlaySuppressed)
    }

    func testWhenNoDialogIsDueThenExistingLogoVisibilityIsPreservedWithoutSurfaceNotifications() {
        let welcome = NewTabPageSwiftUIBlock(id: .welcome, rootView: Text("Welcome"))
        page = RedesignedNewTabPageViewController(blocks: [welcome], onboardingCoordinator: coordinator)
        page.loadViewIfNeeded()
        page.setLogoHidden(true)
        var surfaceChanges = 0
        let observer = NotificationCenter.default.addObserver(
            forName: RemoteMessageImpressionReporter.remoteMessageSurfaceDidChange, object: page, queue: .main) { _ in
            surfaceChanges += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        coordinator.pageDidAppear()

        XCTAssertEqual(welcome.viewController.view.alpha, 0)
        XCTAssertEqual(surfaceChanges, 0)
    }

    private final class FlowProvider: OnboardingFlowProviding {
        var currentOnboardingFlow: OnboardingFlowType = .default
    }

    private struct InputFeature: UnifiedToggleInputFeatureProviding {
        var isAvailable: Bool = false
        var isToggleHiddenOnDuckAITab: Bool { false }
        var isAttachmentPasteEnabled: Bool { false }
    }

    private final class DialogFactory: NewTabDaxDialogProviding {
        var specs: [DaxDialogs.HomeScreenSpec] = []
        var onCompletion: ((Bool) -> Void)?
        var onEndOfJourneyAction: ((OnboardingEndOfJourneyAction) -> Void)?

        func createDaxDialog(for homeDialog: DaxDialogs.HomeScreenSpec,
                             onCompletion: @escaping (Bool) -> Void,
                             onManualDismiss: @escaping () -> Void) -> some View {
            specs.append(homeDialog)
            self.onCompletion = onCompletion
            return EmptyView()
        }

        func createDuckAIFireOnboardingCompletionDialog(message: String, onDismiss: @escaping () -> Void) -> AnyView {
            AnyView(EmptyView())
        }

        func createEndOfJourneyDialog(content: OnboardingEndOfJourneyContent,
                                      onAction: @escaping (OnboardingEndOfJourneyAction) -> Void) -> AnyView {
            onEndOfJourneyAction = onAction
            return AnyView(EmptyView())
        }
    }
}
