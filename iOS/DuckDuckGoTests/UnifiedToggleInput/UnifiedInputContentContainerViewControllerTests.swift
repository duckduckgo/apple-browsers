//
//  UnifiedInputContentContainerViewControllerTests.swift
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
import Bookmarks
import BrowserServicesKit
import BrowserServicesKitTestsUtils
import Combine
import Core
import History
import Onboarding
import Persistence
import PrivacyConfig
import RemoteMessaging
import Suggestions
import SubscriptionTestingUtilities
import SwiftUI
import UIKit
import XCTest
@testable import DuckDuckGo

@MainActor
final class UnifiedInputContentContainerViewControllerTests: XCTestCase {

    func testDuckAISuggestionsDidRequestSyncSetup_RequestsSyncSetupOnDelegate() {
        let delegate = MockUnifiedInputContentContainerDelegate()
        let viewController = UnifiedInputContentContainerViewController(
            switchBarHandler: MockUnifiedInputSwitchBarHandler()
        )
        viewController.delegate = delegate

        viewController.duckAISuggestionsDidRequestSyncSetup()

        XCTAssertEqual(delegate.syncSetupRequestCount, 1)
    }

    func testActiveUnifiedFavoritesKeepsCachedNewTabPageActiveOnlyWhileFavoritesAreExposed() async {
        let fixture = PromoHostFixture()
        fixture.appSettings.autocomplete = false
        let switchBarHandler = MockUnifiedInputSwitchBarHandler()
        let sut = UnifiedInputContentContainerViewController(
            switchBarHandler: switchBarHandler,
            appSettings: fixture.appSettings,
            featureFlagger: fixture.featureFlagger,
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            aiChatSettings: fixture.aiChatSettings,
            featureDiscovery: fixture.featureDiscovery
        )
        sut.suggestionTrayDependencies = fixture.suggestionTrayDependencies
        let retryTargetRegistered = expectation(description: "Unified favorites NTP registered for promo retry")
        fixture.promoCoordinator.onRetryTargetRegistered = { _ in
            retryTargetRegistered.fulfill()
        }
        let firstAdmission = expectation(description: "Unified favorites RMF acquired its surface slot")
        fixture.promoCoordinator.onVisibleLeaseAcquired = { _ in
            firstAdmission.fulfill()
        }
        let window = makeVisibleWindow(rootViewController: sut)
        defer {
            detachAndHide(window)
            fixture.tearDownSuggestionDependencies()
        }

        sut.setActive(true)
        await fulfillment(of: [retryTargetRegistered, firstAdmission], timeout: 3)
        fixture.promoCoordinator.onVisibleLeaseAcquired = nil

        let cachedTarget = fixture.promoCoordinator.retryTarget
        XCTAssertNotNil(cachedTarget)
        XCTAssertTrue(cachedTarget?.isActiveForPromoRetry == true)
        let firstOwner = fixture.promoCoordinator.arbiter.snapshot.visiblePromoIdentity
        XCTAssertNotNil(firstOwner)

        let firstRelease = expectation(description: "Query hid the unified favorites RMF and released its slot")
        fixture.promoCoordinator.onVisibleLeaseReleased = {
            firstRelease.fulfill()
        }
        sut.setText("query")
        await fulfillment(of: [firstRelease], timeout: 1)
        fixture.promoCoordinator.onVisibleLeaseReleased = nil

        XCTAssertTrue(fixture.promoCoordinator.retryTarget === cachedTarget)
        XCTAssertFalse(cachedTarget?.isActiveForPromoRetry == true)
        XCTAssertNil(fixture.promoCoordinator.arbiter.snapshot.activeOwner)
        let hiddenAttemptCount = fixture.promoCoordinator.admissionAttemptCount
        cachedTarget?.retryRemoteMessageAdmission(using: fixture.promoCoordinator.admitRemoteMessage)
        XCTAssertEqual(fixture.promoCoordinator.admissionAttemptCount, hiddenAttemptCount)
        XCTAssertNil(fixture.promoCoordinator.arbiter.snapshot.activeOwner)

        let secondAdmission = expectation(description: "Clearing the query reacquired the unified favorites RMF slot")
        fixture.promoCoordinator.onVisibleLeaseAcquired = { _ in
            secondAdmission.fulfill()
        }
        sut.setText("")
        await fulfillment(of: [secondAdmission], timeout: 1)
        fixture.promoCoordinator.onVisibleLeaseAcquired = nil

        XCTAssertTrue(fixture.promoCoordinator.retryTarget === cachedTarget)
        XCTAssertTrue(cachedTarget?.isActiveForPromoRetry == true)
        XCTAssertEqual(fixture.promoCoordinator.arbiter.snapshot.visiblePromoIdentity, firstOwner)

        let secondRelease = expectation(description: "Fire mode released the unified favorites RMF slot")
        fixture.promoCoordinator.onVisibleLeaseReleased = {
            secondRelease.fulfill()
        }
        sut.refreshFireMode(fireMode: true)
        await fulfillment(of: [secondRelease], timeout: 1)
        fixture.promoCoordinator.onVisibleLeaseReleased = nil

        XCTAssertFalse(cachedTarget?.isActiveForPromoRetry == true)
        XCTAssertNil(fixture.promoCoordinator.arbiter.snapshot.activeOwner)
        let fireModeAttemptCount = fixture.promoCoordinator.admissionAttemptCount
        cachedTarget?.retryRemoteMessageAdmission(using: fixture.promoCoordinator.admitRemoteMessage)
        XCTAssertEqual(fixture.promoCoordinator.admissionAttemptCount, fireModeAttemptCount)
        XCTAssertNil(fixture.promoCoordinator.arbiter.snapshot.activeOwner)

        let thirdAdmission = expectation(description: "Leaving fire mode reacquired the unified favorites RMF slot")
        fixture.promoCoordinator.onVisibleLeaseAcquired = { _ in
            thirdAdmission.fulfill()
        }
        sut.refreshFireMode(fireMode: false)
        await fulfillment(of: [thirdAdmission], timeout: 1)
        fixture.promoCoordinator.onVisibleLeaseAcquired = nil

        XCTAssertTrue(cachedTarget?.isActiveForPromoRetry == true)
        XCTAssertEqual(fixture.promoCoordinator.arbiter.snapshot.visiblePromoIdentity, firstOwner)

        let thirdRelease = expectation(description: "Inactive unified input released the favorites RMF slot")
        fixture.promoCoordinator.onVisibleLeaseReleased = {
            thirdRelease.fulfill()
        }
        sut.setActive(false)
        await fulfillment(of: [thirdRelease], timeout: 1)
        fixture.promoCoordinator.onVisibleLeaseReleased = nil

        XCTAssertFalse(cachedTarget?.isActiveForPromoRetry == true)
        XCTAssertNil(fixture.promoCoordinator.arbiter.snapshot.activeOwner)
        XCTAssertEqual(fixture.promoCoordinator.successfulAdmissionCount, 3)
        XCTAssertEqual(fixture.promoCoordinator.releaseCount, 3)
    }
}

@MainActor
final class NewTabPagePromoHostWiringTests: XCTestCase {

    func testPromoSurfaceExposureRequiresAllFiveHostSignals() {
        let fullyExposed = NewTabPagePromoSurfaceExposure(
            isOwnerActive: true,
            isRenderLocationReady: true,
            isExplicitlyVisible: true,
            isCovered: false
        )

        XCTAssertTrue(fullyExposed.isRenderable(isAttachedToWindow: true))

        let blockingStates: [(String, WritableKeyPath<NewTabPagePromoSurfaceExposure, Bool>, Bool)] = [
            ("owner inactive", \.isOwnerActive, false),
            ("render location not ready", \.isRenderLocationReady, false),
            ("explicitly hidden", \.isExplicitlyVisible, false),
            ("covered", \.isCovered, true),
        ]
        for (name, keyPath, blockingValue) in blockingStates {
            XCTContext.runActivity(named: name) { _ in
                var exposure = fullyExposed
                exposure[keyPath: keyPath] = blockingValue
                XCTAssertFalse(exposure.isRenderable(isAttachedToWindow: true))
            }
        }

        XCTAssertFalse(
            fullyExposed.isRenderable(isAttachedToWindow: false),
            "A detached NTP must not expose its promo surface"
        )
    }

    func testPromoSurfaceHandoffDeactivatesNewTabPageBeforeShowingHostedSurface() {
        var events = [String]()

        NewTabPagePromoSurfaceHandoff.showHostedSurface(
            deactivateNewTabPage: {
                events.append("deactivate-standard-ntp")
            },
            showHostedSurface: {
                events.append("show-suggestion-or-unified-host")
            }
        )

        XCTAssertEqual(events, ["deactivate-standard-ntp", "show-suggestion-or-unified-host"])
    }

    func testPromoSurfaceHandoffHidesHostedSurfaceBeforeReactivatingNewTabPage() {
        var events = [String]()

        NewTabPagePromoSurfaceHandoff.showNewTabPage(
            hideHostedSurface: {
                events.append("hide-suggestion-or-unified-host")
            },
            activateNewTabPage: {
                events.append("activate-standard-ntp")
            }
        )

        XCTAssertEqual(events, ["hide-suggestion-or-unified-host", "activate-standard-ntp"])
    }

    func testWindowAttachedStandardNewTabPageIsRetryActiveOnlyWhileOwnerIsActive() async {
        let fixture = PromoHostFixture()
        let sut = fixture.makeNewTabPageController(isFocussedState: false)
        let window = makeVisibleWindow(rootViewController: sut)
        defer { detachAndHide(window) }
        await nextMainQueueTurn()

        let retryTarget = fixture.promoCoordinator.retryTarget
        XCTAssertNotNil(retryTarget)
        XCTAssertFalse(retryTarget?.isActiveForPromoRetry == true)
        XCTAssertNil(fixture.promoCoordinator.arbiter.snapshot.activeOwner)

        let firstAdmission = expectation(description: "Standard NTP RMF acquired its surface slot")
        fixture.promoCoordinator.onVisibleLeaseAcquired = { _ in
            firstAdmission.fulfill()
        }
        sut.setPromoSurfaceActive(true)
        await fulfillment(of: [firstAdmission], timeout: 1)
        fixture.promoCoordinator.onVisibleLeaseAcquired = nil

        XCTAssertTrue(retryTarget?.isActiveForPromoRetry == true)
        let firstOwner = fixture.promoCoordinator.arbiter.snapshot.visiblePromoIdentity
        XCTAssertNotNil(firstOwner)

        let firstRelease = expectation(description: "Inactive standard NTP released its RMF slot")
        fixture.promoCoordinator.onVisibleLeaseReleased = {
            firstRelease.fulfill()
        }
        sut.setPromoSurfaceActive(false)

        XCTAssertFalse(retryTarget?.isActiveForPromoRetry == true)
        XCTAssertEqual(fixture.promoCoordinator.arbiter.snapshot.visiblePromoIdentity, firstOwner)
        await fulfillment(of: [firstRelease], timeout: 1)
        fixture.promoCoordinator.onVisibleLeaseReleased = nil
        XCTAssertNil(fixture.promoCoordinator.arbiter.snapshot.activeOwner)
        let hiddenAttemptCount = fixture.promoCoordinator.admissionAttemptCount
        retryTarget?.retryRemoteMessageAdmission(using: fixture.promoCoordinator.admitRemoteMessage)
        XCTAssertEqual(fixture.promoCoordinator.admissionAttemptCount, hiddenAttemptCount)
        XCTAssertNil(fixture.promoCoordinator.arbiter.snapshot.activeOwner)

        let secondAdmission = expectation(description: "Reactivated standard NTP reacquired its RMF slot")
        fixture.promoCoordinator.onVisibleLeaseAcquired = { _ in
            secondAdmission.fulfill()
        }
        sut.setPromoSurfaceActive(true)
        await fulfillment(of: [secondAdmission], timeout: 1)
        fixture.promoCoordinator.onVisibleLeaseAcquired = nil
        XCTAssertEqual(fixture.promoCoordinator.arbiter.snapshot.visiblePromoIdentity, firstOwner)

        let secondRelease = expectation(description: "Detached standard NTP released its RMF slot")
        fixture.promoCoordinator.onVisibleLeaseReleased = {
            secondRelease.fulfill()
        }
        window.rootViewController = UIViewController()
        await fulfillment(of: [secondRelease], timeout: 1)
        fixture.promoCoordinator.onVisibleLeaseReleased = nil

        XCTAssertFalse(retryTarget?.isActiveForPromoRetry == true)
        XCTAssertNil(fixture.promoCoordinator.arbiter.snapshot.activeOwner)
        XCTAssertEqual(fixture.promoCoordinator.successfulAdmissionCount, 2)
        XCTAssertEqual(fixture.promoCoordinator.releaseCount, 2)
    }

    func testStaleVisibilityCompletionCannotReactivateNewerHiddenStandardNewTabPage() async {
        let fixture = PromoHostFixture()
        let sut = fixture.makeNewTabPageController(isFocussedState: false)
        let window = makeVisibleWindow(rootViewController: sut)
        defer { detachAndHide(window) }
        await nextMainQueueTurn()

        let firstAdmission = expectation(description: "Standard NTP RMF acquired its surface slot")
        fixture.promoCoordinator.onVisibleLeaseAcquired = { _ in
            firstAdmission.fulfill()
        }
        sut.setPromoSurfaceActive(true)
        await fulfillment(of: [firstAdmission], timeout: 1)
        fixture.promoCoordinator.onVisibleLeaseAcquired = nil

        let release = expectation(description: "Explicitly hidden standard NTP released its RMF slot")
        fixture.promoCoordinator.onVisibleLeaseReleased = {
            release.fulfill()
        }
        let staleGeneration = sut.setPromoSurfaceVisible(false)
        let currentGeneration = sut.setPromoSurfaceVisible(false)
        await fulfillment(of: [release], timeout: 1)
        fixture.promoCoordinator.onVisibleLeaseReleased = nil

        let admissionCountBeforeStaleCompletion = fixture.promoCoordinator.admissionAttemptCount
        sut.restorePromoSurfaceVisibility(ifCurrent: staleGeneration)

        XCTAssertFalse(fixture.promoCoordinator.retryTarget?.isActiveForPromoRetry == true)
        XCTAssertEqual(fixture.promoCoordinator.admissionAttemptCount, admissionCountBeforeStaleCompletion)

        let secondAdmission = expectation(description: "Current completion restored standard NTP visibility")
        fixture.promoCoordinator.onVisibleLeaseAcquired = { _ in
            secondAdmission.fulfill()
        }
        sut.restorePromoSurfaceVisibility(ifCurrent: currentGeneration)
        await fulfillment(of: [secondAdmission], timeout: 1)

        XCTAssertTrue(fixture.promoCoordinator.retryTarget?.isActiveForPromoRetry == true)
    }

    func testAutocompleteKeepsCachedTrayNewTabPageInactiveUntilFavoritesReturn() async throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "The tray caches its NTP below autocomplete only on iPhone"
        )
        let fixture = PromoHostFixture()
        let sut = fixture.makeSuggestionTrayController()
        let window = makeVisibleWindow(rootViewController: sut)
        defer {
            detachAndHide(window)
            fixture.tearDownSuggestionDependencies()
        }

        let firstAdmission = expectation(description: "Tray favorites RMF acquired its surface slot")
        fixture.promoCoordinator.onVisibleLeaseAcquired = { _ in
            firstAdmission.fulfill()
        }
        sut.show(for: .favorites, animated: false)
        sut.view.layoutIfNeeded()
        await fulfillment(of: [firstAdmission], timeout: 1)
        fixture.promoCoordinator.onVisibleLeaseAcquired = nil

        let cachedTarget = fixture.promoCoordinator.retryTarget
        XCTAssertNotNil(cachedTarget)
        XCTAssertTrue(cachedTarget?.isActiveForPromoRetry == true)
        let firstOwner = fixture.promoCoordinator.arbiter.snapshot.visiblePromoIdentity
        XCTAssertNotNil(firstOwner)

        let firstRelease = expectation(description: "Tray autocomplete released the cached favorites RMF slot")
        fixture.promoCoordinator.onVisibleLeaseReleased = {
            firstRelease.fulfill()
        }
        sut.show(for: .autocomplete(query: "https://example.com/"), animated: false)

        XCTAssertTrue(sut.isShowingFavorites)
        XCTAssertTrue(fixture.promoCoordinator.retryTarget === cachedTarget)
        XCTAssertFalse(cachedTarget?.isActiveForPromoRetry == true)
        XCTAssertEqual(fixture.promoCoordinator.arbiter.snapshot.visiblePromoIdentity, firstOwner)
        await fulfillment(of: [firstRelease], timeout: 1)
        fixture.promoCoordinator.onVisibleLeaseReleased = nil
        XCTAssertNil(fixture.promoCoordinator.arbiter.snapshot.activeOwner)
        let hiddenAttemptCount = fixture.promoCoordinator.admissionAttemptCount
        cachedTarget?.retryRemoteMessageAdmission(using: fixture.promoCoordinator.admitRemoteMessage)
        XCTAssertEqual(fixture.promoCoordinator.admissionAttemptCount, hiddenAttemptCount)
        XCTAssertNil(fixture.promoCoordinator.arbiter.snapshot.activeOwner)

        let secondAdmission = expectation(description: "Returning to tray favorites reacquired the RMF slot")
        fixture.promoCoordinator.onVisibleLeaseAcquired = { _ in
            secondAdmission.fulfill()
        }
        sut.show(for: .favorites, animated: false)
        sut.view.layoutIfNeeded()
        await fulfillment(of: [secondAdmission], timeout: 1)
        fixture.promoCoordinator.onVisibleLeaseAcquired = nil

        XCTAssertTrue(fixture.promoCoordinator.retryTarget === cachedTarget)
        XCTAssertTrue(cachedTarget?.isActiveForPromoRetry == true)
        XCTAssertEqual(fixture.promoCoordinator.arbiter.snapshot.visiblePromoIdentity, firstOwner)

        let secondRelease = expectation(description: "Hidden tray released the favorites RMF slot")
        fixture.promoCoordinator.onVisibleLeaseReleased = {
            secondRelease.fulfill()
        }
        sut.didHide(animated: false)
        await fulfillment(of: [secondRelease], timeout: 1)
        fixture.promoCoordinator.onVisibleLeaseReleased = nil

        XCTAssertFalse(cachedTarget?.isActiveForPromoRetry == true)
        XCTAssertNil(fixture.promoCoordinator.retryTarget)
        XCTAssertNil(fixture.promoCoordinator.arbiter.snapshot.activeOwner)
        XCTAssertEqual(fixture.promoCoordinator.successfulAdmissionCount, 2)
        XCTAssertEqual(fixture.promoCoordinator.releaseCount, 2)
    }

    func testStaleAnimatedFavoritesInstallationCannotRemoveCurrentAutocomplete() async throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "The tray caches its NTP below autocomplete only on iPhone"
        )
        let fixture = PromoHostFixture()
        let favoritesInstallationFinished = expectation(description: "Animated favorites installation completed")
        var installedFavoritesController: NewTabPageViewController?
        let sut = fixture.makeSuggestionTrayController { controller in
            if let controller = controller as? NewTabPageViewController {
                installedFavoritesController = controller
                favoritesInstallationFinished.fulfill()
            }
        }
        let window = makeVisibleWindow(rootViewController: sut)
        defer {
            detachAndHide(window)
            fixture.tearDownSuggestionDependencies()
        }

        sut.show(for: .autocomplete(query: "first query"), animated: false)
        XCTAssertTrue(sut.isShowingAutocompleteSuggestions)

        sut.show(for: .favorites, animated: true)
        sut.show(for: .autocomplete(query: "current query"), animated: false)

        await fulfillment(of: [favoritesInstallationFinished], timeout: 1)

        let autocompleteController = try XCTUnwrap(
            sut.children.compactMap { $0 as? AutocompleteViewController }.first
        )
        let favoritesController = try XCTUnwrap(installedFavoritesController)
        let contentContainer = try XCTUnwrap(autocompleteController.view.superview)

        XCTAssertTrue(sut.isShowingAutocompleteSuggestions)
        XCTAssertTrue(sut.isShowingFavorites)
        XCTAssertTrue(favoritesController.view.superview === contentContainer)
        XCTAssertTrue(contentContainer.subviews.last === autocompleteController.view)
        XCTAssertFalse(autocompleteController.view.isHidden)
        XCTAssertEqual(autocompleteController.view.alpha, 1, accuracy: 0.001)
        XCTAssertFalse(fixture.promoCoordinator.retryTarget?.isActiveForPromoRetry == true)
        XCTAssertNil(fixture.promoCoordinator.arbiter.snapshot.activeOwner)
    }
}

@MainActor
private final class PromoHostFixture {
    let appSettings = AppSettingsMock()
    let featureFlagger = MockFeatureFlagger()
    let aiChatSettings = MockAIChatSettingsProvider()
    let featureDiscovery = MockFeatureDiscovery()
    let favoritesModel = MockFavoritesListInteracting()
    let messagesConfiguration = HomePageMessagesConfigurationMock(
        homeMessages: [
            .remoteMessage(
                remoteMessage: RemoteMessageModel(
                    id: "host-wiring-rmf",
                    surfaces: .newTabPage,
                    content: .small(titleText: "Title", descriptionText: "Body"),
                    matchingRules: [],
                    exclusionRules: [],
                    isMetricsEnabled: true
                )
            )
        ]
    )
    let promoCoordinator = ArbitratingPromoHostCoordinator()
    let tabsModel = TabsModel(desktop: false)
    lazy var bookmarksDatabase = CoreDataDatabase.bookmarksMock

    lazy var newTabPageDependencies = SuggestionTrayViewController.NewTabPageDependencies(
        favoritesModel: favoritesModel,
        homePageMessagesConfiguration: messagesConfiguration,
        subscriptionDataReporting: nil,
        newTabDialogFactory: NoopNewTabDaxDialogProvider(),
        newTabDaxDialogManager: MockDaxDialogsManager(),
        onboardingFlowProvider: NoopOnboardingFlowProvider(),
        faviconLoader: EmptyFaviconLoading(),
        faviconsCache: NoopFavoritesFaviconCache(),
        remoteMessagingActionHandler: MockRemoteMessagingActionHandler(),
        remoteMessagingImageLoader: MockRemoteMessagingImageLoader(),
        remoteMessagingPixelReporter: nil,
        promoCoordinator: promoCoordinator,
        appSettings: appSettings,
        subscriptionManager: SubscriptionManagerMock(),
        internalUserCommands: NoopURLBasedDebugCommands()
    )

    lazy var suggestionTrayDependencies = SuggestionTrayDependencies(
        favoritesViewModel: favoritesModel,
        bookmarksDatabase: bookmarksDatabase,
        historyManager: MockHistoryManager(),
        tabsModelProvider: { [tabsModel] in tabsModel },
        featureFlagger: featureFlagger,
        appSettings: appSettings,
        aiChatSettings: aiChatSettings,
        featureDiscovery: featureDiscovery,
        newTabPageDependencies: newTabPageDependencies,
        productSurfaceTelemetry: MockProductSurfaceTelemetry()
    )

    func makeNewTabPageController(isFocussedState: Bool) -> NewTabPageViewController {
        let dependencies = newTabPageDependencies
        return NewTabPageViewController(
            isFocussedState: isFocussedState,
            dismissKeyboardOnScroll: false,
            tab: DuckDuckGo.Tab(),
            interactionModel: dependencies.favoritesModel,
            homePageMessagesConfiguration: dependencies.homePageMessagesConfiguration,
            subscriptionDataReporting: dependencies.subscriptionDataReporting,
            newTabDialogFactory: dependencies.newTabDialogFactory,
            daxDialogsManager: dependencies.newTabDaxDialogManager,
            onboardingFlowProvider: dependencies.onboardingFlowProvider,
            faviconLoader: dependencies.faviconLoader,
            remoteMessagingActionHandler: dependencies.remoteMessagingActionHandler,
            remoteMessagingImageLoader: dependencies.remoteMessagingImageLoader,
            remoteMessagingPixelReporter: dependencies.remoteMessagingPixelReporter,
            promoCoordinator: dependencies.promoCoordinator,
            appSettings: dependencies.appSettings,
            faviconsCache: dependencies.faviconsCache,
            subscriptionManager: dependencies.subscriptionManager,
            internalUserCommands: dependencies.internalUserCommands
        )
    }

    func makeSuggestionTrayController(
        controllerInstallationDidComplete: @escaping (UIViewController) -> Void = { _ in }) -> SuggestionTrayViewController {
        let dependencies = suggestionTrayDependencies
        return SuggestionTrayViewController(
            favoritesViewModel: dependencies.favoritesViewModel,
            bookmarksDatabase: dependencies.bookmarksDatabase,
            historyManager: dependencies.historyManager,
            tabsModelProvider: dependencies.tabsModelProvider,
            featureFlagger: dependencies.featureFlagger,
            appSettings: dependencies.appSettings,
            aiChatSettings: dependencies.aiChatSettings,
            featureDiscovery: dependencies.featureDiscovery,
            newTabPageDependencies: dependencies.newTabPageDependencies,
            productSurfaceTelemetry: dependencies.productSurfaceTelemetry,
            hideBorder: true,
            controllerInstallationDidComplete: controllerInstallationDidComplete
        )
    }

    func tearDownSuggestionDependencies() {
        try? bookmarksDatabase.tearDown(deleteStores: true)
    }
}

@MainActor
private final class ArbitratingPromoHostCoordinator: NewTabPagePromoCoordinating {
    let arbiter = PromoQueueLeaseArbiter()
    let promoCoordinationMode = PromoCoordinationMode.coordinated

    private(set) weak var retryTarget: NewTabPagePromoRetrying?
    private(set) var admissionAttemptCount = 0
    private(set) var successfulAdmissionCount = 0
    private(set) var releaseCount = 0
    var onRetryTargetRegistered: ((NewTabPagePromoRetrying) -> Void)?
    var onVisibleLeaseAcquired: ((VisiblePromoIdentity) -> Void)?
    var onVisibleLeaseReleased: (() -> Void)?

    private var retryRegistrationID: UUID?

    func admitRemoteMessage(_ identity: VisiblePromoIdentity) -> PromoQueueRemoteMessageAdmissionResult {
        admissionAttemptCount += 1

        switch arbiter.acquireVisiblePromoLease(for: identity) {
        case .acquired(let lease):
            successfulAdmissionCount += 1
            onVisibleLeaseAcquired?(identity)
            return .acquired(PromoQueueRemoteMessageAdmission { [weak self, lease] in
                guard lease.release() else {
                    return
                }
                self?.releaseCount += 1
                self?.onVisibleLeaseReleased?()
            })
        case .blockedByModal, .blockedByVisiblePromo:
            return .deferred
        }
    }

    func registerRemoteMessageRetry(
        for surfaceID: UUID,
        target: NewTabPagePromoRetrying
    ) -> NewTabPagePromoRetryRegistration {
        let registrationID = UUID()
        retryRegistrationID = registrationID
        retryTarget = target
        onRetryTargetRegistered?(target)
        return NewTabPagePromoRetryRegistration { [weak self, weak target] in
            guard let self,
                  retryRegistrationID == registrationID,
                  retryTarget === target else {
                return
            }
            retryRegistrationID = nil
            retryTarget = nil
        }
    }
}

private final class NoopNewTabDaxDialogProvider: NewTabDaxDialogProviding {
    func createDaxDialog(
        for homeDialog: DaxDialogs.HomeScreenSpec,
        onCompletion: @escaping (_ activateSearch: Bool) -> Void,
        onManualDismiss: @escaping () -> Void
    ) -> some View {
        EmptyView()
    }

    func createDuckAIFireOnboardingCompletionDialog(
        message: String,
        onDismiss: @escaping () -> Void
    ) -> AnyView {
        AnyView(EmptyView())
    }

    func createEndOfJourneyDialog(
        content: OnboardingEndOfJourneyContent,
        onAction: @escaping (OnboardingEndOfJourneyAction) -> Void
    ) -> AnyView {
        AnyView(EmptyView())
    }
}

private final class NoopOnboardingFlowProvider: OnboardingFlowProviding {
    let currentOnboardingFlow: OnboardingFlowType = .default
}

private final class NoopURLBasedDebugCommands: URLBasedDebugCommands {
    func handle(url: URL) -> Bool {
        false
    }
}

private final class NoopFavoritesFaviconCache: FavoritesFaviconCaching {
    func populateFavicon(
        for domain: String,
        intoCache: FaviconsCacheType,
        fromCache: FaviconsCacheType?
    ) {
    }
}

@MainActor
private func makeVisibleWindow(rootViewController: UIViewController) -> UIWindow {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = rootViewController
    window.isHidden = false
    rootViewController.view.layoutIfNeeded()
    return window
}

@MainActor
private func detachAndHide(_ window: UIWindow) {
    window.rootViewController = UIViewController()
    window.isHidden = true
}

@MainActor
private func nextMainQueueTurn() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async {
            continuation.resume()
        }
    }
}

private final class MockUnifiedInputContentContainerDelegate: UnifiedInputContentContainerViewControllerDelegate {
    private(set) var syncSetupRequestCount = 0

    func unifiedInputEditingStateDidSubmitQuery(_ query: String) {}
    func unifiedInputEditingStateDidSubmitPrompt(_ query: String, tools: [AIChatRAGTool]?) {}
    func unifiedInputEditingStateDidSelectFavorite(_ favorite: BookmarkEntity) {}
    func unifiedInputEditingStateDidEditFavorite(_ favorite: BookmarkEntity) {}
    func unifiedInputEditingStateDidSelectSuggestion(_ suggestion: Suggestion) {}
    func unifiedInputEditingStateDidRequestTextUpdate(_ text: String) {}
    func unifiedInputEditingStateDidSelectChatHistory(url: URL) {}
    func unifiedInputEditingStateDidSelectViewAllChats() {}
    func unifiedInputEditingStateDidRequestSwitchTab(_ tab: DuckDuckGo.Tab) {}
    func unifiedInputEditingStateDidRequestTabSwitcher() {}
    func unifiedInputEditingStateDidChangeMode(_ mode: TextEntryMode) {}

    func unifiedInputEditingStateDidRequestSyncSetup() {
        syncSetupRequestCount += 1
    }
}

private final class MockUnifiedInputSwitchBarHandler: SwitchBarHandling {
    private let currentTextSubject = CurrentValueSubject<String, Never>("")
    private let toggleStateSubject = CurrentValueSubject<TextEntryMode, Never>(.search)
    private let hasUserInteractedWithTextSubject = CurrentValueSubject<Bool, Never>(false)

    var currentText: String = ""
    var currentToggleState: TextEntryMode = .search
    var isVoiceSearchEnabled = false
    var isAIVoiceChatEnabled = false
    var hasUserInteractedWithText = false
    var isCurrentTextValidURL = false
    var buttonState: SwitchBarButtonState = .noButtons
    var isTopBarPosition = true
    var isToggleEnabled = true
    var isFireTab = false
    var isUsingExpandedBottomBarHeight = false
    var isUsingFadeOutAnimation = false
    var shouldDisableAutocorrectOnEmpty = false
    var hidesVoiceButton = false
    var hasSubmittedPrompt = false
    var modeParameters: [String: String] = [:]

    var hasSubmittedPromptPublisher: AnyPublisher<Bool, Never> { Just(false).eraseToAnyPublisher() }
    var currentTextPublisher: AnyPublisher<String, Never> { currentTextSubject.eraseToAnyPublisher() }
    var toggleStatePublisher: AnyPublisher<TextEntryMode, Never> { toggleStateSubject.eraseToAnyPublisher() }
    var textSubmissionPublisher: AnyPublisher<(text: String, mode: TextEntryMode), Never> { Empty().eraseToAnyPublisher() }
    var microphoneButtonTappedPublisher: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }
    var clearButtonTappedPublisher: AnyPublisher<Void, Never> { Empty().eraseToAnyPublisher() }
    var hasUserInteractedWithTextPublisher: AnyPublisher<Bool, Never> { hasUserInteractedWithTextSubject.eraseToAnyPublisher() }
    var isCurrentTextValidURLPublisher: AnyPublisher<Bool, Never> { Empty().eraseToAnyPublisher() }
    var currentButtonStatePublisher: AnyPublisher<SwitchBarButtonState, Never> { Empty().eraseToAnyPublisher() }

    func updateCurrentText(_ text: String) {
        currentText = text
        currentTextSubject.send(text)
    }
    func submitText(_ text: String) {}
    func setToggleState(_ state: TextEntryMode) {
        currentToggleState = state
        toggleStateSubject.send(state)
    }
    func clearText() {
        updateCurrentText("")
    }
    func microphoneButtonTapped() {}
    func markUserInteraction() {
        hasUserInteractedWithText = true
        hasUserInteractedWithTextSubject.send(true)
    }
    func clearButtonTapped() {}
    func updateBarPosition(isTop: Bool) {}
}
