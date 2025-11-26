//
//  PopupHandlingTabExtensionTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import Combine
import Common
import FeatureFlags
import WebKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser
@testable import Navigation

final class PopupHandlingTabExtensionTests: XCTestCase {

    var popupHandlingExtension: PopupHandlingTabExtension!
    var mockFeatureFlagger: MockFeatureFlagger!
    var mockPopupBlockingConfig: MockPopupBlockingConfiguration!
    var mockPermissionModel: PermissionModel!
    var testPermissionManager: TestPermissionManager!
    var interactionEventsSubject: PassthroughSubject<WebViewInteractionEvent, Never>!
    var mockDate: Date!
    var childTabCreated: ((WKWebViewConfiguration, WKNavigationAction, NewWindowPolicy) -> Tab?)?
    var tabPresented: ((Tab, NewWindowPolicy) -> Void)?
    var cancellables = Set<AnyCancellable>()
    var webView: WKWebView!
    var configuration: WKWebViewConfiguration!
    var windowFeatures: WKWindowFeatures!

    override func setUp() {
        super.setUp()
        mockFeatureFlagger = MockFeatureFlagger()
        mockPopupBlockingConfig = MockPopupBlockingConfiguration()
        testPermissionManager = TestPermissionManager()
        mockPermissionModel = PermissionModel(permissionManager: testPermissionManager)
        interactionEventsSubject = PassthroughSubject<WebViewInteractionEvent, Never>()
        webView = WKWebView()
        configuration = WKWebViewConfiguration()
        windowFeatures = WKWindowFeatures()
    }

    override func tearDown() {
        popupHandlingExtension = nil
        mockFeatureFlagger = nil
        mockPopupBlockingConfig = nil
        mockPermissionModel = nil
        testPermissionManager = nil
        interactionEventsSubject = nil
        mockDate = nil
        childTabCreated = nil
        tabPresented = nil
        cancellables.removeAll()
        webView = nil
        configuration = nil
        windowFeatures = nil
        super.tearDown()
    }

    @MainActor
    private func createExtension() -> PopupHandlingTabExtension {
        let windowControllersManager = WindowControllersManagerMock()
        let tabsPreferences = TabsPreferences(
            persistor: MockTabsPreferencesPersistor(),
            windowControllersManager: windowControllersManager
        )

        return PopupHandlingTabExtension(
            tabsPreferences: tabsPreferences,
            burnerMode: BurnerMode(isBurner: false),
            permissionModel: mockPermissionModel,
            createChildTab: { [weak self] config, action, policy in
                self?.childTabCreated?(config, action, policy)
            },
            presentTab: { [weak self] tab, policy in
                self?.tabPresented?(tab, policy)
            },
            newWindowPolicyDecisionMakers: { nil },
            featureFlagger: mockFeatureFlagger,
            popupBlockingConfig: mockPopupBlockingConfig,
            dateProvider: { [weak self] in self!.mockDate! },
            interactionEventsPublisher: interactionEventsSubject.eraseToAnyPublisher()
        )
    }

    private func makeMockNavigationAction(url: URL, isUserInitiated: Bool = false) -> WKNavigationAction {
        let sourceFrame = WKFrameInfoMock(
            webView: webView,
            securityOrigin: WKSecurityOriginMock.new(url: URL(string: "https://example.com")!),
            request: URLRequest(url: URL(string: "https://example.com")!),
            isMainFrame: true
        )
        return MockWKNavigationAction(
            request: URLRequest(url: url),
            targetFrame: nil,
            sourceFrame: sourceFrame,
            isUserInitiated: isUserInitiated
        )
    }

    // MARK: - User Interaction Tracking Tests

    @MainActor
    func testWhenUserInteractionPublisherEnabled_ThenMouseDownUpdatesLastInteractionDate() {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.popupBlocking.rawValue] = true
        mockFeatureFlagger.featuresStub[FeatureFlag.extendedUserInitiatedPopupTimeout.rawValue] = true
        mockPopupBlockingConfig.userInitiatedPopupThreshold = 6.0
        popupHandlingExtension = createExtension()

        // Set current time
        let currentTime = Date(timeIntervalSince1970: 1000)
        mockDate = currentTime

        let expectation = expectation(description: "User interaction recorded")

        // WHEN
        let event = NSEvent()
        interactionEventsSubject.send(.mouseDown(event))

        // Wait for interaction to be processed on main actor
        DispatchQueue.main.async {
            // THEN - Popup should be allowed within threshold
            let navigationAction = self.makeMockNavigationAction(url: URL(string: "https://popup.com")!, isUserInitiated: false)

            // Advance time by 3 seconds (within 6s threshold)
            self.mockDate = currentTime.addingTimeInterval(3.0)

            let shouldAllow = self.popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(
                for: navigationAction,
                windowFeatures: self.windowFeatures
            )

            XCTAssertTrue(shouldAllow, "Popup should be allowed within interaction threshold")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    @MainActor
    func testWhenUserInteractionPublisherEnabled_ThenKeyDownUpdatesLastInteractionDate() {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.popupBlocking.rawValue] = true
        mockFeatureFlagger.featuresStub[FeatureFlag.extendedUserInitiatedPopupTimeout.rawValue] = true
        mockPopupBlockingConfig.userInitiatedPopupThreshold = 6.0
        popupHandlingExtension = createExtension()

        // Set current time
        let currentTime = Date(timeIntervalSince1970: 1000)
        mockDate = currentTime

        let expectation = expectation(description: "User interaction recorded")

        // WHEN
        let event = NSEvent()
        interactionEventsSubject.send(.keyDown(event))

        // Wait for interaction to be processed on main actor
        DispatchQueue.main.async {
            // THEN - Popup should be allowed within threshold
            let navigationAction = self.makeMockNavigationAction(url: URL(string: "https://popup.com")!, isUserInitiated: false)

            // Advance time by 3 seconds (within 6s threshold)
            self.mockDate = currentTime.addingTimeInterval(3.0)

            let shouldAllow = self.popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(
                for: navigationAction,
                windowFeatures: self.windowFeatures
            )

            XCTAssertTrue(shouldAllow, "Popup should be allowed within interaction threshold")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    @MainActor
    func testWhenUserInteractionPublisherEnabled_ThenScrollWheelDoesNotUpdateLastInteractionDate() {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.extendedUserInitiatedPopupTimeout.rawValue] = true
        mockPopupBlockingConfig.userInitiatedPopupThreshold = 6.0
        popupHandlingExtension = createExtension()

        // Set current time
        let currentTime = Date(timeIntervalSince1970: 1000)
        mockDate = currentTime

        let expectation = expectation(description: "Scroll event processed")

        // WHEN
        let event = NSEvent()
        interactionEventsSubject.send(.scrollWheel(event))

        // Wait for event to be processed on main actor
        DispatchQueue.main.async {
            // THEN - Popup should NOT be allowed (no interaction recorded)
            let navigationAction = self.makeMockNavigationAction(url: URL(string: "https://popup.com")!, isUserInitiated: false)

            let shouldAllow = self.popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(
                for: navigationAction,
                windowFeatures: self.windowFeatures
            )

            XCTAssertFalse(shouldAllow, "Scroll wheel should not record interaction")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    @MainActor
    func testWhenUserInteractionPublisherDisabled_ThenInteractionsDoNotUpdateLastInteractionDate() {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.extendedUserInitiatedPopupTimeout.rawValue] = false
        popupHandlingExtension = createExtension()

        // Set current time
        let currentTime = Date(timeIntervalSince1970: 1000)
        mockDate = currentTime

        let expectation = expectation(description: "Events processed")

        // WHEN
        let event = NSEvent()
        interactionEventsSubject.send(.mouseDown(event))
        interactionEventsSubject.send(.keyDown(event))

        // Wait for events to be processed on main actor
        DispatchQueue.main.async {
            // THEN - Should fall back to WebKit's isUserInitiated
            let navigationAction = self.makeMockNavigationAction(url: URL(string: "https://popup.com")!, isUserInitiated: false)

            let shouldAllow = self.popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(
                for: navigationAction,
                windowFeatures: self.windowFeatures
            )

            XCTAssertFalse(shouldAllow, "Should use WebKit's isUserInitiated when feature disabled")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Popup Creation Tests

    @MainActor
    func testWhenPopupIsUserInitiated_ThenShouldAllowWithoutPermission() {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.popupBlocking.rawValue] = false
        popupHandlingExtension = createExtension()

        let navigationAction = makeMockNavigationAction(url: URL(string: "https://popup.com")!, isUserInitiated: true)

        // WHEN
        let shouldAllow = popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(
            for: navigationAction,
            windowFeatures: windowFeatures
        )

        // THEN
        XCTAssertTrue(shouldAllow, "User-initiated popup should be allowed without permission")
    }

    @MainActor
    func testWhenPopupIsNotUserInitiated_AndNoRecentInteraction_ThenShouldRequirePermission() {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.popupBlocking.rawValue] = false
        popupHandlingExtension = createExtension()

        let navigationAction = makeMockNavigationAction(url: URL(string: "https://popup.com")!, isUserInitiated: false)

        // WHEN
        let shouldAllow = popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(
            for: navigationAction,
            windowFeatures: windowFeatures
        )

        // THEN
        XCTAssertFalse(shouldAllow, "Non-user-initiated popup without recent interaction should require permission")
    }

    // MARK: - Extended Timeout Logic Tests

    @MainActor
    func testWhenNoUserInteractionRecorded_ThenShouldRequirePermission() {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.popupBlocking.rawValue] = true
        mockFeatureFlagger.featuresStub[FeatureFlag.extendedUserInitiatedPopupTimeout.rawValue] = true
        mockPopupBlockingConfig.userInitiatedPopupThreshold = 6.0
        popupHandlingExtension = createExtension()

        mockDate = Date(timeIntervalSince1970: 1000)

        // WHEN - No user interaction has occurred (lastUserInteractionDate is nil)
        let navigationAction = makeMockNavigationAction(url: URL(string: "https://popup.com")!, isUserInitiated: false)

        let shouldAllow = popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(
            for: navigationAction,
            windowFeatures: windowFeatures
        )

        // THEN
        XCTAssertFalse(shouldAllow, "Popup should require permission when no interaction recorded")
    }

    @MainActor
    func testWhenOnlyPopupBlockingEnabled_ThenFallsBackToWebKitUserInitiated() {
        // GIVEN - Only popupBlocking on, extendedUserInitiatedPopupTimeout off
        mockFeatureFlagger.featuresStub[FeatureFlag.popupBlocking.rawValue] = true
        mockFeatureFlagger.featuresStub[FeatureFlag.extendedUserInitiatedPopupTimeout.rawValue] = false
        popupHandlingExtension = createExtension()

        // WHEN - navigationAction.isUserInitiated = true/false
        let userInitiatedAction = makeMockNavigationAction(url: URL(string: "https://popup.com")!, isUserInitiated: true)
        let nonUserInitiatedAction = makeMockNavigationAction(url: URL(string: "https://popup.com")!, isUserInitiated: false)

        // THEN - Should use WebKit's isUserInitiated
        XCTAssertTrue(popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(for: userInitiatedAction, windowFeatures: windowFeatures))
        XCTAssertFalse(popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(for: nonUserInitiatedAction, windowFeatures: windowFeatures))
    }

    @MainActor
    func testWhenBothFeaturesDisabled_ThenFallsBackToWebKitUserInitiated() {
        // GIVEN - Both features off
        mockFeatureFlagger.featuresStub[FeatureFlag.popupBlocking.rawValue] = false
        mockFeatureFlagger.featuresStub[FeatureFlag.extendedUserInitiatedPopupTimeout.rawValue] = false
        popupHandlingExtension = createExtension()

        // WHEN - navigationAction.isUserInitiated = true/false
        let userInitiatedAction = makeMockNavigationAction(url: URL(string: "https://popup.com")!, isUserInitiated: true)
        let nonUserInitiatedAction = makeMockNavigationAction(url: URL(string: "https://popup.com")!, isUserInitiated: false)

        // THEN - Should use WebKit's isUserInitiated
        XCTAssertTrue(popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(for: userInitiatedAction, windowFeatures: windowFeatures))
        XCTAssertFalse(popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(for: nonUserInitiatedAction, windowFeatures: windowFeatures))
    }

    @MainActor
    func testWhenRecentUserInteraction_AndExtendedTimeoutEnabled_ThenShouldAllowPopupWithoutPermission() {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.popupBlocking.rawValue] = true
        mockFeatureFlagger.featuresStub[FeatureFlag.extendedUserInitiatedPopupTimeout.rawValue] = true
        mockPopupBlockingConfig.userInitiatedPopupThreshold = 6.0
        popupHandlingExtension = createExtension()

        // Set current time
        let currentTime = Date(timeIntervalSince1970: 1000)
        mockDate = currentTime

        let expectation = expectation(description: "User interaction recorded")

        // WHEN - Simulate user interaction
        let event = NSEvent()
        interactionEventsSubject.send(.mouseDown(event))

        // Wait for interaction to be processed on main actor
        DispatchQueue.main.async {
            let navigationAction = self.makeMockNavigationAction(url: URL(string: "https://popup.com")!, isUserInitiated: false)

            // Advance time by 3 seconds (within 6s threshold)
            self.mockDate = currentTime.addingTimeInterval(3.0)

            let shouldAllow = self.popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(
                for: navigationAction,
                windowFeatures: self.windowFeatures
            )

            // THEN
            XCTAssertTrue(shouldAllow, "Should allow popup due to recent user interaction")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    @MainActor
    func testWhenOldUserInteraction_AndExtendedTimeoutEnabled_ThenShouldRequirePermission() {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.popupBlocking.rawValue] = true
        mockFeatureFlagger.featuresStub[FeatureFlag.extendedUserInitiatedPopupTimeout.rawValue] = true
        mockPopupBlockingConfig.userInitiatedPopupThreshold = 6.0
        popupHandlingExtension = createExtension()

        // Set current time
        let currentTime = Date(timeIntervalSince1970: 1000)
        mockDate = currentTime

        let expectation = expectation(description: "User interaction recorded")

        // WHEN - Simulate user interaction
        let event = NSEvent()
        interactionEventsSubject.send(.mouseDown(event))

        // Wait for interaction to be processed on main actor
        DispatchQueue.main.async {
            let navigationAction = self.makeMockNavigationAction(url: URL(string: "https://popup.com")!, isUserInitiated: false)

            // Advance time by 7 seconds (beyond 6s threshold)
            self.mockDate = currentTime.addingTimeInterval(7.0)

            let shouldAllow = self.popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(
                for: navigationAction,
                windowFeatures: self.windowFeatures
            )

            // THEN
            XCTAssertFalse(shouldAllow, "Should require permission due to old user interaction")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Empty URL Suppression Tests

    @MainActor
    func testWhenPopupApprovedAndSuppressEmptyUrlsEnabled_ThenEmptyUrlIsBlocked() {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.popupBlocking.rawValue] = true
        mockFeatureFlagger.featuresStub[FeatureFlag.suppressEmptyPopUpsOnApproval.rawValue] = true
        popupHandlingExtension = createExtension()

        let queryAddedExpectation = expectation(description: "Permission query added")
        let permissionGrantedExpectation = expectation(description: "Permission callback completed")
        permissionGrantedExpectation.isInverted = true // We expect childTabCreated NOT to be called

        // Subscribe to permission query changes
        mockPermissionModel.$authorizationQuery
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { query in
                queryAddedExpectation.fulfill()
                // Grant permission when query is added
                self.mockPermissionModel.allow(query)
            }
            .store(in: &cancellables)

        childTabCreated = { _, _, _ in
            permissionGrantedExpectation.fulfill() // This shouldn't happen
            return nil
        }

        let navigationAction = makeMockNavigationAction(url: .empty, isUserInitiated: false)

        // WHEN
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: navigationAction, windowFeatures: windowFeatures)

        // Wait for query to be added and granted
        wait(for: [queryAddedExpectation], timeout: 1.0)

        // Wait to ensure childTabCreated is NOT called
        wait(for: [permissionGrantedExpectation], timeout: 0.1)
    }

    @MainActor
    func testWhenPopupApprovedAndSuppressEmptyUrlsDisabled_ThenEmptyUrlIsAllowed() {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.popupBlocking.rawValue] = true
        mockFeatureFlagger.featuresStub[FeatureFlag.suppressEmptyPopUpsOnApproval.rawValue] = false
        popupHandlingExtension = createExtension()

        let queryAddedExpectation = expectation(description: "Permission query added")
        let popupCreatedExpectation = expectation(description: "Popup created")

        // Subscribe to permission query changes
        mockPermissionModel.$authorizationQuery
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { query in
                queryAddedExpectation.fulfill()
                // Grant permission when query is added (async to simulate real behavior)
                self.mockPermissionModel.allow(query)
            }
            .store(in: &cancellables)

        childTabCreated = { _, _, _ in
            popupCreatedExpectation.fulfill()
            return nil
        }

        let navigationAction = makeMockNavigationAction(url: .empty, isUserInitiated: false)

        // WHEN
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: navigationAction, windowFeatures: windowFeatures)

        // THEN - Wait for query to be added, granted, and popup created
        wait(for: [queryAddedExpectation, popupCreatedExpectation], timeout: 1.0)
    }

    // MARK: - Allow Popups for Current Page Tests

    @MainActor
    func testWhenEmptyUrlPopupApproved_AndAllowPopupsForCurrentPageEnabled_ThenSubsequentEmptyUrlsAllowed() {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.popupBlocking.rawValue] = true
        mockFeatureFlagger.featuresStub[FeatureFlag.suppressEmptyPopUpsOnApproval.rawValue] = true
        mockFeatureFlagger.featuresStub[FeatureFlag.allowPopupsForCurrentPage.rawValue] = true
        popupHandlingExtension = createExtension()

        let queryAddedExpectation = expectation(description: "Permission query added")
        let permissionCallbackExpectation = expectation(description: "Permission callback completed")
        permissionCallbackExpectation.isInverted = true // First popup should be suppressed

        // Subscribe to permission query changes
        mockPermissionModel.$authorizationQuery
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { query in
                queryAddedExpectation.fulfill()
                // Grant permission when query is added (async to simulate real behavior)
                self.mockPermissionModel.allow(query)
            }
            .store(in: &cancellables)

        childTabCreated = { _, _, _ in
            permissionCallbackExpectation.fulfill() // Shouldn't be called
            return nil
        }

        // First popup with empty URL
        let firstAction = makeMockNavigationAction(url: .empty, isUserInitiated: false)

        // WHEN - First popup requires permission
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: firstAction, windowFeatures: windowFeatures)

        // Wait for query to be added and granted
        wait(for: [queryAddedExpectation], timeout: 1.0)

        // Wait for permission callback to complete (inverted expectation ensures tab wasn't created)
        wait(for: [permissionCallbackExpectation], timeout: 0.1)

        // THEN - Second empty URL popup should be allowed without permission
        let secondAction = makeMockNavigationAction(url: .empty, isUserInitiated: false)

        let shouldAllow = popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(
            for: secondAction,
            windowFeatures: windowFeatures
        )

        XCTAssertTrue(shouldAllow, "Subsequent empty URL should be allowed after initial approval")
    }

    @MainActor
    func testWhenEmptyUrlPopupApproved_AndAllowPopupsForCurrentPageEnabled_ThenSubsequentAboutUrlsAllowed() {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.popupBlocking.rawValue] = true
        mockFeatureFlagger.featuresStub[FeatureFlag.suppressEmptyPopUpsOnApproval.rawValue] = true
        mockFeatureFlagger.featuresStub[FeatureFlag.allowPopupsForCurrentPage.rawValue] = true
        popupHandlingExtension = createExtension()

        let queryAddedExpectation = expectation(description: "Permission query added")
        let permissionCallbackExpectation = expectation(description: "Permission callback completed")
        permissionCallbackExpectation.isInverted = true // First popup should be suppressed

        // Subscribe to permission query changes
        mockPermissionModel.$authorizationQuery
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { query in
                queryAddedExpectation.fulfill()
                // Grant permission when query is added (async to simulate real behavior)
                self.mockPermissionModel.allow(query)
            }
            .store(in: &cancellables)

        childTabCreated = { _, _, _ in
            permissionCallbackExpectation.fulfill() // Shouldn't be called
            return nil
        }

        // First popup with empty URL
        let firstAction = makeMockNavigationAction(url: .empty, isUserInitiated: false)

        // WHEN - First popup requires permission
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: firstAction, windowFeatures: windowFeatures)

        // Wait for query to be added and granted
        wait(for: [queryAddedExpectation], timeout: 1.0)

        // Wait for permission callback to complete (inverted expectation ensures tab wasn't created)
        wait(for: [permissionCallbackExpectation], timeout: 0.1)

        // THEN - Second popup with about: URL should be allowed without permission
        let secondAction = makeMockNavigationAction(url: URL(string: "about:blank")!, isUserInitiated: false)

        let shouldAllow = popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(
            for: secondAction,
            windowFeatures: windowFeatures
        )

        XCTAssertTrue(shouldAllow, "Subsequent about: URL should be allowed after initial approval")
    }

    @MainActor
    func testWhenEmptyUrlPopupApproved_AndAllowPopupsForCurrentPageEnabled_ThenCrossOriginPopupsAllowed() {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.popupBlocking.rawValue] = true
        mockFeatureFlagger.featuresStub[FeatureFlag.suppressEmptyPopUpsOnApproval.rawValue] = true
        mockFeatureFlagger.featuresStub[FeatureFlag.allowPopupsForCurrentPage.rawValue] = true
        popupHandlingExtension = createExtension()

        let queryAddedExpectation = expectation(description: "Permission query added")
        let permissionCallbackExpectation = expectation(description: "Permission callback completed")
        permissionCallbackExpectation.isInverted = true // First popup should be suppressed

        // Subscribe to permission query changes
        mockPermissionModel.$authorizationQuery
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { query in
                queryAddedExpectation.fulfill()
                // Grant permission when query is added (async to simulate real behavior)
                self.mockPermissionModel.allow(query)
            }
            .store(in: &cancellables)

        childTabCreated = { _, _, _ in
            permissionCallbackExpectation.fulfill() // Shouldn't be called
            return nil
        }

        // First popup with empty URL
        let firstAction = makeMockNavigationAction(url: .empty, isUserInitiated: false)

        // WHEN - First popup requires permission
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: firstAction, windowFeatures: windowFeatures)

        // Wait for query to be added and granted
        wait(for: [queryAddedExpectation], timeout: 1.0)

        // Wait for permission callback to complete (inverted expectation ensures tab wasn't created)
        wait(for: [permissionCallbackExpectation], timeout: 0.1)

        // THEN - Cross-origin popup should be allowed when feature is enabled
        let crossOriginAction = makeMockNavigationAction(url: URL(string: "https://other-domain.com")!, isUserInitiated: false)

        let shouldAllow = popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(
            for: crossOriginAction,
            windowFeatures: windowFeatures
        )

        XCTAssertTrue(shouldAllow, "Cross-origin popup should be allowed when allowPopupsForCurrentPage is enabled")
    }

    @MainActor
    func testWhenNavigationCommits_AndAllowPopupsForCurrentPageEnabled_ThenPopupAllowanceCleared() {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.popupBlocking.rawValue] = true
        mockFeatureFlagger.featuresStub[FeatureFlag.suppressEmptyPopUpsOnApproval.rawValue] = true
        mockFeatureFlagger.featuresStub[FeatureFlag.allowPopupsForCurrentPage.rawValue] = true
        popupHandlingExtension = createExtension()

        let queryAddedExpectation = expectation(description: "Permission query added")
        let permissionCallbackExpectation = expectation(description: "Permission callback completed")
        permissionCallbackExpectation.isInverted = true // First popup should be suppressed

        // Subscribe to permission query changes
        mockPermissionModel.$authorizationQuery
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { query in
                queryAddedExpectation.fulfill()
                // Grant permission when query is added (async to simulate real behavior)
                self.mockPermissionModel.allow(query)
            }
            .store(in: &cancellables)

        childTabCreated = { _, _, _ in
            permissionCallbackExpectation.fulfill() // Shouldn't be called
            return nil
        }

        // First popup with empty URL to establish allowance
        let firstAction = makeMockNavigationAction(url: .empty, isUserInitiated: false)

        // WHEN
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: firstAction, windowFeatures: windowFeatures)

        // Wait for query to be added and granted
        wait(for: [queryAddedExpectation], timeout: 1.0)

        // Wait for permission callback to complete (inverted expectation ensures tab wasn't created)
        wait(for: [permissionCallbackExpectation], timeout: 0.1)

        // Verify allowance is set
        let secondAction = makeMockNavigationAction(url: .empty, isUserInitiated: false)

        let shouldAllowBefore = popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(
            for: secondAction,
            windowFeatures: windowFeatures
        )
        XCTAssertTrue(shouldAllowBefore, "Popup should be allowed before navigation")

        // Navigate to clear allowance
        let navigation = Navigation(identity: NavigationIdentity(nil), responders: ResponderChain(), state: .started, isCurrent: true)
        popupHandlingExtension.willStart(navigation)

        // THEN - Popup should no longer be allowed
        let shouldAllowAfter = popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(
            for: secondAction,
            windowFeatures: windowFeatures
        )
        XCTAssertFalse(shouldAllowAfter, "Popup allowance should be cleared after navigation")
    }

    @MainActor
    func testWhenAllowPopupsForCurrentPageDisabled_ThenCrossOriginPopupsStillRequirePermission() {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.popupBlocking.rawValue] = true
        mockFeatureFlagger.featuresStub[FeatureFlag.suppressEmptyPopUpsOnApproval.rawValue] = true
        mockFeatureFlagger.featuresStub[FeatureFlag.allowPopupsForCurrentPage.rawValue] = false
        popupHandlingExtension = createExtension()

        let queryAddedExpectation = expectation(description: "Permission query added")
        let permissionCallbackExpectation = expectation(description: "Permission callback completed")
        permissionCallbackExpectation.isInverted = true // First popup should be suppressed

        // Subscribe to permission query changes
        mockPermissionModel.$authorizationQuery
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { query in
                queryAddedExpectation.fulfill()
                // Grant permission when query is added (async to simulate real behavior)
                self.mockPermissionModel.allow(query)
            }
            .store(in: &cancellables)

        childTabCreated = { _, _, _ in
            permissionCallbackExpectation.fulfill() // Shouldn't be called
            return nil
        }

        // First popup with empty URL
        let firstAction = makeMockNavigationAction(url: .empty, isUserInitiated: false)

        // WHEN
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: firstAction, windowFeatures: windowFeatures)

        // Wait for query to be added and granted
        wait(for: [queryAddedExpectation], timeout: 1.0)

        // Wait for permission callback to complete (inverted expectation ensures tab wasn't created)
        wait(for: [permissionCallbackExpectation], timeout: 0.1)

        // THEN - Empty/about URLs still allowed, but cross-origin requires permission when feature disabled
        let emptyAction = makeMockNavigationAction(url: .empty, isUserInitiated: false)
        XCTAssertTrue(
            popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(for: emptyAction, windowFeatures: windowFeatures),
            "Empty URL should still be allowed"
        )

        let crossOriginAction = makeMockNavigationAction(url: URL(string: "https://other-domain.com")!, isUserInitiated: false)
        XCTAssertFalse(
            popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(for: crossOriginAction, windowFeatures: windowFeatures),
            "Cross-origin popup should require permission when feature is disabled"
        )
    }

    // MARK: - Multiple Consecutive Popup Tests

    @MainActor
    func testWhenMultiplePopupsReceived_AndAllowForCurrentPageEnabled_ThenAllSubsequentPopupsAllowed() {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.popupBlocking.rawValue] = true
        mockFeatureFlagger.featuresStub[FeatureFlag.suppressEmptyPopUpsOnApproval.rawValue] = true
        mockFeatureFlagger.featuresStub[FeatureFlag.allowPopupsForCurrentPage.rawValue] = true
        popupHandlingExtension = createExtension()

        let queryAddedExpectation = expectation(description: "Permission query added")

        // Subscribe to permission query changes
        mockPermissionModel.$authorizationQuery
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { query in
                queryAddedExpectation.fulfill()
                self.mockPermissionModel.allow(query)
            }
            .store(in: &cancellables)

        childTabCreated = { _, _, _ in nil }

        // First popup with empty URL
        let firstAction = makeMockNavigationAction(url: .empty, isUserInitiated: false)
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: firstAction, windowFeatures: windowFeatures)

        wait(for: [queryAddedExpectation], timeout: 1.0)

        // WHEN - Multiple subsequent popups of different types
        let emptyAction = makeMockNavigationAction(url: .empty, isUserInitiated: false)
        let aboutBlankAction = makeMockNavigationAction(url: URL(string: "about:blank")!, isUserInitiated: false)
        let crossOriginAction = makeMockNavigationAction(url: URL(string: "https://other-domain.com")!, isUserInitiated: false)
        let sameDomainAction = makeMockNavigationAction(url: URL(string: "https://example.com/popup")!, isUserInitiated: false)

        // THEN - All should be allowed
        XCTAssertTrue(popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(for: emptyAction, windowFeatures: windowFeatures))
        XCTAssertTrue(popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(for: aboutBlankAction, windowFeatures: windowFeatures))
        XCTAssertTrue(popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(for: crossOriginAction, windowFeatures: windowFeatures))
        XCTAssertTrue(popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(for: sameDomainAction, windowFeatures: windowFeatures))
    }

    @MainActor
    func testWhenAboutBlankPopupApproved_ThenSuppressedAndSubsequentAllowed() {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.popupBlocking.rawValue] = true
        mockFeatureFlagger.featuresStub[FeatureFlag.suppressEmptyPopUpsOnApproval.rawValue] = true
        mockFeatureFlagger.featuresStub[FeatureFlag.allowPopupsForCurrentPage.rawValue] = true
        popupHandlingExtension = createExtension()

        let queryAddedExpectation = expectation(description: "Permission query added")
        let permissionCallbackExpectation = expectation(description: "Permission callback completed")
        permissionCallbackExpectation.isInverted = true
        let permissionGrantedExpectation = expectation(description: "Permission granted")

        mockPermissionModel.$authorizationQuery
            .compactMap { $0 }
            .sink { query in
                queryAddedExpectation.fulfill()
                DispatchQueue.main.async {
                    self.mockPermissionModel.allow(query)
                    permissionGrantedExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        childTabCreated = { _, _, _ in
            permissionCallbackExpectation.fulfill()
            return nil
        }

        // WHEN - about:blank popup
        let aboutBlankAction = makeMockNavigationAction(url: URL(string: "about:blank")!, isUserInitiated: false)
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: aboutBlankAction, windowFeatures: windowFeatures)

        wait(for: [queryAddedExpectation, permissionGrantedExpectation], timeout: 1.0)
        wait(for: [permissionCallbackExpectation], timeout: 0.1)

        // THEN - Subsequent about:blank allowed
        let secondAboutBlank = makeMockNavigationAction(url: URL(string: "about:blank")!, isUserInitiated: false)
        XCTAssertTrue(popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(for: secondAboutBlank, windowFeatures: windowFeatures))
    }

    // MARK: - Temporary Allowance API Tests

    @MainActor
    func testWhenSuppressFeatureDisabled_ThenTemporaryAllowanceDoesNotWork() {
        // GIVEN - suppressEmptyPopUpsOnApproval is OFF
        mockFeatureFlagger.featuresStub[FeatureFlag.suppressEmptyPopUpsOnApproval.rawValue] = false
        mockFeatureFlagger.featuresStub[FeatureFlag.allowPopupsForCurrentPage.rawValue] = true
        popupHandlingExtension = createExtension()

        // Manually set temporary allowance
        popupHandlingExtension.setPopupAllowanceForCurrentPage()
        XCTAssertTrue(popupHandlingExtension.popupsTemporarilyAllowedForCurrentPage)

        // WHEN - Try to open popups
        let emptyAction = makeMockNavigationAction(url: .empty, isUserInitiated: false)
        let regularAction = makeMockNavigationAction(url: URL(string: "https://popup.com")!, isUserInitiated: false)

        // THEN - Temporary allowance should NOT work because suppressEmptyPopUpsOnApproval is OFF
        XCTAssertFalse(popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(for: emptyAction, windowFeatures: windowFeatures))
        XCTAssertFalse(popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(for: regularAction, windowFeatures: windowFeatures))
    }

    @MainActor
    func testSetAndClearPopupAllowanceForCurrentPage() {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.allowPopupsForCurrentPage.rawValue] = true
        popupHandlingExtension = createExtension()

        XCTAssertFalse(popupHandlingExtension.popupsTemporarilyAllowedForCurrentPage, "Should start without allowance")

        // WHEN - Set allowance
        popupHandlingExtension.setPopupAllowanceForCurrentPage()

        // THEN
        XCTAssertTrue(popupHandlingExtension.popupsTemporarilyAllowedForCurrentPage, "Should have allowance after setting")

        // WHEN - Clear allowance
        popupHandlingExtension.clearPopupAllowanceForCurrentPage()

        // THEN
        XCTAssertFalse(popupHandlingExtension.popupsTemporarilyAllowedForCurrentPage, "Should not have allowance after clearing")
    }

    @MainActor
    func testWhenTemporaryAllowanceSet_ThenUserInitiatedStillWorks() {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.allowPopupsForCurrentPage.rawValue] = true
        popupHandlingExtension = createExtension()
        popupHandlingExtension.setPopupAllowanceForCurrentPage()

        // WHEN - User-initiated popup
        let userInitiatedAction = makeMockNavigationAction(url: URL(string: "https://popup.com")!, isUserInitiated: true)

        // THEN - Should still be allowed
        XCTAssertTrue(popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(for: userInitiatedAction, windowFeatures: windowFeatures))
    }

    // MARK: - Edge Cases

    @MainActor
    func testWhenTimeoutExactlyAtBoundary_ThenRequiresPermission() {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.popupBlocking.rawValue] = true
        mockFeatureFlagger.featuresStub[FeatureFlag.extendedUserInitiatedPopupTimeout.rawValue] = true
        mockPopupBlockingConfig.userInitiatedPopupThreshold = 6.0
        popupHandlingExtension = createExtension()

        let currentTime = Date(timeIntervalSince1970: 1000)
        mockDate = currentTime

        let expectation = expectation(description: "User interaction recorded")

        let event = NSEvent()
        interactionEventsSubject.send(.mouseDown(event))

        DispatchQueue.main.async {
            let navigationAction = self.makeMockNavigationAction(url: URL(string: "https://popup.com")!, isUserInitiated: false)

            // Advance time by exactly 6.0 seconds (at boundary)
            self.mockDate = currentTime.addingTimeInterval(6.0)

            let shouldAllow = self.popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(
                for: navigationAction,
                windowFeatures: self.windowFeatures
            )

            XCTAssertFalse(shouldAllow, "Popup at exact timeout boundary should require permission")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    @MainActor
    func testWhenAllowanceSetManually_AndNavigationOccurs_ThenAllowanceCleared() {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.allowPopupsForCurrentPage.rawValue] = true
        popupHandlingExtension = createExtension()

        popupHandlingExtension.setPopupAllowanceForCurrentPage()
        XCTAssertTrue(popupHandlingExtension.popupsTemporarilyAllowedForCurrentPage)

        // WHEN - Navigation occurs
        let navigation = Navigation(identity: NavigationIdentity(nil), responders: ResponderChain(), state: .started, isCurrent: true)
        popupHandlingExtension.willStart(navigation)

        // THEN
        XCTAssertFalse(popupHandlingExtension.popupsTemporarilyAllowedForCurrentPage, "Allowance should be cleared on navigation")
    }

    @MainActor
    func testWhenSuppressFeatureDisabled_ThenAboutBlankNotSuppressed() {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.suppressEmptyPopUpsOnApproval.rawValue] = false
        popupHandlingExtension = createExtension()

        let queryAddedExpectation = expectation(description: "Permission query added")
        let popupCreatedExpectation = expectation(description: "Popup created")

        mockPermissionModel.$authorizationQuery
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { query in
                queryAddedExpectation.fulfill()
                self.mockPermissionModel.allow(query)
            }
            .store(in: &cancellables)

        childTabCreated = { _, _, _ in
            popupCreatedExpectation.fulfill()
            return nil
        }

        // WHEN - about:blank popup
        let aboutBlankAction = makeMockNavigationAction(url: URL(string: "about:blank")!, isUserInitiated: false)
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: aboutBlankAction, windowFeatures: windowFeatures)

        // THEN - Should be created (not suppressed)
        wait(for: [queryAddedExpectation, popupCreatedExpectation], timeout: 1.0)
    }

    // MARK: - Persisted Permission Tests

    @MainActor
    func testWhenAlwaysAllowSet_ThenPopupsAllowedWithoutPrompt() {
        // GIVEN
        popupHandlingExtension = createExtension()
        testPermissionManager.setPermission(.allow, forDomain: "example.com", permissionType: .popups)

        let queryExpectation = expectation(description: "No permission query")
        queryExpectation.isInverted = true

        let popupCreatedExpectation = expectation(description: "Popup created")

        mockPermissionModel.$authorizationQuery
            .compactMap { $0 }
            .sink { _ in
                queryExpectation.fulfill() // Shouldn't happen
            }
            .store(in: &cancellables)

        childTabCreated = { _, _, _ in
            popupCreatedExpectation.fulfill()
            return nil
        }

        // WHEN - Non-user-initiated popup
        let navigationAction = makeMockNavigationAction(url: URL(string: "https://popup.com")!, isUserInitiated: false)
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: navigationAction, windowFeatures: windowFeatures)

        // THEN - Popup should be created without prompting
        wait(for: [popupCreatedExpectation], timeout: 1.0)
        wait(for: [queryExpectation], timeout: 0.1)
    }

    @MainActor
    func testWhenAlwaysDenySet_ThenPopupsBlockedWithoutPrompt() {
        // GIVEN
        popupHandlingExtension = createExtension()
        testPermissionManager.setPermission(.deny, forDomain: "example.com", permissionType: .popups)

        let popupCreatedExpectation = expectation(description: "Popup not created")
        popupCreatedExpectation.isInverted = true

        childTabCreated = { _, _, _ in
            popupCreatedExpectation.fulfill() // Shouldn't happen
            return nil
        }

        // WHEN - Non-user-initiated popup
        let navigationAction = makeMockNavigationAction(url: URL(string: "https://popup.com")!, isUserInitiated: false)
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: navigationAction, windowFeatures: windowFeatures)

        // THEN - Popup should be blocked (permission denied automatically)
        wait(for: [popupCreatedExpectation], timeout: 0.5)
    }

    @MainActor
    func testWhenAlwaysAllowSet_ThenPersistsAcrossNavigations() {
        // GIVEN
        popupHandlingExtension = createExtension()
        testPermissionManager.setPermission(.allow, forDomain: "example.com", permissionType: .popups)

        let firstPopupExpectation = expectation(description: "First popup created")
        let secondPopupExpectation = expectation(description: "Second popup created")

        var popupCount = 0
        childTabCreated = { _, _, _ in
            popupCount += 1
            if popupCount == 1 {
                firstPopupExpectation.fulfill()
            } else if popupCount == 2 {
                secondPopupExpectation.fulfill()
            }
            return nil
        }

        // WHEN - First popup
        let firstAction = makeMockNavigationAction(url: URL(string: "https://popup1.com")!, isUserInitiated: false)
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: firstAction, windowFeatures: windowFeatures)

        wait(for: [firstPopupExpectation], timeout: 1.0)

        // Simulate navigation
        let navigation = Navigation(identity: NavigationIdentity(nil), responders: ResponderChain(), state: .started, isCurrent: true)
        popupHandlingExtension.willStart(navigation)

        // Second popup after navigation
        let secondAction = makeMockNavigationAction(url: URL(string: "https://popup2.com")!, isUserInitiated: false)
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: secondAction, windowFeatures: windowFeatures)

        // THEN - Both popups allowed
        wait(for: [secondPopupExpectation], timeout: 1.0)
    }
}

// MARK: - Mock Objects

class MockPopupBlockingConfiguration: PopupBlockingConfiguration {
    var userInitiatedPopupThreshold: TimeInterval = 6.0
}

class TestPermissionManager: PermissionManagerProtocol {
    var persistedPermissions: [String: [PermissionType: PersistedPermissionDecision]] = [:]

    var permissionPublisher: AnyPublisher<(domain: String, permissionType: PermissionType, decision: PersistedPermissionDecision), Never> {
        return Empty().eraseToAnyPublisher()
    }

    func hasPermissionPersisted(forDomain domain: String, permissionType: PermissionType) -> Bool {
        return persistedPermissions[domain]?[permissionType] != nil
    }

    func permission(forDomain domain: String, permissionType: PermissionType) -> PersistedPermissionDecision {
        return persistedPermissions[domain]?[permissionType] ?? .ask
    }

    func setPermission(_ decision: PersistedPermissionDecision, forDomain domain: String, permissionType: PermissionType) {
        if persistedPermissions[domain] == nil {
            persistedPermissions[domain] = [:]
        }
        persistedPermissions[domain]?[permissionType] = decision
    }

    func burnPermissions(except fireproofDomains: FireproofDomains, completion: @escaping @MainActor () -> Void) {
        MainActor.assumeMainThread {
            completion()
        }
    }

    func burnPermissions(of baseDomains: Set<String>, tld: TLD, completion: @escaping @MainActor () -> Void) {
        MainActor.assumeMainThread {
            completion()
        }
    }

    var persistedPermissionTypes: Set<PermissionType> { return [] }
}
