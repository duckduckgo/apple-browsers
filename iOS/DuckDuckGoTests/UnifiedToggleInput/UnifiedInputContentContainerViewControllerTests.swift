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

    func testActiveUnifiedFavoritesKeepsCachedNewTabPageEligibleOnlyWhileFavoritesAreExposed() async {
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
        fixture.resolvePromoExposure(from: sut)
        let rendererRegistered = expectation(description: "Unified favorites NTP registered as a renderer")
        fixture.promoCoordinator.onRendererRegistered = { _ in
            rendererRegistered.fulfill()
        }
        let firstSessionStarted = expectation(description: "Unified favorites renderer started a logical session")
        fixture.promoCoordinator.onSessionStarted = { _ in
            firstSessionStarted.fulfill()
        }
        let window = makeVisibleWindow(rootViewController: sut)
        defer {
            detachAndHide(window)
            fixture.tearDownSuggestionDependencies()
        }

        sut.setActive(true)
        await fulfillment(of: [rendererRegistered, firstSessionStarted], timeout: 3)
        fixture.promoCoordinator.onSessionStarted = nil

        let cachedRenderer = fixture.promoCoordinator.registeredRenderer
        let cachedRendererID = fixture.promoCoordinator.registeredRendererID
        let firstSession = fixture.promoCoordinator.arbiter.snapshot.remoteMessageSession
        XCTAssertNotNil(cachedRenderer)
        XCTAssertNotNil(cachedRendererID)
        XCTAssertTrue(fixture.promoCoordinator.registeredRendererIsEligible)
        XCTAssertNotNil(firstSession)

        let firstRelease = expectation(description: "Query removed the unified favorites card and ended its session")
        fixture.promoCoordinator.onSessionReleased = { _ in
            firstRelease.fulfill()
        }
        sut.setText("query")
        await fulfillment(of: [firstRelease], timeout: 1)
        fixture.promoCoordinator.onSessionReleased = nil

        XCTAssertTrue(fixture.promoCoordinator.registeredRenderer === cachedRenderer)
        XCTAssertEqual(fixture.promoCoordinator.registeredRendererID, cachedRendererID)
        XCTAssertFalse(fixture.promoCoordinator.registeredRendererIsEligible)
        XCTAssertNil(fixture.promoCoordinator.arbiter.snapshot.activeOwner)

        let secondSessionStarted = expectation(description: "Clearing the query started a fresh unified favorites session")
        fixture.promoCoordinator.onSessionStarted = { _ in
            secondSessionStarted.fulfill()
        }
        sut.setText("")
        await fulfillment(of: [secondSessionStarted], timeout: 1)
        fixture.promoCoordinator.onSessionStarted = nil

        let secondSession = fixture.promoCoordinator.arbiter.snapshot.remoteMessageSession
        XCTAssertTrue(fixture.promoCoordinator.registeredRenderer === cachedRenderer)
        XCTAssertTrue(fixture.promoCoordinator.registeredRendererIsEligible)
        XCTAssertNotNil(secondSession)
        XCTAssertNotEqual(secondSession?.id, firstSession?.id)

        let secondRelease = expectation(description: "Fire mode removed the unified favorites card and ended its session")
        fixture.promoCoordinator.onSessionReleased = { _ in
            secondRelease.fulfill()
        }
        sut.refreshFireMode(fireMode: true)
        await fulfillment(of: [secondRelease], timeout: 1)
        fixture.promoCoordinator.onSessionReleased = nil

        XCTAssertFalse(fixture.promoCoordinator.registeredRendererIsEligible)
        XCTAssertNil(fixture.promoCoordinator.arbiter.snapshot.activeOwner)

        let thirdSessionStarted = expectation(description: "Leaving fire mode started a fresh unified favorites session")
        fixture.promoCoordinator.onSessionStarted = { _ in
            thirdSessionStarted.fulfill()
        }
        sut.refreshFireMode(fireMode: false)
        await fulfillment(of: [thirdSessionStarted], timeout: 1)
        fixture.promoCoordinator.onSessionStarted = nil

        let thirdSession = fixture.promoCoordinator.arbiter.snapshot.remoteMessageSession
        XCTAssertTrue(fixture.promoCoordinator.registeredRendererIsEligible)
        XCTAssertNotNil(thirdSession)
        XCTAssertNotEqual(thirdSession?.id, secondSession?.id)

        let thirdRelease = expectation(description: "Inactive unified input removed the favorites card and ended its session")
        fixture.promoCoordinator.onSessionReleased = { _ in
            thirdRelease.fulfill()
        }
        sut.setActive(false)
        await fulfillment(of: [thirdRelease], timeout: 1)
        fixture.promoCoordinator.onSessionReleased = nil

        XCTAssertFalse(fixture.promoCoordinator.registeredRendererIsEligible)
        XCTAssertNil(fixture.promoCoordinator.arbiter.snapshot.activeOwner)
        XCTAssertEqual(fixture.promoCoordinator.successfulSessionCount, 3)
        XCTAssertEqual(fixture.promoCoordinator.releaseCount, 3)
    }

    func testReactivatingUnifiedInputInSameTurnAsQueryChangeDoesNotReExposeStaleFavorites() async {
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
        fixture.resolvePromoExposure(from: sut)
        let window = makeVisibleWindow(rootViewController: sut)
        defer {
            detachAndHide(window)
            fixture.tearDownSuggestionDependencies()
        }

        let initialSessionStarted = expectation(description: "Unified favorites started the initial session")
        fixture.promoCoordinator.onSessionStarted = { _ in initialSessionStarted.fulfill() }
        sut.setActive(true)
        await fulfillment(of: [initialSessionStarted], timeout: 3)
        fixture.promoCoordinator.onSessionStarted = nil

        let initialSessionReleased = expectation(description: "Deactivation ended the initial favorites session")
        fixture.promoCoordinator.onSessionReleased = { _ in initialSessionReleased.fulfill() }
        sut.setActive(false)
        await fulfillment(of: [initialSessionReleased], timeout: 1)
        fixture.promoCoordinator.onSessionReleased = nil

        // The content model resolves the query synchronously while its published notification is
        // delivered on the next main turn. Reactivation must pull the live model state rather than
        // reuse the previous favorites notification.
        sut.setText("query")
        let sessionCountBeforeReactivation = fixture.promoCoordinator.successfulSessionCount
        sut.setActive(true)

        XCTAssertNil(sut.exposedPromoRendererID)
        XCTAssertNil(fixture.promoSurfaceExposureController.snapshot.effectiveSelectedRendererID)
        XCTAssertFalse(fixture.promoCoordinator.registeredRendererIsEligible)
        XCTAssertNil(fixture.promoCoordinator.arbiter.snapshot.activeOwner)
        XCTAssertEqual(fixture.promoCoordinator.successfulSessionCount, sessionCountBeforeReactivation)

        await nextMainQueueTurn()

        XCTAssertNil(sut.exposedPromoRendererID)
        XCTAssertNil(fixture.promoSurfaceExposureController.snapshot.effectiveSelectedRendererID)
        XCTAssertFalse(fixture.promoCoordinator.registeredRendererIsEligible)
        XCTAssertNil(fixture.promoCoordinator.arbiter.snapshot.activeOwner)
        XCTAssertEqual(fixture.promoCoordinator.successfulSessionCount, sessionCountBeforeReactivation)
    }

    func testActiveUnifiedLogoAndListRemainFailClosedUntilFavoritesArePhysicallyExposed() async {
        let fixture = PromoHostFixture()
        fixture.appSettings.autocomplete = false
        let remoteMessages = fixture.messagesConfiguration.homeMessages
        fixture.messagesConfiguration.homeMessages = []
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
        fixture.resolvePromoExposure(from: sut)
        let window = makeVisibleWindow(rootViewController: sut)
        defer {
            detachAndHide(window)
            fixture.tearDownSuggestionDependencies()
        }

        sut.setActive(true)
        await nextMainQueueTurn()

        XCTAssertTrue(sut.isShowingLogoContent)
        XCTAssertNil(sut.exposedPromoRendererID)
        XCTAssertNil(fixture.promoSurfaceExposureController.snapshot.effectiveSelectedRendererID)
        XCTAssertFalse(fixture.promoCoordinator.registeredRendererIsEligible)
        XCTAssertNil(fixture.promoCoordinator.arbiter.snapshot.activeOwner)
        XCTAssertEqual(fixture.promoCoordinator.successfulSessionCount, 0)

        sut.setText("query")
        await nextMainQueueTurn()

        XCTAssertFalse(sut.isShowingLogoContent)
        XCTAssertFalse(sut.isShowingFavoritesContent)
        XCTAssertNil(sut.exposedPromoRendererID)
        XCTAssertNil(fixture.promoSurfaceExposureController.snapshot.effectiveSelectedRendererID)
        XCTAssertFalse(fixture.promoCoordinator.registeredRendererIsEligible)
        XCTAssertNil(fixture.promoCoordinator.arbiter.snapshot.activeOwner)
        XCTAssertEqual(fixture.promoCoordinator.successfulSessionCount, 0)

        let sessionStarted = expectation(description: "Physically exposed unified favorites started a session")
        fixture.promoCoordinator.onSessionStarted = { _ in
            sessionStarted.fulfill()
        }
        fixture.messagesConfiguration.homeMessages = remoteMessages
        NotificationCenter.default.post(
            name: RemoteMessagingStore.Notifications.remoteMessagesDidChange,
            object: nil
        )
        sut.setText("")
        await fulfillment(of: [sessionStarted], timeout: 3)
        fixture.promoCoordinator.onSessionStarted = nil

        let cachedRenderer = fixture.promoCoordinator.registeredRenderer
        let cachedRendererID = fixture.promoCoordinator.registeredRendererID
        XCTAssertTrue(sut.isShowingFavoritesContent)
        XCTAssertEqual(sut.exposedPromoRendererID, cachedRendererID)
        XCTAssertEqual(
            fixture.promoSurfaceExposureController.snapshot.effectiveSelectedRendererID,
            cachedRendererID
        )
        XCTAssertTrue(fixture.promoCoordinator.registeredRendererIsEligible)

        let release = expectation(description: "Returning to non-favorites content ended the unified favorites session")
        fixture.promoCoordinator.onSessionReleased = { _ in
            release.fulfill()
        }
        fixture.messagesConfiguration.homeMessages = []
        sut.setText("query")
        await fulfillment(of: [release], timeout: 1)
        fixture.promoCoordinator.onSessionReleased = nil

        XCTAssertNil(sut.exposedPromoRendererID)
        XCTAssertNil(fixture.promoSurfaceExposureController.snapshot.effectiveSelectedRendererID)
        XCTAssertFalse(fixture.promoCoordinator.registeredRendererIsEligible)

        sut.setText("")
        await nextMainQueueTurn()

        XCTAssertTrue(sut.isShowingLogoContent)
        XCTAssertNil(sut.exposedPromoRendererID)
        XCTAssertTrue(fixture.promoCoordinator.registeredRenderer === cachedRenderer)
        XCTAssertEqual(fixture.promoCoordinator.registeredRendererID, cachedRendererID)
        XCTAssertFalse(fixture.promoCoordinator.registeredRendererIsEligible)
        XCTAssertNil(fixture.promoCoordinator.arbiter.snapshot.activeOwner)
        XCTAssertEqual(fixture.promoCoordinator.successfulSessionCount, 1)
        XCTAssertEqual(fixture.promoCoordinator.releaseCount, 1)

        sut.tearDownPromoSurfaceProvider()

        XCTAssertNil(sut.exposedPromoRendererID)
        XCTAssertNil(fixture.promoCoordinator.registeredRenderer)
    }
}

@MainActor
final class NewTabPagePromoHostWiringTests: XCTestCase {

    func testWindowAttachedStandardNewTabPageIsEligibleOnlyWhileSelectedAndLifecycleReady() async {
        let fixture = PromoHostFixture()
        let sut = fixture.makeNewTabPageController(isFocussedState: false)
        fixture.promoSurfaceExposureController.setRouteCandidateRendererID(sut.promoSurfaceID)
        let window = makeVisibleWindow(rootViewController: sut)
        defer { detachAndHide(window) }
        sut.viewWillAppear(false)
        await nextMainQueueTurn()

        let renderer = fixture.promoCoordinator.registeredRenderer
        XCTAssertNotNil(renderer)
        XCTAssertTrue(fixture.promoCoordinator.registeredRendererIsEligible)
        let firstSession = fixture.promoCoordinator.arbiter.snapshot.remoteMessageSession
        XCTAssertNotNil(firstSession)

        let firstRelease = expectation(description: "Inactive standard NTP completed RMF removal")
        fixture.promoCoordinator.onSessionReleased = { _ in
            firstRelease.fulfill()
        }
        sut.viewDidDisappear(false)

        XCTAssertFalse(fixture.promoCoordinator.registeredRendererIsEligible)
        XCTAssertEqual(fixture.promoCoordinator.arbiter.snapshot.remoteMessageSession, firstSession)
        await fulfillment(of: [firstRelease], timeout: 1)
        fixture.promoCoordinator.onSessionReleased = nil
        XCTAssertNil(fixture.promoCoordinator.arbiter.snapshot.activeOwner)

        let secondSessionStarted = expectation(description: "Reactivated standard NTP started a fresh RMF session")
        fixture.promoCoordinator.onSessionStarted = { _ in
            secondSessionStarted.fulfill()
        }
        sut.viewWillAppear(false)
        await fulfillment(of: [secondSessionStarted], timeout: 1)
        fixture.promoCoordinator.onSessionStarted = nil
        let secondSession = fixture.promoCoordinator.arbiter.snapshot.remoteMessageSession
        XCTAssertNotNil(secondSession)
        XCTAssertNotEqual(secondSession?.id, firstSession?.id)

        let secondRelease = expectation(description: "Detached standard NTP completed RMF removal")
        fixture.promoCoordinator.onSessionReleased = { _ in
            secondRelease.fulfill()
        }
        window.rootViewController = UIViewController()
        await fulfillment(of: [secondRelease], timeout: 1)
        fixture.promoCoordinator.onSessionReleased = nil

        XCTAssertNil(fixture.promoCoordinator.arbiter.snapshot.activeOwner)
        XCTAssertEqual(fixture.promoCoordinator.successfulSessionCount, 2)
        XCTAssertEqual(fixture.promoCoordinator.releaseCount, 2)
    }

    func testWhenStandardNewTabPageReconnectsThenItRemainsFailClosedUntilAttachedAndSelected() async throws {
        let fixture = PromoHostFixture()
        let sut = fixture.makeNewTabPageController(isFocussedState: false)
        fixture.promoSurfaceExposureController.setRouteCandidateRendererID(sut.promoSurfaceID)
        let firstSessionStarted = expectation(description: "Attached and selected standard NTP started its first RMF session")
        fixture.promoCoordinator.onSessionStarted = { _ in
            firstSessionStarted.fulfill()
        }
        let window = makeVisibleWindow(rootViewController: sut)
        defer { detachAndHide(window) }
        sut.viewWillAppear(false)
        await fulfillment(of: [firstSessionStarted], timeout: 1)
        fixture.promoCoordinator.onSessionStarted = nil
        let renderer = try XCTUnwrap(fixture.promoCoordinator.registeredRenderer)
        let firstSessionID = try XCTUnwrap(fixture.promoCoordinator.arbiter.snapshot.remoteMessageSession?.id)

        let firstRelease = expectation(description: "Detached standard NTP completed RMF removal")
        fixture.promoCoordinator.onSessionReleased = { _ in
            firstRelease.fulfill()
        }
        window.rootViewController = UIViewController()
        await fulfillment(of: [firstRelease], timeout: 1)
        fixture.promoCoordinator.onSessionReleased = nil

        sut.viewWillAppear(false)
        await nextMainQueueTurn()

        XCTAssertEqual(
            fixture.promoSurfaceExposureController.snapshot.effectiveSelectedRendererID,
            sut.promoSurfaceID
        )
        XCTAssertFalse(renderer.isRemoteMessageRendererAttachedToWindow)
        XCTAssertFalse(fixture.promoCoordinator.registeredRendererIsEligible)
        XCTAssertNil(fixture.promoCoordinator.arbiter.snapshot.activeOwner)
        XCTAssertEqual(fixture.promoCoordinator.successfulSessionCount, 1)

        fixture.promoSurfaceExposureController.setRouteCandidateRendererID(nil)
        window.rootViewController = sut
        sut.view.layoutIfNeeded()
        sut.viewWillAppear(false)
        await nextMainQueueTurn()

        XCTAssertTrue(renderer.isRemoteMessageRendererAttachedToWindow)
        XCTAssertNil(fixture.promoSurfaceExposureController.snapshot.effectiveSelectedRendererID)
        XCTAssertFalse(fixture.promoCoordinator.registeredRendererIsEligible)
        XCTAssertNil(fixture.promoCoordinator.arbiter.snapshot.activeOwner)
        XCTAssertEqual(fixture.promoCoordinator.successfulSessionCount, 1)

        let secondSessionStarted = expectation(description: "Reattached and reselected standard NTP started a fresh RMF session")
        fixture.promoCoordinator.onSessionStarted = { _ in
            secondSessionStarted.fulfill()
        }
        fixture.promoSurfaceExposureController.setRouteCandidateRendererID(sut.promoSurfaceID)
        await fulfillment(of: [secondSessionStarted], timeout: 1)
        fixture.promoCoordinator.onSessionStarted = nil

        XCTAssertTrue(fixture.promoCoordinator.registeredRendererIsEligible)
        let secondSessionID = try XCTUnwrap(fixture.promoCoordinator.arbiter.snapshot.remoteMessageSession?.id)
        XCTAssertNotEqual(secondSessionID, firstSessionID)
        XCTAssertEqual(fixture.promoCoordinator.successfulSessionCount, 2)
        XCTAssertEqual(fixture.promoCoordinator.releaseCount, 1)
    }

    func testStaleVisibilityBlockerReleaseCannotReactivateNewerHiddenStandardNewTabPage() async {
        let fixture = PromoHostFixture()
        let sut = fixture.makeNewTabPageController(isFocussedState: false)
        fixture.promoSurfaceExposureController.setRouteCandidateRendererID(sut.promoSurfaceID)
        let firstSessionStarted = expectation(description: "Standard NTP started a logical RMF session")
        fixture.promoCoordinator.onSessionStarted = { _ in
            firstSessionStarted.fulfill()
        }
        let window = makeVisibleWindow(rootViewController: sut)
        defer { detachAndHide(window) }
        sut.viewWillAppear(false)
        await fulfillment(of: [firstSessionStarted], timeout: 1)
        fixture.promoCoordinator.onSessionStarted = nil

        let release = expectation(description: "Explicitly hidden standard NTP completed RMF removal")
        fixture.promoCoordinator.onSessionReleased = { _ in
            release.fulfill()
        }
        let staleToken = sut.blockPromoSurfaceVisibility(source: PromoSurfaceBlockerSource("stale-transition"))
        let currentToken = sut.blockPromoSurfaceVisibility(source: PromoSurfaceBlockerSource("current-transition"))
        await fulfillment(of: [release], timeout: 1)
        fixture.promoCoordinator.onSessionReleased = nil

        let sessionAttemptCountBeforeStaleCompletion = fixture.promoCoordinator.sessionAttemptCount
        staleToken.release()

        XCTAssertFalse(fixture.promoCoordinator.registeredRendererIsEligible)
        XCTAssertEqual(fixture.promoCoordinator.sessionAttemptCount, sessionAttemptCountBeforeStaleCompletion)

        let secondSessionStarted = expectation(description: "Current completion restored standard NTP visibility")
        fixture.promoCoordinator.onSessionStarted = { _ in
            secondSessionStarted.fulfill()
        }
        currentToken.release()
        await fulfillment(of: [secondSessionStarted], timeout: 1)

        XCTAssertTrue(fixture.promoCoordinator.registeredRendererIsEligible)
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

        let firstSessionStarted = expectation(description: "Tray favorites started a logical RMF session")
        fixture.promoCoordinator.onSessionStarted = { _ in
            firstSessionStarted.fulfill()
        }
        sut.show(for: .favorites, animated: false)
        sut.view.layoutIfNeeded()
        await fulfillment(of: [firstSessionStarted], timeout: 1)
        fixture.promoCoordinator.onSessionStarted = nil

        let cachedRenderer = fixture.promoCoordinator.registeredRenderer
        let cachedRendererID = fixture.promoCoordinator.registeredRendererID
        let firstSession = fixture.promoCoordinator.arbiter.snapshot.remoteMessageSession
        XCTAssertNotNil(cachedRenderer)
        XCTAssertNotNil(cachedRendererID)
        XCTAssertTrue(fixture.promoCoordinator.registeredRendererIsEligible)
        XCTAssertNotNil(firstSession)

        let firstRelease = expectation(description: "Tray autocomplete completed cached favorites RMF removal")
        fixture.promoCoordinator.onSessionReleased = { _ in
            firstRelease.fulfill()
        }
        sut.show(for: .autocomplete(query: "https://example.com/"), animated: false)

        XCTAssertTrue(sut.isShowingFavorites)
        XCTAssertTrue(fixture.promoCoordinator.registeredRenderer === cachedRenderer)
        XCTAssertEqual(fixture.promoCoordinator.registeredRendererID, cachedRendererID)
        XCTAssertFalse(fixture.promoCoordinator.registeredRendererIsEligible)
        XCTAssertEqual(fixture.promoCoordinator.arbiter.snapshot.remoteMessageSession, firstSession)
        await fulfillment(of: [firstRelease], timeout: 1)
        fixture.promoCoordinator.onSessionReleased = nil
        XCTAssertNil(fixture.promoCoordinator.arbiter.snapshot.activeOwner)

        let secondSessionStarted = expectation(description: "Returning to tray favorites started a fresh RMF session")
        fixture.promoCoordinator.onSessionStarted = { _ in
            secondSessionStarted.fulfill()
        }
        sut.show(for: .favorites, animated: false)
        sut.view.layoutIfNeeded()
        await fulfillment(of: [secondSessionStarted], timeout: 1)
        fixture.promoCoordinator.onSessionStarted = nil

        let secondSession = fixture.promoCoordinator.arbiter.snapshot.remoteMessageSession
        XCTAssertTrue(fixture.promoCoordinator.registeredRenderer === cachedRenderer)
        XCTAssertTrue(fixture.promoCoordinator.registeredRendererIsEligible)
        XCTAssertNotNil(secondSession)
        XCTAssertNotEqual(secondSession?.id, firstSession?.id)

        let secondRelease = expectation(description: "Hidden tray completed favorites RMF removal")
        fixture.promoCoordinator.onSessionReleased = { _ in
            secondRelease.fulfill()
        }
        sut.didHide(animated: false)
        await fulfillment(of: [secondRelease], timeout: 1)
        fixture.promoCoordinator.onSessionReleased = nil

        XCTAssertFalse(fixture.promoCoordinator.registeredRendererIsEligible)
        XCTAssertNil(fixture.promoCoordinator.registeredRenderer)
        XCTAssertNil(fixture.promoCoordinator.arbiter.snapshot.activeOwner)
        XCTAssertEqual(fixture.promoCoordinator.successfulSessionCount, 2)
        XCTAssertEqual(fixture.promoCoordinator.releaseCount, 2)
    }

    func testDuckAISuggestionsClearTrayExposureBeforeFavoritesRemovalSettles() async {
        let fixture = PromoHostFixture()
        let sut = fixture.makeSuggestionTrayController()
        let window = makeVisibleWindow(rootViewController: sut)
        defer {
            detachAndHide(window)
            fixture.tearDownSuggestionDependencies()
        }

        let sessionStarted = expectation(description: "Tray favorites started a logical RMF session")
        fixture.promoCoordinator.onSessionStarted = { _ in
            sessionStarted.fulfill()
        }
        sut.show(for: .favorites, animated: false)
        await fulfillment(of: [sessionStarted], timeout: 1)
        fixture.promoCoordinator.onSessionStarted = nil

        let ownedSession = fixture.promoCoordinator.arbiter.snapshot.remoteMessageSession
        XCTAssertNotNil(sut.exposedPromoRendererID)
        XCTAssertNotNil(ownedSession)

        let release = expectation(description: "Duck.ai content completed favorites RMF removal")
        fixture.promoCoordinator.onSessionReleased = { _ in
            release.fulfill()
        }
        sut.show(for: .duckAISuggestions(query: "prompt"), animated: false)

        XCTAssertNil(sut.exposedPromoRendererID)
        XCTAssertNil(fixture.promoSurfaceExposureController.snapshot.effectiveSelectedRendererID)
        XCTAssertFalse(fixture.promoCoordinator.registeredRendererIsEligible)
        XCTAssertEqual(
            fixture.promoCoordinator.arbiter.snapshot.remoteMessageSession,
            ownedSession,
            "Semantic exposure must clear before the exact physical removal terminal releases ownership"
        )

        await fulfillment(of: [release], timeout: 1)
        fixture.promoCoordinator.onSessionReleased = nil

        XCTAssertNil(fixture.promoCoordinator.registeredRenderer)
        XCTAssertNil(fixture.promoCoordinator.arbiter.snapshot.activeOwner)
        XCTAssertEqual(fixture.promoCoordinator.successfulSessionCount, 1)
        XCTAssertEqual(fixture.promoCoordinator.releaseCount, 1)
    }

    func testDeactivatingTrayKeepsCachedNewTabPageInactiveUntilFavoritesReturn() async {
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
        let firstSession = fixture.promoCoordinator.arbiter.snapshot.remoteMessageSession
        XCTAssertNotNil(cachedRenderer)
        XCTAssertTrue(fixture.promoCoordinator.registeredRendererIsEligible)
        XCTAssertNotNil(firstSession)

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
        XCTAssertNil(fixture.promoCoordinator.arbiter.snapshot.activeOwner)

        let secondSessionStarted = expectation(description: "Returning to tray favorites started a fresh RMF session")
        fixture.promoCoordinator.onSessionStarted = { _ in
            secondSessionStarted.fulfill()
        }
        sut.show(for: .favorites, animated: false)
        await fulfillment(of: [secondSessionStarted], timeout: 1)
        fixture.promoCoordinator.onSessionStarted = nil

        let secondSession = fixture.promoCoordinator.arbiter.snapshot.remoteMessageSession
        XCTAssertTrue(fixture.promoCoordinator.registeredRenderer === cachedRenderer)
        XCTAssertTrue(fixture.promoCoordinator.registeredRendererIsEligible)
        XCTAssertNotNil(secondSession)
        XCTAssertNotEqual(secondSession?.id, firstSession?.id)

        let secondRelease = expectation(description: "Tray teardown completed favorites RMF removal")
        fixture.promoCoordinator.onSessionReleased = { _ in
            secondRelease.fulfill()
        }
        sut.teardownPopoverSuggestions()
        await fulfillment(of: [secondRelease], timeout: 1)

        XCTAssertTrue(sut.isShowingFavorites, "Tray teardown must preserve its cached favorites content")
        XCTAssertTrue(fixture.promoCoordinator.registeredRenderer === cachedRenderer)
        XCTAssertFalse(fixture.promoCoordinator.registeredRendererIsEligible)
        XCTAssertNil(fixture.promoCoordinator.arbiter.snapshot.activeOwner)
        XCTAssertEqual(fixture.promoCoordinator.successfulSessionCount, 2)
        XCTAssertEqual(fixture.promoCoordinator.releaseCount, 2)
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
        XCTAssertNil(fixture.promoCoordinator.arbiter.snapshot.activeOwner)
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
    lazy var promoSurfaceExposureController = NewTabPagePromoExposureController(selectionSink: promoCoordinator)
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
        promoSurfaceExposureController: promoSurfaceExposureController,
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
            promoSurfaceExposureController: dependencies.promoSurfaceExposureController,
            appSettings: dependencies.appSettings,
            faviconsCache: dependencies.faviconsCache,
            subscriptionManager: dependencies.subscriptionManager,
            internalUserCommands: dependencies.internalUserCommands
        )
    }

    func makeSuggestionTrayController(
        controllerInstallationDidComplete: @escaping (UIViewController) -> Void = { _ in }) -> SuggestionTrayViewController {
        let dependencies = suggestionTrayDependencies
        let controller = SuggestionTrayViewController(
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
        resolvePromoExposure(from: controller)
        return controller
    }

    func resolvePromoExposure(from provider: NewTabPagePromoSurfaceProviding) {
        provider.onPromoSurfaceExposureChanged = { [weak self, weak provider] in
            guard let self, let provider else { return }
            promoSurfaceExposureController.setRouteCandidateRendererID(provider.exposedPromoRendererID)
        }
        promoSurfaceExposureController.setRouteCandidateRendererID(provider.exposedPromoRendererID)
    }

    func tearDownSuggestionDependencies() {
        try? bookmarksDatabase.tearDown(deleteStores: true)
    }
}

@MainActor
private final class ArbitratingPromoHostCoordinator: NewTabPagePromoCoordinating {
    private struct SessionState {
        let session: PromoQueueRemoteMessageSession
        let presentation: PromoQueueRemoteMessagePresentation
        let lease: PromoQueueRemoteMessageLease
        var appearanceWasConfirmed = false
    }

    private struct RemovalState {
        let registrationID: UUID
        let sessionID: UUID
        let presentationID: UUID
        let removalID: UUID
        var terminalWasReported = false
    }

    let arbiter = PromoQueueLeaseArbiter()
    let promoCoordinationMode = PromoCoordinationMode.coordinated

    private(set) var sessionAttemptCount = 0
    private(set) var successfulSessionCount = 0
    private(set) var presentationCount = 0
    private(set) var appearanceCount = 0
    private(set) var releaseCount = 0
    var onRendererRegistered: ((UUID) -> Void)?
    var onSessionStarted: ((PromoQueueRemoteMessageSession) -> Void)?
    var onSessionReleased: ((PromoQueueRemoteMessageSession) -> Void)?

    var registeredRenderer: NewTabPagePromoRendering? {
        isRendererRegistered ? rendererTarget : nil
    }

    var registeredRendererID: UUID? {
        isRendererRegistered ? rendererID : nil
    }

    var registeredRendererIsEligible: Bool {
        isRendererEffectivelyEligible
    }

    private weak var rendererTarget: NewTabPagePromoRendering?
    private var rendererID: UUID?
    private var selectedRendererID: UUID?
    private var registrationID: UUID?
    private var rendererCandidate = PromoQueueRemoteMessageCandidateState.none
    private var isRendererLocallyReady = false
    private var isRendererRegistered = false
    private var sessionState: SessionState?
    private var removalState: RemovalState?

    func setSelectedRemoteMessageRendererID(_ rendererID: UUID?) {
        guard selectedRendererID != rendererID else { return }
        selectedRendererID = rendererID
        reconcile()
    }

    func registerRemoteMessageRenderer(
        id rendererID: UUID,
        target: NewTabPagePromoRendering
    ) -> NewTabPagePromoRendererRegistration {
        let registrationID = UUID()
        self.rendererID = rendererID
        self.registrationID = registrationID
        rendererTarget = target
        rendererCandidate = .none
        isRendererLocallyReady = false
        isRendererRegistered = true
        onRendererRegistered?(rendererID)

        return NewTabPagePromoRendererRegistration(
            updateHandler: { [weak self] candidate, isLocallyReady in
                self?.updateRenderer(
                    registrationID: registrationID,
                    candidate: candidate,
                    isLocallyReady: isLocallyReady
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
        isLocallyReady: Bool
    ) {
        guard self.registrationID == registrationID,
              isRendererRegistered else {
            return
        }

        rendererCandidate = candidate
        isRendererLocallyReady = isLocallyReady
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
              isRendererEffectivelyEligible,
              isAttachedToWindow,
              rendererTarget?.isRemoteMessageRendererAttachedToWindow == true,
              removalState == nil,
              var sessionState,
              sessionState.session.id == sessionID,
              sessionState.presentation.id == presentationID,
              candidateMessageID == sessionState.session.messageID,
              !sessionState.appearanceWasConfirmed else {
            return .rejected
        }

        sessionState.appearanceWasConfirmed = true
        self.sessionState = sessionState
        appearanceCount += 1
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
        isRendererLocallyReady = false
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
              isRendererEffectivelyEligible,
              let messageID = candidateMessageID,
              let rendererTarget else {
            return
        }

        startSession(messageID: messageID, renderer: rendererTarget)
    }

    private func startSession(messageID: String, renderer: NewTabPagePromoRendering) {
        sessionAttemptCount += 1
        let session = PromoQueueRemoteMessageSession(id: UUID(), messageID: messageID)

        switch arbiter.acquireRemoteMessageLease(for: session) {
        case .acquired(let lease):
            let presentation = PromoQueueRemoteMessagePresentation(id: UUID(), session: session)
            sessionState = SessionState(
                session: session,
                presentation: presentation,
                lease: lease
            )
            guard renderer.showRemoteMessage(presentation) else {
                sessionState = nil
                _ = lease.release()
                return
            }
            successfulSessionCount += 1
            presentationCount += 1
            onSessionStarted?(session)
        case .blockedByModal, .blockedByRemoteMessage:
            break
        }
    }

    private func shouldKeepShowing(_ sessionState: SessionState) -> Bool {
        isRendererRegistered &&
            isRendererEffectivelyEligible &&
            rendererTarget != nil &&
            candidateMessageID == sessionState.session.messageID
    }

    private var isRendererEffectivelyEligible: Bool {
        isRendererRegistered &&
            isRendererLocallyReady &&
            selectedRendererID == rendererID
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
        guard sessionState.lease.release() else {
            return
        }

        releaseCount += 1
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
        rendererID = nil
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
