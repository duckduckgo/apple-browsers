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

    func testUnifiedFavoritesUsesCurrentContentForPromoEligibility() async {
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
        let firstSessionStarted = expectation(description: "Unified favorites renderer started its session")
        fixture.promoCoordinator.onSessionStarted = { _ in
            firstSessionStarted.fulfill()
        }
        let window = makeVisibleWindow(rootViewController: sut)
        defer {
            detachAndHide(window)
            fixture.tearDownSuggestionDependencies()
        }

        sut.setActive(true)
        await fulfillment(of: [firstSessionStarted], timeout: 3)
        fixture.promoCoordinator.onSessionStarted = nil

        XCTAssertTrue(fixture.promoCoordinator.registeredRendererIsEligible)
        XCTAssertEqual(fixture.promoCoordinator.successfulSessionCount, 1)

        let firstRelease = expectation(description: "Inactive unified input ended the favorites session")
        fixture.promoCoordinator.onSessionReleased = { _ in
            firstRelease.fulfill()
        }

        sut.setActive(false)
        XCTAssertFalse(fixture.promoCoordinator.registeredRendererIsEligible)
        await fulfillment(of: [firstRelease], timeout: 1)
        fixture.promoCoordinator.onSessionReleased = nil

        XCTAssertFalse(fixture.promoCoordinator.hasActiveSession)

        // Reproduce the activation race in one main-actor turn. The content model resolves the query
        // synchronously, while its UI notification is deliberately delivered on the next main turn.
        // Eligibility must use that current model state rather than the prior favorites notification.
        sut.setText("query")
        let successfulSessionCount = fixture.promoCoordinator.successfulSessionCount

        sut.setActive(true)

        XCTAssertFalse(fixture.promoCoordinator.registeredRendererIsEligible)
        XCTAssertFalse(fixture.promoCoordinator.hasActiveSession)
        XCTAssertEqual(fixture.promoCoordinator.successfulSessionCount, successfulSessionCount)

        await nextMainQueueTurn()

        XCTAssertFalse(fixture.promoCoordinator.registeredRendererIsEligible)
        XCTAssertFalse(fixture.promoCoordinator.hasActiveSession)
        XCTAssertEqual(fixture.promoCoordinator.successfulSessionCount, successfulSessionCount)
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

    func testPromoSurfaceHandoffDeactivatesOutgoingSurfaceBeforeActivatingIncomingSurface() {
        var hostedSurfaceEvents = [String]()

        NewTabPagePromoSurfaceHandoff.showHostedSurface(
            deactivateNewTabPage: {
                hostedSurfaceEvents.append("deactivate-standard-ntp")
            },
            showHostedSurface: {
                hostedSurfaceEvents.append("show-suggestion-or-unified-host")
            }
        )

        var newTabPageEvents = [String]()

        NewTabPagePromoSurfaceHandoff.showNewTabPage(
            hideHostedSurface: {
                newTabPageEvents.append("hide-suggestion-or-unified-host")
            },
            activateNewTabPage: {
                newTabPageEvents.append("activate-standard-ntp")
            }
        )

        XCTAssertEqual(hostedSurfaceEvents, ["deactivate-standard-ntp", "show-suggestion-or-unified-host"])
        XCTAssertEqual(newTabPageEvents, ["hide-suggestion-or-unified-host", "activate-standard-ntp"])
    }

    func testWindowAttachedStandardNewTabPageIsEligibleOnlyWhileOwnerIsActive() async {
        let fixture = PromoHostFixture()
        let sut = fixture.makeNewTabPageController(isFocussedState: false)
        let window = makeVisibleWindow(rootViewController: sut)
        defer { detachAndHide(window) }
        await nextMainQueueTurn()

        let renderer = fixture.promoCoordinator.registeredRenderer
        XCTAssertNotNil(renderer)
        XCTAssertFalse(fixture.promoCoordinator.registeredRendererIsEligible)
        XCTAssertFalse(fixture.promoCoordinator.hasActiveSession)

        let firstSessionStarted = expectation(description: "Standard NTP started a logical RMF session")
        fixture.promoCoordinator.onSessionStarted = { _ in
            firstSessionStarted.fulfill()
        }
        sut.setPromoSurfaceActive(true)
        await fulfillment(of: [firstSessionStarted], timeout: 1)
        fixture.promoCoordinator.onSessionStarted = nil

        XCTAssertTrue(fixture.promoCoordinator.registeredRendererIsEligible)
        XCTAssertTrue(fixture.promoCoordinator.hasActiveSession)

        let firstRelease = expectation(description: "Inactive standard NTP completed RMF removal")
        fixture.promoCoordinator.onSessionReleased = { _ in
            firstRelease.fulfill()
        }
        sut.setPromoSurfaceActive(false)

        XCTAssertFalse(fixture.promoCoordinator.registeredRendererIsEligible)
        XCTAssertTrue(fixture.promoCoordinator.hasActiveSession)
        await fulfillment(of: [firstRelease], timeout: 1)
        fixture.promoCoordinator.onSessionReleased = nil
        XCTAssertFalse(fixture.promoCoordinator.hasActiveSession)

        let secondSessionStarted = expectation(description: "Reactivated standard NTP started a fresh RMF session")
        fixture.promoCoordinator.onSessionStarted = { _ in
            secondSessionStarted.fulfill()
        }
        sut.setPromoSurfaceActive(true)
        await fulfillment(of: [secondSessionStarted], timeout: 1)
        fixture.promoCoordinator.onSessionStarted = nil
        XCTAssertTrue(fixture.promoCoordinator.hasActiveSession)

        let secondRelease = expectation(description: "Detached standard NTP completed RMF removal")
        fixture.promoCoordinator.onSessionReleased = { _ in
            secondRelease.fulfill()
        }
        window.rootViewController = UIViewController()
        await fulfillment(of: [secondRelease], timeout: 1)
        fixture.promoCoordinator.onSessionReleased = nil

        XCTAssertFalse(fixture.promoCoordinator.hasActiveSession)
        XCTAssertEqual(fixture.promoCoordinator.successfulSessionCount, 2)
    }

    func testStaleVisibilityCompletionCannotReactivateNewerHiddenStandardNewTabPage() async {
        let fixture = PromoHostFixture()
        let sut = fixture.makeNewTabPageController(isFocussedState: false)
        let window = makeVisibleWindow(rootViewController: sut)
        defer { detachAndHide(window) }
        await nextMainQueueTurn()

        let firstSessionStarted = expectation(description: "Standard NTP started a logical RMF session")
        fixture.promoCoordinator.onSessionStarted = { _ in
            firstSessionStarted.fulfill()
        }
        sut.setPromoSurfaceActive(true)
        await fulfillment(of: [firstSessionStarted], timeout: 1)
        fixture.promoCoordinator.onSessionStarted = nil

        let release = expectation(description: "Explicitly hidden standard NTP completed RMF removal")
        fixture.promoCoordinator.onSessionReleased = { _ in
            release.fulfill()
        }
        let staleGeneration = sut.setPromoSurfaceVisible(false)
        let currentGeneration = sut.setPromoSurfaceVisible(false)
        await fulfillment(of: [release], timeout: 1)
        fixture.promoCoordinator.onSessionReleased = nil

        let successfulSessionCountBeforeStaleCompletion = fixture.promoCoordinator.successfulSessionCount
        sut.restorePromoSurfaceVisibility(ifCurrent: staleGeneration)

        XCTAssertFalse(fixture.promoCoordinator.registeredRendererIsEligible)
        XCTAssertEqual(fixture.promoCoordinator.successfulSessionCount, successfulSessionCountBeforeStaleCompletion)

        let secondSessionStarted = expectation(description: "Current completion restored standard NTP visibility")
        fixture.promoCoordinator.onSessionStarted = { _ in
            secondSessionStarted.fulfill()
        }
        sut.restorePromoSurfaceVisibility(ifCurrent: currentGeneration)
        await fulfillment(of: [secondSessionStarted], timeout: 1)

        XCTAssertTrue(fixture.promoCoordinator.registeredRendererIsEligible)
    }

    func testAutocompleteDeactivatesCachedTrayNewTabPageAndDidHideDeregistersIt() async throws {
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

        let firstSessionStarted = expectation(description: "Tray favorites started a logical RMF session")
        fixture.promoCoordinator.onSessionStarted = { _ in
            firstSessionStarted.fulfill()
        }
        sut.show(for: .favorites, animated: false)
        sut.view.layoutIfNeeded()
        await fulfillment(of: [firstSessionStarted], timeout: 1)
        fixture.promoCoordinator.onSessionStarted = nil

        let cachedRenderer = fixture.promoCoordinator.registeredRenderer
        XCTAssertNotNil(cachedRenderer)
        XCTAssertTrue(fixture.promoCoordinator.registeredRendererIsEligible)
        XCTAssertTrue(fixture.promoCoordinator.hasActiveSession)

        let firstRelease = expectation(description: "Tray autocomplete completed cached favorites RMF removal")
        fixture.promoCoordinator.onSessionReleased = { _ in
            firstRelease.fulfill()
        }
        sut.show(for: .autocomplete(query: "https://example.com/"), animated: false)

        XCTAssertTrue(sut.isShowingFavorites)
        XCTAssertTrue(fixture.promoCoordinator.registeredRenderer === cachedRenderer)
        XCTAssertFalse(fixture.promoCoordinator.registeredRendererIsEligible)
        XCTAssertTrue(fixture.promoCoordinator.hasActiveSession)
        await fulfillment(of: [firstRelease], timeout: 1)
        fixture.promoCoordinator.onSessionReleased = nil
        XCTAssertFalse(fixture.promoCoordinator.hasActiveSession)

        sut.didHide(animated: false)

        XCTAssertFalse(fixture.promoCoordinator.registeredRendererIsEligible)
        XCTAssertNil(fixture.promoCoordinator.registeredRenderer)
        XCTAssertFalse(fixture.promoCoordinator.hasActiveSession)
    }

    func testDeactivatingTrayKeepsCachedNewTabPageInactive() async {
        let fixture = PromoHostFixture()
        let sut = fixture.makeSuggestionTrayController()
        let window = makeVisibleWindow(rootViewController: sut)
        defer {
            detachAndHide(window)
            fixture.tearDownSuggestionDependencies()
        }

        let firstSessionStarted = expectation(description: "Tray favorites started a logical RMF session")
        fixture.promoCoordinator.onSessionStarted = { _ in
            firstSessionStarted.fulfill()
        }
        sut.show(for: .favorites, animated: false)
        await fulfillment(of: [firstSessionStarted], timeout: 1)
        fixture.promoCoordinator.onSessionStarted = nil

        let cachedRenderer = fixture.promoCoordinator.registeredRenderer
        XCTAssertNotNil(cachedRenderer)
        XCTAssertTrue(fixture.promoCoordinator.registeredRendererIsEligible)
        XCTAssertTrue(fixture.promoCoordinator.hasActiveSession)

        let firstRelease = expectation(description: "Hidden tray completed favorites RMF removal")
        fixture.promoCoordinator.onSessionReleased = { _ in
            firstRelease.fulfill()
        }
        sut.deactivatePromoSurfaceExposure()
        await fulfillment(of: [firstRelease], timeout: 1)
        fixture.promoCoordinator.onSessionReleased = nil

        XCTAssertTrue(sut.isShowingFavorites, "Hiding the tray must preserve its cached favorites content")
        XCTAssertTrue(fixture.promoCoordinator.registeredRenderer === cachedRenderer)
        XCTAssertFalse(fixture.promoCoordinator.registeredRendererIsEligible)
        XCTAssertFalse(fixture.promoCoordinator.hasActiveSession)
    }

    func testDeactivatingTrayInvalidatesPendingFavoritesActivation() async {
        let fixture = PromoHostFixture()
        let favoritesInstallationFinished = expectation(
            description: "Animated tray favorites installation completed"
        )
        let sut = fixture.makeSuggestionTrayController { controller in
            if controller is NewTabPageViewController {
                favoritesInstallationFinished.fulfill()
            }
        }
        let window = makeVisibleWindow(rootViewController: sut)
        defer {
            detachAndHide(window)
            fixture.tearDownSuggestionDependencies()
        }

        sut.show(for: .favorites, animated: true)
        sut.deactivatePromoSurfaceExposure()

        await fulfillment(of: [favoritesInstallationFinished], timeout: 1)
        await nextMainQueueTurn()

        XCTAssertTrue(sut.isShowingFavorites, "Hiding during installation must keep the favorites cache")
        XCTAssertFalse(fixture.promoCoordinator.registeredRendererIsEligible)
        XCTAssertFalse(fixture.promoCoordinator.hasActiveSession)
        XCTAssertEqual(fixture.promoCoordinator.successfulSessionCount, 0)
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
        XCTAssertFalse(fixture.promoCoordinator.registeredRendererIsEligible)
        XCTAssertFalse(fixture.promoCoordinator.hasActiveSession)
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
    let promoCoordinator = PromoHostCoordinatorSpy()
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
private final class PromoHostCoordinatorSpy: NewTabPagePromoCoordinating {
    private struct SessionState {
        let session: PromoQueueRemoteMessageSession
        let presentation: PromoQueueRemoteMessagePresentation
    }

    private struct RemovalState {
        let registrationID: UUID
        let sessionID: UUID
        let presentationID: UUID
        let removalID: UUID
        var terminalWasReported = false
    }

    let promoCoordinationMode = PromoCoordinationMode.coordinated

    private(set) var successfulSessionCount = 0
    var onSessionStarted: ((PromoQueueRemoteMessageSession) -> Void)?
    var onSessionReleased: ((PromoQueueRemoteMessageSession) -> Void)?

    var registeredRenderer: NewTabPagePromoRendering? {
        isRendererRegistered ? rendererTarget : nil
    }

    var registeredRendererIsEligible: Bool {
        isRendererRegistered && isRendererEligible
    }

    var hasActiveSession: Bool {
        sessionState != nil
    }

    private weak var rendererTarget: NewTabPagePromoRendering?
    private var registrationID: UUID?
    private var rendererCandidate = PromoQueueRemoteMessageCandidateState.none
    private var isRendererEligible = false
    private var isRendererRegistered = false
    private var sessionState: SessionState?
    private var removalState: RemovalState?

    func registerRemoteMessageRenderer(
        id _: UUID,
        target: NewTabPagePromoRendering
    ) -> NewTabPagePromoRendererRegistration {
        let registrationID = UUID()
        self.registrationID = registrationID
        rendererTarget = target
        rendererCandidate = .none
        isRendererEligible = false
        isRendererRegistered = true

        return NewTabPagePromoRendererRegistration(
            updateHandler: { [weak self] candidate, isEligible in
                self?.updateRenderer(
                    registrationID: registrationID,
                    candidate: candidate,
                    isEligible: isEligible
                )
            },
            appearanceHandler: { [weak self] sessionID, presentationID, isAttachedToWindow in
                self?.confirmAppearance(
                    registrationID: registrationID,
                    sessionID: sessionID,
                    presentationID: presentationID,
                    isAttachedToWindow: isAttachedToWindow
                ) ?? .rejected
            },
            removalTerminalHandler: { [weak self] sessionID, presentationID, removalID, terminal in
                self?.reportRemovalTerminal(
                    registrationID: registrationID,
                    sessionID: sessionID,
                    presentationID: presentationID,
                    removalID: removalID,
                    terminal: terminal
                )
            },
            deregistrationHandler: { [weak self] in
                self?.deregisterRenderer(registrationID: registrationID)
            }
        )
    }

    private func updateRenderer(
        registrationID: UUID,
        candidate: PromoQueueRemoteMessageCandidateState,
        isEligible: Bool
    ) {
        guard self.registrationID == registrationID,
              isRendererRegistered else {
            return
        }

        rendererCandidate = candidate
        isRendererEligible = isEligible
        reconcile()
    }

    private func confirmAppearance(
        registrationID: UUID,
        sessionID: UUID,
        presentationID: UUID,
        isAttachedToWindow: Bool
    ) -> PromoQueueRemoteMessageAppearanceResult {
        guard self.registrationID == registrationID,
              isRendererRegistered,
              isRendererEligible,
              isAttachedToWindow,
              rendererTarget?.isRemoteMessageRendererAttachedToWindow == true,
              removalState == nil,
              let sessionState,
              sessionState.session.id == sessionID,
              sessionState.presentation.id == presentationID,
              candidateMessageID == sessionState.session.messageID else {
            return .rejected
        }

        return .accepted
    }

    private func reportRemovalTerminal(
        registrationID: UUID,
        sessionID: UUID,
        presentationID: UUID,
        removalID: UUID,
        terminal: PromoQueueRemoteMessageRemovalTerminal
    ) {
        guard self.registrationID == registrationID,
              var removalState,
              !removalState.terminalWasReported,
              removalState.registrationID == registrationID,
              removalState.sessionID == sessionID,
              removalState.presentationID == presentationID,
              removalState.removalID == removalID else {
            return
        }

        if terminal == .hostDetached {
            guard rendererTarget?.isRemoteMessageRendererAttachedToWindow == false else {
                return
            }
        }

        removalState.terminalWasReported = true
        self.removalState = removalState
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.completeRemoval(
                    registrationID: registrationID,
                    sessionID: sessionID,
                    presentationID: presentationID,
                    removalID: removalID
                )
            }
        }
    }

    private func deregisterRenderer(registrationID: UUID) {
        guard self.registrationID == registrationID,
              isRendererRegistered else {
            return
        }

        isRendererRegistered = false
        isRendererEligible = false
        reconcile()
        clearRendererIfUnused()
    }

    private func reconcile() {
        if let sessionState {
            guard removalState == nil,
                  !shouldKeepShowing(sessionState) else {
                return
            }
            beginRemoval(of: sessionState)
            return
        }

        guard isRendererRegistered,
              isRendererEligible,
              let messageID = candidateMessageID,
              let rendererTarget else {
            return
        }

        startSession(messageID: messageID, renderer: rendererTarget)
    }

    private func startSession(messageID: String, renderer: NewTabPagePromoRendering) {
        let session = PromoQueueRemoteMessageSession(id: UUID(), messageID: messageID)
        let presentation = PromoQueueRemoteMessagePresentation(id: UUID(), session: session)
        sessionState = SessionState(session: session, presentation: presentation)
        guard renderer.showRemoteMessage(presentation) else {
            sessionState = nil
            return
        }
        successfulSessionCount += 1
        onSessionStarted?(session)
    }

    private func shouldKeepShowing(_ sessionState: SessionState) -> Bool {
        isRendererRegistered &&
            isRendererEligible &&
            rendererTarget != nil &&
            candidateMessageID == sessionState.session.messageID
    }

    private func beginRemoval(of sessionState: SessionState) {
        guard let registrationID,
              let rendererTarget else {
            return
        }

        let removalID = UUID()
        removalState = RemovalState(
            registrationID: registrationID,
            sessionID: sessionState.session.id,
            presentationID: sessionState.presentation.id,
            removalID: removalID
        )
        rendererTarget.hideRemoteMessage(
            sessionState.presentation,
            removalID: removalID
        )
    }

    private func completeRemoval(
        registrationID: UUID,
        sessionID: UUID,
        presentationID: UUID,
        removalID: UUID
    ) {
        guard self.registrationID == registrationID,
              let removalState,
              removalState.terminalWasReported,
              removalState.registrationID == registrationID,
              removalState.sessionID == sessionID,
              removalState.presentationID == presentationID,
              removalState.removalID == removalID,
              let sessionState,
              sessionState.session.id == sessionID,
              sessionState.presentation.id == presentationID else {
            return
        }

        self.removalState = nil
        self.sessionState = nil
        onSessionReleased?(sessionState.session)
        clearRendererIfUnused()
        reconcile()
    }

    private var candidateMessageID: String? {
        guard case .available(let messageID) = rendererCandidate else {
            return nil
        }
        return messageID
    }

    private func clearRendererIfUnused() {
        guard !isRendererRegistered,
              sessionState == nil else {
            return
        }

        rendererTarget = nil
        registrationID = nil
        rendererCandidate = .none
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
