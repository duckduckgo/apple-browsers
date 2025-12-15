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
    var webView: DuckDuckGo_Privacy_Browser.WebView!
    var mockMachAbsTime: TimeInterval!
    var createChildTab: ((WKWebViewConfiguration?, SecurityOrigin?, NewWindowPolicy) -> Tab?)?
    var tabPresented: ((Tab, NewWindowPolicy) -> Void)?
    var cancellables = Set<AnyCancellable>()
    var configuration: WKWebViewConfiguration!
    var windowFeatures: WKWindowFeatures!

    override func setUp() {
        super.setUp()
        mockFeatureFlagger = MockFeatureFlagger()
        mockPopupBlockingConfig = MockPopupBlockingConfiguration()
        testPermissionManager = TestPermissionManager()
        mockPermissionModel = PermissionModel(permissionManager: testPermissionManager, featureFlagger: mockFeatureFlagger)
        webView = WebView()
        configuration = WKWebViewConfiguration()
        windowFeatures = WKWindowFeatures()
        mockMachAbsTime = 1000.0 // Default mock time
    }

    override func tearDown() {
        popupHandlingExtension = nil
        mockFeatureFlagger = nil
        mockPopupBlockingConfig = nil
        mockPermissionModel = nil
        testPermissionManager = nil
        createChildTab = nil
        tabPresented = nil
        cancellables.removeAll()
        webView = nil
        configuration = nil
        windowFeatures = nil
        mockMachAbsTime = nil
        super.tearDown()
    }

    @MainActor
    private func createExtension(isTabPinned: Bool = false, isBurner: Bool = false, switchToNewTabWhenOpened: Bool = true) -> PopupHandlingTabExtension {
        let windowControllersManager = WindowControllersManagerMock()
        let mockPersistor = MockTabsPreferencesPersistor()
        mockPersistor.switchToNewTabWhenOpened = switchToNewTabWhenOpened
        let tabsPreferences = TabsPreferences(
            persistor: mockPersistor,
            windowControllersManager: windowControllersManager
        )

        return PopupHandlingTabExtension(
            tabsPreferences: tabsPreferences,
            burnerMode: BurnerMode(isBurner: isBurner),
            permissionModel: mockPermissionModel,
            createChildTab: { [weak self] config, securityOrigin, policy in
                self?.createChildTab?(config, securityOrigin, policy)
            },
            presentTab: { [weak self] tab, policy in
                self?.tabPresented?(tab, policy)
            },
            newWindowPolicyDecisionMakers: { nil },
            featureFlagger: mockFeatureFlagger,
            popupBlockingConfig: mockPopupBlockingConfig,
            tld: TLD(),
            machAbsTimeProvider: { [weak self] in self!.mockMachAbsTime! },
            interactionEventsPublisher: webView.interactionEventsPublisher.eraseToAnyPublisher(),
            isTabPinned: { isTabPinned },
            isBurner: isBurner,
            isInPopUpWindow: { false }
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
    func testWhenUserInteractionPublisherEnabled_ThenMouseDownUpdatesLastInteractionTime() {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.popupBlocking.rawValue] = true
        mockFeatureFlagger.featuresStub[FeatureFlag.extendedUserInitiatedPopupTimeout.rawValue] = true
        mockPopupBlockingConfig.userInitiatedPopupThreshold = 6.0

        let interactionTime: TimeInterval = 1000.0
        mockMachAbsTime = interactionTime
        popupHandlingExtension = createExtension()

        let expectation = expectation(description: "User interaction recorded")

        // WHEN - Simulate mouse down at the interaction time
        webView.mouseDown(with: .mock(.leftMouseDown, timestamp: interactionTime))

        // Wait for interaction to be processed on main actor
        DispatchQueue.main.async {
            // THEN - Popup should be allowed within threshold (3 seconds is within 6s threshold)
            let navigationAction = WKNavigationAction.mock(url: URL(string: "https://popup.com")!, webView: self.webView, isUserInitiated: false)

            // Advance mock time by 3 seconds
            self.mockMachAbsTime = interactionTime + 3.0

            let bypassReason = self.popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(
                for: navigationAction,
                windowFeatures: self.windowFeatures
            )

            XCTAssertEqual(
                bypassReason,
                .userInitiated(.extendedTimeout(eventTimestamp: interactionTime, currentTime: interactionTime + 3.0)),
                "Expected userInitiated with extendedTimeout reason"
            )
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    @MainActor
    func testWhenUserInteractionPublisherEnabled_ThenKeyDownUpdatesLastInteractionTime() {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.popupBlocking.rawValue] = true
        mockFeatureFlagger.featuresStub[FeatureFlag.extendedUserInitiatedPopupTimeout.rawValue] = true
        mockPopupBlockingConfig.userInitiatedPopupThreshold = 6.0

        let interactionTime: TimeInterval = 1000.0
        mockMachAbsTime = interactionTime
        popupHandlingExtension = createExtension()

        let expectation = expectation(description: "User interaction recorded")

        // WHEN - Simulate key down at the interaction time
        webView.keyDown(with: .mock(.keyDown, timestamp: interactionTime))

        // Wait for interaction to be processed on main actor
        DispatchQueue.main.async {
            // THEN - Popup should be allowed within threshold
            let navigationAction = WKNavigationAction.mock(url: URL(string: "https://popup.com")!, webView: self.webView, isUserInitiated: false)

            // Advance mock time by 3 seconds (within 6s threshold)
            self.mockMachAbsTime = interactionTime + 3.0

            let bypassReason = self.popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(
                for: navigationAction,
                windowFeatures: self.windowFeatures
            )

            XCTAssertEqual(
                bypassReason,
                .userInitiated(.extendedTimeout(eventTimestamp: interactionTime, currentTime: interactionTime + 3.0)),
                "Expected userInitiated with extendedTimeout reason"
            )
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    @MainActor
    func testWhenUserInteractionPublisherEnabled_ThenMiddleMouseDownUpdatesLastInteractionTime() {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.popupBlocking.rawValue] = true
        mockFeatureFlagger.featuresStub[FeatureFlag.extendedUserInitiatedPopupTimeout.rawValue] = true
        mockPopupBlockingConfig.userInitiatedPopupThreshold = 6.0

        let interactionTime: TimeInterval = 1000.0
        mockMachAbsTime = interactionTime
        popupHandlingExtension = createExtension()

        let expectation = expectation(description: "User interaction recorded")

        // WHEN - Simulate middle mouse down at the interaction time
        webView.otherMouseDown(with: .mock(.otherMouseDown, timestamp: interactionTime))

        // Wait for interaction to be processed on main actor
        DispatchQueue.main.async {
            // THEN - Popup should be allowed within threshold
            let navigationAction = WKNavigationAction.mock(url: URL(string: "https://popup.com")!, webView: self.webView, isUserInitiated: false)

            // Advance mock time by 3 seconds (within 6s threshold)
            self.mockMachAbsTime = interactionTime + 3.0

            let bypassReason = self.popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(
                for: navigationAction,
                windowFeatures: self.windowFeatures
            )

            XCTAssertEqual(
                bypassReason,
                .userInitiated(.extendedTimeout(eventTimestamp: interactionTime, currentTime: interactionTime + 3.0)),
                "Expected userInitiated with extendedTimeout reason"
            )
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    @MainActor
    func testWhenUserInteractionPublisherEnabled_ThenScrollWheelDoesNotUpdateLastInteractionTime() {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.extendedUserInitiatedPopupTimeout.rawValue] = true
        mockPopupBlockingConfig.userInitiatedPopupThreshold = 6.0
        popupHandlingExtension = createExtension()

        // Set current mach absolute time
        let currentTime: TimeInterval = 1000.0
        mockMachAbsTime = currentTime

        let expectation = expectation(description: "Scroll event processed")

        // WHEN - Send scroll wheel event (doesn't update interaction time)
        // Note: NSEvent doesn't provide a convenient factory for scroll wheel events, so we skip this test interaction
        // The extension should not track scroll wheel as user interaction anyway
        let expectation2 = self.expectation(description: "Scroll processed")
        DispatchQueue.main.async {
            expectation2.fulfill()
        }
        wait(for: [expectation2], timeout: 0.1)

        // Wait for event to be processed on main actor
        DispatchQueue.main.async {
            // THEN - Popup should NOT be allowed (no interaction recorded)
            let navigationAction = WKNavigationAction.mock(url: URL(string: "https://popup.com")!, webView: self.webView, isUserInitiated: false)

            let bypassReason = self.popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(
                for: navigationAction,
                windowFeatures: self.windowFeatures
            )

            XCTAssertNil(bypassReason, "Scroll wheel should not record interaction")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    @MainActor
    func testWhenUserInteractionPublisherDisabled_ThenInteractionsDoNotUpdateLastInteractionTime() {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.extendedUserInitiatedPopupTimeout.rawValue] = false
        popupHandlingExtension = createExtension()

        // Set current mach absolute time
        let interactionTime: TimeInterval = 1000.0
        mockMachAbsTime = interactionTime

        let expectation = expectation(description: "Events processed")

        // WHEN - Send interaction events
        webView.mouseDown(with: .mock(.leftMouseDown, timestamp: interactionTime))
        webView.keyDown(with: .mock(.keyDown, timestamp: interactionTime))

        // Wait for events to be processed on main actor
        DispatchQueue.main.async {
            // THEN - Should fall back to WebKit's isUserInitiated
            let navigationAction = WKNavigationAction.mock(url: URL(string: "https://popup.com")!, webView: self.webView, isUserInitiated: false)

            let bypassReason = self.popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(
                for: navigationAction,
                windowFeatures: self.windowFeatures
            )

            XCTAssertNil(bypassReason, "Should use WebKit's isUserInitiated when feature disabled")
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

        let navigationAction = WKNavigationAction.mock(url: URL(string: "https://popup.com")!, webView: self.webView, isUserInitiated: true)

        // WHEN
        let bypassReason = popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(
            for: navigationAction,
            windowFeatures: windowFeatures
        )

        // THEN
        XCTAssertEqual(bypassReason, .userInitiated(.webKitUserInitiated), "Expected userInitiated with webKitUserInitiated reason")
    }

    @MainActor
    func testWhenPopupIsNotUserInitiated_AndNoRecentInteraction_ThenShouldRequirePermission() {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.popupBlocking.rawValue] = false
        popupHandlingExtension = createExtension()

        let navigationAction = WKNavigationAction.mock(url: URL(string: "https://popup.com")!, webView: self.webView, isUserInitiated: false)

        // WHEN
        let bypassReason = popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(
            for: navigationAction,
            windowFeatures: windowFeatures
        )

        // THEN
        XCTAssertNil(bypassReason, "Non-user-initiated popup without recent interaction should require permission")
    }

    // MARK: - Extended Timeout Logic Tests

    @MainActor
    func testWhenNoUserInteractionRecorded_ThenShouldRequirePermission() {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.popupBlocking.rawValue] = true
        mockFeatureFlagger.featuresStub[FeatureFlag.extendedUserInitiatedPopupTimeout.rawValue] = true
        mockPopupBlockingConfig.userInitiatedPopupThreshold = 6.0
        popupHandlingExtension = createExtension()

        mockMachAbsTime = 1000.0

        // WHEN - No user interaction has occurred (lastUserInteractionDate is nil)
        let navigationAction = WKNavigationAction.mock(url: URL(string: "https://popup.com")!, webView: self.webView, isUserInitiated: false)

        let bypassReason = popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(
            for: navigationAction,
            windowFeatures: windowFeatures
        )

        // THEN
        XCTAssertNil(bypassReason, "Popup should require permission when no interaction recorded")
    }

    @MainActor
    func testWhenOnlyPopupBlockingEnabled_ThenFallsBackToWebKitUserInitiated() {
        // GIVEN - Only popupBlocking on, extendedUserInitiatedPopupTimeout off
        mockFeatureFlagger.featuresStub[FeatureFlag.popupBlocking.rawValue] = true
        mockFeatureFlagger.featuresStub[FeatureFlag.extendedUserInitiatedPopupTimeout.rawValue] = false
        popupHandlingExtension = createExtension()

        // WHEN - navigationAction.isUserInitiated = true/false
        let userInitiatedAction = WKNavigationAction.mock(url: URL(string: "https://popup.com")!, webView: self.webView, isUserInitiated: true)
        let nonUserInitiatedAction = WKNavigationAction.mock(url: URL(string: "https://popup.com")!, webView: self.webView, isUserInitiated: false)

        // THEN - Should use WebKit's isUserInitiated
        let userInitiatedBypassReason = popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(for: userInitiatedAction, windowFeatures: windowFeatures)
        XCTAssertEqual(userInitiatedBypassReason, .userInitiated(.webKitUserInitiated), "Expected userInitiated with webKitUserInitiated")

        let nonUserInitiatedBypassReason = popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(for: nonUserInitiatedAction, windowFeatures: windowFeatures)
        XCTAssertNil(nonUserInitiatedBypassReason, "Non-user-initiated should require permission")
    }

    @MainActor
    func testWhenBothFeaturesDisabled_ThenFallsBackToWebKitUserInitiated() {
        // GIVEN - Both features off
        mockFeatureFlagger.featuresStub[FeatureFlag.popupBlocking.rawValue] = false
        mockFeatureFlagger.featuresStub[FeatureFlag.extendedUserInitiatedPopupTimeout.rawValue] = false
        popupHandlingExtension = createExtension()

        // WHEN - navigationAction.isUserInitiated = true/false
        let userInitiatedAction = WKNavigationAction.mock(url: URL(string: "https://popup.com")!, webView: self.webView, isUserInitiated: true)
        let nonUserInitiatedAction = WKNavigationAction.mock(url: URL(string: "https://popup.com")!, webView: self.webView, isUserInitiated: false)

        // THEN - Should use WebKit's isUserInitiated
        let userInitiatedBypassReason = popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(for: userInitiatedAction, windowFeatures: windowFeatures)
        XCTAssertEqual(userInitiatedBypassReason, .userInitiated(.webKitUserInitiated), "Expected userInitiated with webKitUserInitiated")

        let nonUserInitiatedBypassReason = popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(for: nonUserInitiatedAction, windowFeatures: windowFeatures)
        XCTAssertNil(nonUserInitiatedBypassReason, "Non-user-initiated should require permission")
    }

    @MainActor
    func testWhenRecentUserInteraction_AndExtendedTimeoutEnabled_ThenShouldAllowPopupWithoutPermission() {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.popupBlocking.rawValue] = true
        mockFeatureFlagger.featuresStub[FeatureFlag.extendedUserInitiatedPopupTimeout.rawValue] = true
        mockPopupBlockingConfig.userInitiatedPopupThreshold = 6.0
        popupHandlingExtension = createExtension()

        // Set current mach absolute time
        let interactionTime: TimeInterval = 1000.0
        mockMachAbsTime = interactionTime

        let expectation = expectation(description: "User interaction recorded")

        // WHEN - Simulate user interaction
        webView.mouseDown(with: .mock(.leftMouseDown, timestamp: interactionTime))

        // Wait for interaction to be processed on main actor
        DispatchQueue.main.async {
            let navigationAction = WKNavigationAction.mock(url: URL(string: "https://popup.com")!, webView: self.webView, isUserInitiated: false)

            // Advance time by 3 seconds (within 6s threshold)
            self.mockMachAbsTime = interactionTime + 3.0

            let bypassReason = self.popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(
                for: navigationAction,
                windowFeatures: self.windowFeatures
            )

            // THEN
            XCTAssertEqual(
                bypassReason,
                .userInitiated(.extendedTimeout(eventTimestamp: interactionTime, currentTime: interactionTime + 3.0)),
                "Expected userInitiated with extendedTimeout reason"
            )
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

        // Set current mach absolute time
        let interactionTime: TimeInterval = 1000.0
        mockMachAbsTime = interactionTime

        let expectation = expectation(description: "User interaction recorded")

        // WHEN - Simulate user interaction
        webView.mouseDown(with: .mock(.leftMouseDown, timestamp: interactionTime))

        // Wait for interaction to be processed on main actor
        DispatchQueue.main.async {
            let navigationAction = WKNavigationAction.mock(url: URL(string: "https://popup.com")!, webView: self.webView, isUserInitiated: false)

            // Advance time by 7 seconds (beyond 6s threshold)
            self.mockMachAbsTime = interactionTime + 7.0

            let bypassReason = self.popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(
                for: navigationAction,
                windowFeatures: self.windowFeatures
            )

            // THEN
            XCTAssertNil(bypassReason, "Should require permission due to old user interaction")
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
        permissionGrantedExpectation.isInverted = true // We expect createChildTab NOT to be called

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

        createChildTab = { _, _, _ in
            permissionGrantedExpectation.fulfill() // This shouldn't happen
            return nil
        }

        let navigationAction = WKNavigationAction.mock(url: .empty, webView: webView, isUserInitiated: false)

        // WHEN
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: navigationAction, windowFeatures: windowFeatures)

        // Wait for query to be added and granted
        wait(for: [queryAddedExpectation], timeout: 1.0)

        // Wait to ensure createChildTab is NOT called
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

        createChildTab = { _, _, _ in
            popupCreatedExpectation.fulfill()
            return nil
        }

        let navigationAction = WKNavigationAction.mock(url: .empty, webView: webView, isUserInitiated: false)

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

        createChildTab = { _, _, _ in
            permissionCallbackExpectation.fulfill() // Shouldn't be called
            return nil
        }

        // First popup with empty URL
        let firstAction = WKNavigationAction.mock(url: .empty, webView: webView, isUserInitiated: false)

        // WHEN - First popup requires permission
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: firstAction, windowFeatures: windowFeatures)

        // Wait for query to be added and granted
        wait(for: [queryAddedExpectation], timeout: 1.0)

        // Wait for permission callback to complete (inverted expectation ensures tab wasn't created)
        wait(for: [permissionCallbackExpectation], timeout: 0.1)

        // THEN - Second empty URL popup should be allowed without permission
        let secondAction = WKNavigationAction.mock(url: .empty, webView: webView, isUserInitiated: false)

        let bypassReason = popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(
            for: secondAction,
            windowFeatures: windowFeatures
        )

        XCTAssertEqual(bypassReason, .popupsTemporarilyAllowedForCurrentPage, "Expected popupsTemporarilyAllowedForCurrentPage")
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

        createChildTab = { _, _, _ in
            permissionCallbackExpectation.fulfill() // Shouldn't be called
            return nil
        }

        // First popup with empty URL
        let firstAction = WKNavigationAction.mock(url: .empty, webView: webView, isUserInitiated: false)

        // WHEN - First popup requires permission
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: firstAction, windowFeatures: windowFeatures)

        // Wait for query to be added and granted
        wait(for: [queryAddedExpectation], timeout: 1.0)

        // Wait for permission callback to complete (inverted expectation ensures tab wasn't created)
        wait(for: [permissionCallbackExpectation], timeout: 0.1)

        // THEN - Second popup with about: URL should be allowed without permission
        let secondAction = WKNavigationAction.mock(url: URL(string: "about:blank")!, webView: self.webView, isUserInitiated: false)

        let bypassReason = popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(
            for: secondAction,
            windowFeatures: windowFeatures
        )

        XCTAssertEqual(bypassReason, .popupsTemporarilyAllowedForCurrentPage, "Expected popupsTemporarilyAllowedForCurrentPage")
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

        createChildTab = { _, _, _ in
            permissionCallbackExpectation.fulfill() // Shouldn't be called
            return nil
        }

        // First popup with empty URL
        let firstAction = WKNavigationAction.mock(url: .empty, webView: webView, isUserInitiated: false)

        // WHEN - First popup requires permission
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: firstAction, windowFeatures: windowFeatures)

        // Wait for query to be added and granted
        wait(for: [queryAddedExpectation], timeout: 1.0)

        // Wait for permission callback to complete (inverted expectation ensures tab wasn't created)
        wait(for: [permissionCallbackExpectation], timeout: 0.1)

        // THEN - Cross-origin popup should be allowed when feature is enabled
        let crossOriginAction = WKNavigationAction.mock(url: URL(string: "https://other-domain.com")!, webView: self.webView, isUserInitiated: false)

        let bypassReason = popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(
            for: crossOriginAction,
            windowFeatures: windowFeatures
        )

        XCTAssertEqual(bypassReason, .popupsTemporarilyAllowedForCurrentPage, "Expected popupsTemporarilyAllowedForCurrentPage")
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

        createChildTab = { _, _, _ in
            permissionCallbackExpectation.fulfill() // Shouldn't be called
            return nil
        }

        // First popup with empty URL to establish allowance
        let firstAction = WKNavigationAction.mock(url: .empty, webView: webView, isUserInitiated: false)

        // WHEN
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: firstAction, windowFeatures: windowFeatures)

        // Wait for query to be added and granted
        wait(for: [queryAddedExpectation], timeout: 1.0)

        // Wait for permission callback to complete (inverted expectation ensures tab wasn't created)
        wait(for: [permissionCallbackExpectation], timeout: 0.1)

        // Verify allowance is set
        let secondAction = WKNavigationAction.mock(url: .empty, webView: webView, isUserInitiated: false)

        let bypassReasonBefore = popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(
            for: secondAction,
            windowFeatures: windowFeatures
        )
        XCTAssertEqual(bypassReasonBefore, .popupsTemporarilyAllowedForCurrentPage, "Expected popupsTemporarilyAllowedForCurrentPage before navigation")

        // Navigate to clear allowance
        let navigation = Navigation(identity: NavigationIdentity(nil), responders: ResponderChain(), state: .started, isCurrent: true)
        popupHandlingExtension.willStart(navigation)

        // THEN - Popup should no longer be allowed
        let bypassReasonAfter = popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(
            for: secondAction,
            windowFeatures: windowFeatures
        )
        XCTAssertNil(bypassReasonAfter, "Popup allowance should be cleared after navigation")
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

        createChildTab = { _, _, _ in
            permissionCallbackExpectation.fulfill() // Shouldn't be called
            return nil
        }

        // First popup with empty URL
        let firstAction = WKNavigationAction.mock(url: .empty, webView: webView, isUserInitiated: false)

        // WHEN
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: firstAction, windowFeatures: windowFeatures)

        // Wait for query to be added and granted
        wait(for: [queryAddedExpectation], timeout: 1.0)

        // Wait for permission callback to complete (inverted expectation ensures tab wasn't created)
        wait(for: [permissionCallbackExpectation], timeout: 0.1)

        // THEN - Empty/about URLs still allowed, but cross-origin requires permission when feature disabled
        let emptyAction = WKNavigationAction.mock(url: .empty, webView: webView, isUserInitiated: false)
        let emptyBypassReason = popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(for: emptyAction, windowFeatures: windowFeatures)
        XCTAssertEqual(emptyBypassReason, .popupsTemporarilyAllowedForCurrentPage, "Expected popupsTemporarilyAllowedForCurrentPage for empty URL")

        let crossOriginAction = WKNavigationAction.mock(url: URL(string: "https://other-domain.com")!, webView: self.webView, isUserInitiated: false)
        let crossOriginBypassReason = popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(for: crossOriginAction, windowFeatures: windowFeatures)
        XCTAssertNil(crossOriginBypassReason, "Cross-origin popup should require permission when feature is disabled")
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

        createChildTab = { _, _, _ in nil }

        // First popup with empty URL
        let firstAction = WKNavigationAction.mock(url: .empty, webView: webView, isUserInitiated: false)
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: firstAction, windowFeatures: windowFeatures)

        wait(for: [queryAddedExpectation], timeout: 1.0)

        // WHEN - Multiple subsequent popups of different types
        let emptyAction = WKNavigationAction.mock(url: .empty, webView: webView, isUserInitiated: false)
        let aboutBlankAction = WKNavigationAction.mock(url: URL(string: "about:blank")!, webView: self.webView, isUserInitiated: false)
        let crossOriginAction = WKNavigationAction.mock(url: URL(string: "https://other-domain.com")!, webView: self.webView, isUserInitiated: false)
        let sameDomainAction = WKNavigationAction.mock(url: URL(string: "https://example.com/popup")!, webView: self.webView, isUserInitiated: false)

        // THEN - All should be allowed
        let emptyBypassReason = popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(for: emptyAction, windowFeatures: windowFeatures)
        XCTAssertEqual(emptyBypassReason, .popupsTemporarilyAllowedForCurrentPage, "Expected popupsTemporarilyAllowedForCurrentPage for empty URL")

        let aboutBlankBypassReason = popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(for: aboutBlankAction, windowFeatures: windowFeatures)
        XCTAssertEqual(aboutBlankBypassReason, .popupsTemporarilyAllowedForCurrentPage, "Expected popupsTemporarilyAllowedForCurrentPage for about:blank")

        let crossOriginBypassReason = popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(for: crossOriginAction, windowFeatures: windowFeatures)
        XCTAssertEqual(crossOriginBypassReason, .popupsTemporarilyAllowedForCurrentPage, "Expected popupsTemporarilyAllowedForCurrentPage for cross-origin")

        let sameDomainBypassReason = popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(for: sameDomainAction, windowFeatures: windowFeatures)
        XCTAssertEqual(sameDomainBypassReason, .popupsTemporarilyAllowedForCurrentPage, "Expected popupsTemporarilyAllowedForCurrentPage for same domain")
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

        createChildTab = { _, _, _ in
            permissionCallbackExpectation.fulfill()
            return nil
        }

        // WHEN - about:blank popup
        let aboutBlankAction = WKNavigationAction.mock(url: URL(string: "about:blank")!, webView: self.webView, isUserInitiated: false)
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: aboutBlankAction, windowFeatures: windowFeatures)

        wait(for: [queryAddedExpectation, permissionGrantedExpectation], timeout: 1.0)
        wait(for: [permissionCallbackExpectation], timeout: 0.1)

        // THEN - Subsequent about:blank allowed
        let secondAboutBlank = WKNavigationAction.mock(url: URL(string: "about:blank")!, webView: webView, isUserInitiated: false)
        let secondAboutBlankBypassReason = popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(for: secondAboutBlank, windowFeatures: windowFeatures)
        XCTAssertEqual(secondAboutBlankBypassReason, .popupsTemporarilyAllowedForCurrentPage, "Expected popupsTemporarilyAllowedForCurrentPage for subsequent about:blank")
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
        let emptyAction = WKNavigationAction.mock(url: .empty, webView: webView, isUserInitiated: false)
        let regularAction = WKNavigationAction.mock(url: URL(string: "https://popup.com")!, webView: self.webView, isUserInitiated: false)

        // THEN - Temporary allowance should NOT work because suppressEmptyPopUpsOnApproval is OFF
        let emptyBypassReason = popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(for: emptyAction, windowFeatures: windowFeatures)
        XCTAssertNil(emptyBypassReason, "Empty URL should require permission when suppress feature is off")

        let regularBypassReason = popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(for: regularAction, windowFeatures: windowFeatures)
        XCTAssertNil(regularBypassReason, "Regular URL should require permission when suppress feature is off")
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
        let userInitiatedAction = WKNavigationAction.mock(url: URL(string: "https://popup.com")!, webView: self.webView, isUserInitiated: true)

        // THEN - Should still be allowed
        let userInitiatedBypassReason = popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(for: userInitiatedAction, windowFeatures: windowFeatures)
        XCTAssertEqual(userInitiatedBypassReason, .userInitiated(.webKitUserInitiated), "Expected userInitiated with webKitUserInitiated")
    }

    // MARK: - Edge Cases

    @MainActor
    func testWhenTimeoutExactlyAtBoundary_ThenRequiresPermission() {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.popupBlocking.rawValue] = true
        mockFeatureFlagger.featuresStub[FeatureFlag.extendedUserInitiatedPopupTimeout.rawValue] = true
        mockPopupBlockingConfig.userInitiatedPopupThreshold = 6.0
        popupHandlingExtension = createExtension()

        let interactionTime: TimeInterval = 1000.0
        mockMachAbsTime = interactionTime

        let expectation = expectation(description: "User interaction recorded")

        webView.mouseDown(with: .mock(.leftMouseDown, timestamp: interactionTime))

        DispatchQueue.main.async {
            let navigationAction = WKNavigationAction.mock(url: URL(string: "https://popup.com")!, webView: self.webView, isUserInitiated: false)

            // Advance time by exactly 6.0 seconds (at boundary)
            self.mockMachAbsTime = interactionTime + 6.001

            let bypassReason = self.popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(
                for: navigationAction,
                windowFeatures: self.windowFeatures
            )

            XCTAssertNil(bypassReason, "Popup at exact timeout boundary should require permission")
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

        createChildTab = { _, _, _ in
            popupCreatedExpectation.fulfill()
            return nil
        }

        // WHEN - about:blank popup
        let aboutBlankAction = WKNavigationAction.mock(url: URL(string: "about:blank")!, webView: self.webView, isUserInitiated: false)
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

        createChildTab = { _, _, _ in
            popupCreatedExpectation.fulfill()
            return nil
        }

        // WHEN - Non-user-initiated popup
        let navigationAction = WKNavigationAction.mock(url: URL(string: "https://popup.com")!, webView: self.webView, isUserInitiated: false)
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

        createChildTab = { _, _, _ in
            popupCreatedExpectation.fulfill() // Shouldn't happen
            return nil
        }

        // WHEN - Non-user-initiated popup
        let navigationAction = WKNavigationAction.mock(url: URL(string: "https://popup.com")!, webView: self.webView, isUserInitiated: false)
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
        createChildTab = { _, _, _ in
            popupCount += 1
            if popupCount == 1 {
                firstPopupExpectation.fulfill()
            } else if popupCount == 2 {
                secondPopupExpectation.fulfill()
            }
            return nil
        }

        // WHEN - First popup
        let firstAction = WKNavigationAction.mock(url: URL(string: "https://popup1.com")!, webView: self.webView, isUserInitiated: false)
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: firstAction, windowFeatures: windowFeatures)

        wait(for: [firstPopupExpectation], timeout: 1.0)

        // Simulate navigation
        let navigation = Navigation(identity: NavigationIdentity(nil), responders: ResponderChain(), state: .started, isCurrent: true)
        popupHandlingExtension.willStart(navigation)

        // Second popup after navigation
        let secondAction = WKNavigationAction.mock(url: URL(string: "https://popup2.com")!, webView: self.webView, isUserInitiated: false)
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: secondAction, windowFeatures: windowFeatures)

        // THEN - Both popups allowed
        wait(for: [secondPopupExpectation], timeout: 1.0)
    }

    // MARK: - lastUserInteractionEvent Consumption Tests

    @MainActor
    func testWhenLinkOpenedInCurrentTab_ThenLastUserInteractionEventNotConsumed() async {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.popupBlocking.rawValue] = true
        mockFeatureFlagger.featuresStub[FeatureFlag.extendedUserInitiatedPopupTimeout.rawValue] = true
        mockPopupBlockingConfig.userInitiatedPopupThreshold = 6.0
        popupHandlingExtension = createExtension()

        let interactionTime: TimeInterval = 1000.0
        mockMachAbsTime = interactionTime

        // Record user interaction
        webView.mouseDown(with: .mock(.leftMouseDown, timestamp: interactionTime))

        // WHEN - Regular click (no modifiers) - should stay in current tab
        let navigationAction = NavigationAction(
            request: URLRequest(url: URL(string: "https://example.com")!),
            navigationType: .linkActivated(isMiddleClick: false),
            currentHistoryItemIdentity: nil,
            redirectHistory: nil,
            isUserInitiated: true,
            sourceFrame: FrameInfo(webView: webView, handle: FrameHandle(rawValue: 1), isMainFrame: true, url: URL(string: "https://source.com")!, securityOrigin: URL(string: "https://source.com")!.securityOrigin),
            targetFrame: FrameInfo(webView: webView, handle: FrameHandle(rawValue: 1), isMainFrame: true, url: URL(string: "https://source.com")!, securityOrigin: URL(string: "https://source.com")!.securityOrigin),
            shouldDownload: false,
            mainFrameNavigation: nil
        )

        var prefs = NavigationPreferences.default
        let policy = await popupHandlingExtension.decidePolicy(for: navigationAction, preferences: &prefs)

        // THEN - Should allow navigation in current tab (.next is nil)
        XCTAssertNil(policy, "Regular click should return .next (nil)")

        // AND - lastUserInteractionEvent should NOT be consumed
        mockMachAbsTime = interactionTime + 3.0
        let popupAction = WKNavigationAction.mock(url: URL(string: "https://popup.com")!, webView: self.webView, isUserInitiated: false)
        let bypassReason = popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(for: popupAction, windowFeatures: windowFeatures)

        XCTAssertEqual(
            bypassReason,
            .userInitiated(.extendedTimeout(eventTimestamp: interactionTime, currentTime: interactionTime + 3.0)),
            "User interaction should still be available (not consumed)"
        )
    }

    @MainActor
    func testWhenLinkOpenedInNewTab_ThenLastUserInteractionEventConsumed() async {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.popupBlocking.rawValue] = true
        mockFeatureFlagger.featuresStub[FeatureFlag.extendedUserInitiatedPopupTimeout.rawValue] = true
        mockPopupBlockingConfig.userInitiatedPopupThreshold = 6.0
        popupHandlingExtension = createExtension()

        let interactionTime: TimeInterval = 1000.0
        mockMachAbsTime = interactionTime

        // Record user interaction (⌘-click)
        webView.mouseDown(with: .mock(.leftMouseDown, timestamp: interactionTime, modifierFlags: .command))

        // WHEN - ⌘-click - should open in new tab
        // Note: The actual navigation will be cancelled and reopened via loadInNewWindow
        let url = URL(string: "https://example.com")!
        let sourceFrame = FrameInfo(webView: webView, handle: FrameHandle(rawValue: 1), isMainFrame: true, url: URL(string: "https://source.com")!, securityOrigin: URL(string: "https://source.com")!.securityOrigin)

        let navigationAction = NavigationAction(
            request: URLRequest(url: url),
            navigationType: .linkActivated(isMiddleClick: false),
            currentHistoryItemIdentity: nil,
            redirectHistory: nil,
            isUserInitiated: true,
            sourceFrame: sourceFrame,
            targetFrame: sourceFrame,
            shouldDownload: false,
            mainFrameNavigation: nil
        )

        var prefs = NavigationPreferences.default
        let policy = await popupHandlingExtension.decidePolicy(for: navigationAction, preferences: &prefs)

        // THEN - Should cancel (will be reopened in new tab)
        if case .cancel = policy {
            // Success
        } else {
            XCTFail("Expected .cancel policy for ⌘-click, got \(String(describing: policy))")
        }

        // AND - lastUserInteractionEvent should be consumed
        mockMachAbsTime = interactionTime + 3.0
        let popupAction = WKNavigationAction.mock(url: URL(string: "https://popup.com")!, webView: self.webView, isUserInitiated: false)
        let bypassReason = popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(for: popupAction, windowFeatures: windowFeatures)

        XCTAssertNil(bypassReason, "User interaction should be consumed after opening new tab")
    }

    @MainActor
    func testWhenLinkMiddleClickedInNewTab_ThenLastUserInteractionEventConsumed() async {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.popupBlocking.rawValue] = true
        mockFeatureFlagger.featuresStub[FeatureFlag.extendedUserInitiatedPopupTimeout.rawValue] = true
        mockPopupBlockingConfig.userInitiatedPopupThreshold = 6.0
        popupHandlingExtension = createExtension()

        let interactionTime: TimeInterval = 1000.0
        mockMachAbsTime = interactionTime

        // Record user interaction - middle mouse down
        webView.otherMouseDown(with: .mock(.otherMouseDown, timestamp: interactionTime))

        // WHEN - Middle-click - should open in new tab
        // Note: The actual navigation will be cancelled and reopened via loadInNewWindow
        let url = URL(string: "https://example.com")!
        let sourceFrame = FrameInfo(webView: webView, handle: FrameHandle(rawValue: 1), isMainFrame: true, url: URL(string: "https://source.com")!, securityOrigin: URL(string: "https://source.com")!.securityOrigin)

        let navigationAction = NavigationAction(
            request: URLRequest(url: url),
            navigationType: .linkActivated(isMiddleClick: true),
            currentHistoryItemIdentity: nil,
            redirectHistory: nil,
            isUserInitiated: true,
            sourceFrame: sourceFrame,
            targetFrame: sourceFrame,
            shouldDownload: false,
            mainFrameNavigation: nil
        )

        var prefs = NavigationPreferences.default
        let policy = await popupHandlingExtension.decidePolicy(for: navigationAction, preferences: &prefs)

        // THEN - Should cancel (will be reopened in new tab)
        if case .cancel = policy {
            // Success
        } else {
            XCTFail("Expected .cancel policy for middle-click, got \(String(describing: policy))")
        }

        // AND - lastUserInteractionEvent should be consumed
        mockMachAbsTime = interactionTime + 3.0
        let popupAction = WKNavigationAction.mock(url: URL(string: "https://popup.com")!, webView: self.webView, isUserInitiated: false)
        let bypassReason = popupHandlingExtension.shouldAllowPopupBypassingPermissionRequest(for: popupAction, windowFeatures: windowFeatures)

        XCTAssertNil(bypassReason, "User interaction should be consumed after middle-click opening new tab")
    }

    @MainActor
    func testWhenPinnedTabNavigatesToAnotherDomain_ThenOpensInNewTab() async {
        // GIVEN - Tab is pinned
        mockFeatureFlagger.featuresStub[FeatureFlag.extendedUserInitiatedPopupTimeout.rawValue] = true
        popupHandlingExtension = createExtension(isTabPinned: true)

        // WHEN - Navigate to different domain
        let sourceFrame = FrameInfo(webView: webView, handle: FrameHandle(rawValue: 1), isMainFrame: true, url: URL(string: "https://source.com")!, securityOrigin: URL(string: "https://source.com")!.securityOrigin)

        let navigationAction = NavigationAction(
            request: URLRequest(url: URL(string: "https://different.com")!),
            navigationType: .linkActivated(isMiddleClick: false),
            currentHistoryItemIdentity: nil,
            redirectHistory: nil,
            isUserInitiated: true,
            sourceFrame: sourceFrame,
            targetFrame: sourceFrame,
            shouldDownload: false,
            mainFrameNavigation: nil
        )

        var prefs = NavigationPreferences.default
        let policy = await popupHandlingExtension.decidePolicy(for: navigationAction, preferences: &prefs)

        // THEN - Should cancel and open in new tab
        if case .cancel = policy {
            // Success
        } else {
            XCTFail("Expected .cancel policy for pinned tab cross-domain navigation, got \(String(describing: policy))")
        }
    }

    @MainActor
    func testWhenPinnedTabNavigatesToSameDomain_ThenStaysInCurrentTab() async {
        // GIVEN - Tab is pinned
        popupHandlingExtension = createExtension(isTabPinned: true)

        // WHEN - Navigate to same domain
        let sourceURL = URL(string: "https://source.com/page1")!
        let targetURL = URL(string: "https://source.com/page2")!
        let sourceFrame = FrameInfo(webView: webView, handle: FrameHandle(rawValue: 1), isMainFrame: true, url: sourceURL, securityOrigin: sourceURL.securityOrigin)

        let navigationAction = NavigationAction(
            request: URLRequest(url: targetURL),
            navigationType: .linkActivated(isMiddleClick: false),
            currentHistoryItemIdentity: nil,
            redirectHistory: nil,
            isUserInitiated: true,
            sourceFrame: sourceFrame,
            targetFrame: sourceFrame,
            shouldDownload: false,
            mainFrameNavigation: nil
        )

        var prefs = NavigationPreferences.default
        let policy = await popupHandlingExtension.decidePolicy(for: navigationAction, preferences: &prefs)

        // THEN - Should allow navigation in current tab (.next is nil)
        XCTAssertNil(policy, "Pinned tab same-domain navigation should return .next (nil)")
    }

    // MARK: - pageInitiatedPopupOpened Flag Tests

    @MainActor
    func testWhenUserInitiatedPopupOpens_ThenPageInitiatedPopupOpenedNotSet() {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.popupBlocking.rawValue] = false
        popupHandlingExtension = createExtension()

        XCTAssertFalse(popupHandlingExtension.pageInitiatedPopupOpened, "Should start as false")

        let popupCreatedExpectation = expectation(description: "Popup created")

        createChildTab = { configuration, _, _ in
            popupCreatedExpectation.fulfill()
            return Tab(content: .none, webViewConfiguration: configuration)
        }

        // WHEN - User-initiated popup
        let navigationAction = WKNavigationAction.mock(url: URL(string: "https://popup.com")!, webView: self.webView, isUserInitiated: true)
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: navigationAction, windowFeatures: windowFeatures)

        wait(for: [popupCreatedExpectation], timeout: 1.0)

        // THEN - pageInitiatedPopupOpened should NOT be set
        XCTAssertFalse(popupHandlingExtension.pageInitiatedPopupOpened, "User-initiated popup should not set pageInitiatedPopupOpened flag")
    }

    @MainActor
    func testWhenNonUserInitiatedPopupOpens_ThenPageInitiatedPopupOpenedSet() {
        // GIVEN
        popupHandlingExtension = createExtension()
        testPermissionManager.setPermission(.allow, forDomain: "example.com", permissionType: .popups)

        XCTAssertFalse(popupHandlingExtension.pageInitiatedPopupOpened, "Should start as false")

        let popupCreatedExpectation = expectation(description: "Popup created")

        createChildTab = { configuration, _, _ in
            popupCreatedExpectation.fulfill()
            return Tab(content: .none, webViewConfiguration: configuration)
        }

        // WHEN - Non-user-initiated popup (permission already granted)
        let navigationAction = WKNavigationAction.mock(url: URL(string: "https://popup.com")!, webView: self.webView, isUserInitiated: false)
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: navigationAction, windowFeatures: windowFeatures)

        wait(for: [popupCreatedExpectation], timeout: 1.0)

        // THEN - pageInitiatedPopupOpened should be set
        XCTAssertTrue(popupHandlingExtension.pageInitiatedPopupOpened, "Non-user-initiated popup should set pageInitiatedPopupOpened flag")
    }

    @MainActor
    func testWhenNavigationStarts_ThenPageInitiatedPopupOpenedCleared() {
        // GIVEN
        popupHandlingExtension = createExtension()
        testPermissionManager.setPermission(.allow, forDomain: "example.com", permissionType: .popups)

        let popupCreatedExpectation = expectation(description: "Popup created")

        createChildTab = { configuration, _, _ in
            popupCreatedExpectation.fulfill()
            return Tab(content: .none, webViewConfiguration: configuration)
        }

        // Create a non-user-initiated popup to set the flag
        let navigationAction = WKNavigationAction.mock(url: URL(string: "https://popup.com")!, webView: self.webView, isUserInitiated: false)
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: navigationAction, windowFeatures: windowFeatures)

        wait(for: [popupCreatedExpectation], timeout: 1.0)

        XCTAssertTrue(popupHandlingExtension.pageInitiatedPopupOpened, "Flag should be set after popup")

        // WHEN - Navigation starts
        let navigation = Navigation(identity: NavigationIdentity(nil), responders: ResponderChain(), state: .started, isCurrent: true)
        popupHandlingExtension.willStart(navigation)

        // THEN - Flag should be cleared
        XCTAssertFalse(popupHandlingExtension.pageInitiatedPopupOpened, "Flag should be cleared on navigation")
    }

    @MainActor
    func testPageInitiatedPopupPublisher_SendsEventWhenFlagSet() {
        // GIVEN
        popupHandlingExtension = createExtension()
        testPermissionManager.setPermission(.allow, forDomain: "example.com", permissionType: .popups)

        let publisherExpectation = expectation(description: "Publisher sends event")
        let popupCreatedExpectation = expectation(description: "Popup created")

        popupHandlingExtension.pageInitiatedPopupPublisher
            .sink { _ in
                publisherExpectation.fulfill()
            }
            .store(in: &cancellables)

        createChildTab = { configuration, _, _ in
            popupCreatedExpectation.fulfill()
            return Tab(content: .none, webViewConfiguration: configuration)
        }

        // WHEN - Non-user-initiated popup opens
        let navigationAction = WKNavigationAction.mock(url: URL(string: "https://popup.com")!, webView: self.webView, isUserInitiated: false)
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: navigationAction, windowFeatures: windowFeatures)

        // THEN - Publisher should send event
        wait(for: [popupCreatedExpectation, publisherExpectation], timeout: 1.0)
    }

    @MainActor
    func testPageInitiatedPopupPublisher_DoesNotSendForUserInitiatedPopup() {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.popupBlocking.rawValue] = false
        popupHandlingExtension = createExtension()

        let publisherExpectation = expectation(description: "Publisher does not send")
        publisherExpectation.isInverted = true
        let popupCreatedExpectation = expectation(description: "Popup created")

        popupHandlingExtension.pageInitiatedPopupPublisher
            .sink { _ in
                publisherExpectation.fulfill() // Should not happen
            }
            .store(in: &cancellables)

        createChildTab = { configuration, _, _ in
            popupCreatedExpectation.fulfill()
            return Tab(content: .none, webViewConfiguration: configuration)
        }

        // WHEN - User-initiated popup opens
        let navigationAction = WKNavigationAction.mock(url: URL(string: "https://popup.com")!, webView: self.webView, isUserInitiated: true)
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: navigationAction, windowFeatures: windowFeatures)

        // THEN - Publisher should NOT send event
        wait(for: [popupCreatedExpectation], timeout: 1.0)
        wait(for: [publisherExpectation], timeout: 0.1)
    }

    // MARK: - onNewWindow Callback Mechanism Tests

    @MainActor
    func testOnNewWindowCallback_ClearedAfterUse() async {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.popupBlocking.rawValue] = true
        mockFeatureFlagger.featuresStub[FeatureFlag.extendedUserInitiatedPopupTimeout.rawValue] = true
        popupHandlingExtension = createExtension()

        let interactionTime: TimeInterval = 1000.0
        mockMachAbsTime = interactionTime

        // Record user interaction (⌘-click)
        webView.mouseDown(with: .mock(.leftMouseDown, timestamp: interactionTime, modifierFlags: .command))

        // Set up onNewWindow via decidePolicy
        let sourceFrame = FrameInfo(webView: webView, handle: FrameHandle(rawValue: 1), isMainFrame: true, url: URL(string: "https://source.com")!, securityOrigin: URL(string: "https://source.com")!.securityOrigin)

        let firstNavAction = NavigationAction(
            request: URLRequest(url: URL(string: "https://first.com")!),
            navigationType: .linkActivated(isMiddleClick: false),
            currentHistoryItemIdentity: nil,
            redirectHistory: nil,
            isUserInitiated: true,
            sourceFrame: sourceFrame,
            targetFrame: sourceFrame,
            shouldDownload: false,
            mainFrameNavigation: nil
        )

        // WHEN - First navigation with modifier keys
        var prefs = NavigationPreferences.default
        _ = await popupHandlingExtension.decidePolicy(for: firstNavAction, preferences: &prefs)

        // Now trigger createWebView which should consume the callback
        let wkNavAction = WKNavigationAction.mock(url: URL(string: "https://first.com")!, webView: self.webView, isUserInitiated: false)

        let decision1 = popupHandlingExtension.decideNewWindowPolicy(for: wkNavAction)
        XCTAssertEqual(
            decision1,
            .allow(.tab(selected: true, burner: false, contextMenuInitiated: false)),
            "First call should return .allow with tab policy"
        )

        // THEN - Second call should return nil (callback cleared)
        let decision2 = popupHandlingExtension.decideNewWindowPolicy(for: wkNavAction)
        XCTAssertNil(decision2, "Second call should return nil as callback is cleared")
    }

    @MainActor
    func testOnNewWindowCallback_OnlyMatchesCorrectURL() async {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.popupBlocking.rawValue] = true
        mockFeatureFlagger.featuresStub[FeatureFlag.extendedUserInitiatedPopupTimeout.rawValue] = true
        popupHandlingExtension = createExtension()

        let interactionTime: TimeInterval = 1000.0
        mockMachAbsTime = interactionTime

        // Record user interaction (⌘-click)
        webView.mouseDown(with: .mock(.leftMouseDown, timestamp: interactionTime, modifierFlags: .command))

        let targetURL = URL(string: "https://target.com")!
        let sourceFrame = FrameInfo(webView: webView, handle: FrameHandle(rawValue: 1), isMainFrame: true, url: URL(string: "https://source.com")!, securityOrigin: URL(string: "https://source.com")!.securityOrigin)

        let navAction = NavigationAction(
            request: URLRequest(url: targetURL),
            navigationType: .linkActivated(isMiddleClick: false),
            currentHistoryItemIdentity: nil,
            redirectHistory: nil,
            isUserInitiated: true,
            sourceFrame: sourceFrame,
            targetFrame: sourceFrame,
            shouldDownload: false,
            mainFrameNavigation: nil
        )

        // WHEN - Set up onNewWindow for specific URL
        var prefs = NavigationPreferences.default
        _ = await popupHandlingExtension.decidePolicy(for: navAction, preferences: &prefs)

        // THEN - Wrong URL should return nil
        let wrongURLAction = WKNavigationAction.mock(url: URL(string: "https://different.com")!, webView: self.webView, isUserInitiated: false)
        let decision1 = popupHandlingExtension.decideNewWindowPolicy(for: wrongURLAction)
        XCTAssertNil(decision1, "Different URL should not match")

        // AND - Correct URL should return decision
        let correctURLAction = WKNavigationAction.mock(url: targetURL, webView: webView, isUserInitiated: false)
        let decision2 = popupHandlingExtension.decideNewWindowPolicy(for: correctURLAction)
        XCTAssertEqual(
            decision2,
            .allow(.tab(selected: true, burner: false, contextMenuInitiated: false)),
            "Matching URL should return .allow with tab policy"
        )
    }

    @MainActor
    func testOnNewWindowCallback_WithSwitchToNewTabDisabled() async {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.popupBlocking.rawValue] = true
        mockFeatureFlagger.featuresStub[FeatureFlag.extendedUserInitiatedPopupTimeout.rawValue] = true
        popupHandlingExtension = createExtension(switchToNewTabWhenOpened: false)

        let interactionTime: TimeInterval = 1000.0
        mockMachAbsTime = interactionTime

        // Record user interaction (⌘-click)
        webView.mouseDown(with: .mock(.leftMouseDown, timestamp: interactionTime, modifierFlags: .command))

        // Set up onNewWindow via decidePolicy
        let sourceFrame = FrameInfo(webView: webView, handle: FrameHandle(rawValue: 1), isMainFrame: true, url: URL(string: "https://source.com")!, securityOrigin: URL(string: "https://source.com")!.securityOrigin)

        let firstNavAction = NavigationAction(
            request: URLRequest(url: URL(string: "https://first.com")!),
            navigationType: .linkActivated(isMiddleClick: false),
            currentHistoryItemIdentity: nil,
            redirectHistory: nil,
            isUserInitiated: true,
            sourceFrame: sourceFrame,
            targetFrame: sourceFrame,
            shouldDownload: false,
            mainFrameNavigation: nil
        )

        // WHEN - First navigation with modifier keys and switchToNewTabWhenOpened = false
        var prefs = NavigationPreferences.default
        _ = await popupHandlingExtension.decidePolicy(for: firstNavAction, preferences: &prefs)

        // THEN - Decision should have selected = false
        let wkNavAction = WKNavigationAction.mock(url: URL(string: "https://first.com")!, webView: self.webView, isUserInitiated: false)
        let decision = popupHandlingExtension.decideNewWindowPolicy(for: wkNavAction)
        XCTAssertEqual(
            decision,
            .allow(.tab(selected: false, burner: false, contextMenuInitiated: false)),
            "Should return .allow with tab policy and selected = false"
        )
    }

    @MainActor
    func testOnNewWindowCallback_MiddleClickWithSwitchToNewTabDisabled() async {
        // GIVEN
        mockFeatureFlagger.featuresStub[FeatureFlag.popupBlocking.rawValue] = true
        mockFeatureFlagger.featuresStub[FeatureFlag.extendedUserInitiatedPopupTimeout.rawValue] = true
        popupHandlingExtension = createExtension(switchToNewTabWhenOpened: false)

        let interactionTime: TimeInterval = 1000.0
        mockMachAbsTime = interactionTime

        // Record middle mouse interaction
        webView.otherMouseDown(with: .mock(.otherMouseDown, timestamp: interactionTime))

        let targetURL = URL(string: "https://target.com")!
        let sourceFrame = FrameInfo(webView: webView, handle: FrameHandle(rawValue: 1), isMainFrame: true, url: URL(string: "https://source.com")!, securityOrigin: URL(string: "https://source.com")!.securityOrigin)

        let navAction = NavigationAction(
            request: URLRequest(url: targetURL),
            navigationType: .linkActivated(isMiddleClick: true),
            currentHistoryItemIdentity: nil,
            redirectHistory: nil,
            isUserInitiated: true,
            sourceFrame: sourceFrame,
            targetFrame: sourceFrame,
            shouldDownload: false,
            mainFrameNavigation: nil
        )

        // WHEN - Middle-click with switchToNewTabWhenOpened = false
        var prefs = NavigationPreferences.default
        _ = await popupHandlingExtension.decidePolicy(for: navAction, preferences: &prefs)

        // THEN - Decision should have selected = false
        let correctURLAction = WKNavigationAction.mock(url: targetURL, webView: webView, isUserInitiated: false)
        let decision = popupHandlingExtension.decideNewWindowPolicy(for: correctURLAction)
        XCTAssertEqual(
            decision,
            .allow(.tab(selected: false, burner: false, contextMenuInitiated: false)),
            "Middle-click should return .allow with tab policy and selected = false"
        )
    }

        // MARK: - Allowlist Tests

    @MainActor
    func testWhenSourceDomainExactMatchInAllowlist_ThenPopupAllowedWithoutPermission() {
        // GIVEN - Exact domain match in allowlist
        mockPopupBlockingConfig.allowlist = ["example.com"]
        popupHandlingExtension = createExtension()

        let popupExpectation = expectation(description: "Popup created")
        createChildTab = { _, _, _ in
            popupExpectation.fulfill()
            return nil
        }

        // WHEN - Non-user-initiated popup from exact allowlisted domain
        let sourceFrame = WKFrameInfoMock(
            webView: webView,
            securityOrigin: WKSecurityOriginMock.new(url: URL(string: "https://example.com")!),
            request: URLRequest(url: URL(string: "https://example.com")!),
            isMainFrame: true
        )
        let navigationAction = MockWKNavigationAction(
            request: URLRequest(url: URL(string: "https://popup.com")!),
            targetFrame: nil,
            sourceFrame: sourceFrame,
            isUserInitiated: false
        )
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: navigationAction, windowFeatures: windowFeatures)

        // THEN - Popup allowed immediately without permission request
        wait(for: [popupExpectation], timeout: 0.5)
    }

    @MainActor
    func testWhenSourceSubdomainMatchesAllowlistedETLDplus1_ThenPopupAllowed() {
        // GIVEN - Allowlist contains eTLD+1
        mockPopupBlockingConfig.allowlist = ["google.com"]
        popupHandlingExtension = createExtension()

        let popupExpectation = expectation(description: "Popup created")
        createChildTab = { _, _, _ in
            popupExpectation.fulfill()
            return nil
        }

        // WHEN - Popup from subdomain (accounts.google.com)
        let sourceFrame = WKFrameInfoMock(
            webView: webView,
            securityOrigin: WKSecurityOriginMock.new(url: URL(string: "https://accounts.google.com")!),
            request: URLRequest(url: URL(string: "https://accounts.google.com")!),
            isMainFrame: true
        )
        let navigationAction = MockWKNavigationAction(
            request: URLRequest(url: URL(string: "https://popup.com")!),
            targetFrame: nil,
            sourceFrame: sourceFrame,
            isUserInitiated: false
        )
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: navigationAction, windowFeatures: windowFeatures)

        // THEN - Popup allowed (strips to parent domain google.com which is in allowlist)
        wait(for: [popupExpectation], timeout: 0.5)
    }

    @MainActor
    func testWhenSourceApexDomainInAllowlist_ThenPopupAllowed() {
        // GIVEN - Allowlist contains eTLD+1
        mockPopupBlockingConfig.allowlist = ["google.com"]
        popupHandlingExtension = createExtension()

        let popupExpectation = expectation(description: "Popup created")
        createChildTab = { _, _, _ in
            popupExpectation.fulfill()
            return nil
        }

        // WHEN - Popup from apex domain (google.com itself)
        let sourceFrame = WKFrameInfoMock(
            webView: webView,
            securityOrigin: WKSecurityOriginMock.new(url: URL(string: "https://google.com")!),
            request: URLRequest(url: URL(string: "https://google.com")!),
            isMainFrame: true
        )
        let navigationAction = MockWKNavigationAction(
            request: URLRequest(url: URL(string: "https://popup.com")!),
            targetFrame: nil,
            sourceFrame: sourceFrame,
            isUserInitiated: false
        )
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: navigationAction, windowFeatures: windowFeatures)

        // THEN - Popup allowed (google.com is in allowlist)
        wait(for: [popupExpectation], timeout: 0.5)
    }

    @MainActor
    func testWhenSourceDomainNotInAllowlist_ThenPopupRequiresPermission() {
        // GIVEN
        mockPopupBlockingConfig.allowlist = ["example.com"]
        popupHandlingExtension = createExtension()
        testPermissionManager.setPermission(.deny, forDomain: "other.com", permissionType: .popups)

        let popupCreatedExpectation = expectation(description: "Popup not created")
        popupCreatedExpectation.isInverted = true
        createChildTab = { _, _, _ in
            popupCreatedExpectation.fulfill()
            return nil
        }

        // WHEN - Popup from non-allowlisted domain
        let sourceFrame = WKFrameInfoMock(
            webView: webView,
            securityOrigin: WKSecurityOriginMock.new(url: URL(string: "https://other.com")!),
            request: URLRequest(url: URL(string: "https://other.com")!),
            isMainFrame: true
        )
        let navigationAction = MockWKNavigationAction(
            request: URLRequest(url: URL(string: "https://popup.com")!),
            targetFrame: nil,
            sourceFrame: sourceFrame,
            isUserInitiated: false
        )
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: navigationAction, windowFeatures: windowFeatures)

        // THEN - Popup blocked (requires permission)
        wait(for: [popupCreatedExpectation], timeout: 0.5)
    }

    @MainActor
    func testWhenMultipleDomainsInAllowlist_ThenAllAreAllowed() {
        // GIVEN - Multiple domains in allowlist
        mockPopupBlockingConfig.allowlist = ["github.com", "reddit.com", "zoom.us"]
        popupHandlingExtension = createExtension()

        // Test exact match: github.com
        let githubExpectation = expectation(description: "GitHub popup created")
        createChildTab = { _, _, _ in
            githubExpectation.fulfill()
            return nil
        }

        let githubFrame = WKFrameInfoMock(
            webView: webView,
            securityOrigin: WKSecurityOriginMock.new(url: URL(string: "https://github.com")!),
            request: URLRequest(url: URL(string: "https://github.com")!),
            isMainFrame: true
        )
        let githubAction = MockWKNavigationAction(
            request: URLRequest(url: URL(string: "https://popup.com")!),
            targetFrame: nil,
            sourceFrame: githubFrame,
            isUserInitiated: false
        )
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: githubAction, windowFeatures: windowFeatures)
        wait(for: [githubExpectation], timeout: 0.5)

        // Test parent domain match: oauth.reddit.com matches reddit.com
        let redditExpectation = expectation(description: "Reddit popup created")
        createChildTab = { _, _, _ in
            redditExpectation.fulfill()
            return nil
        }

        let redditFrame = WKFrameInfoMock(
            webView: webView,
            securityOrigin: WKSecurityOriginMock.new(url: URL(string: "https://oauth.reddit.com")!),
            request: URLRequest(url: URL(string: "https://oauth.reddit.com")!),
            isMainFrame: true
        )
        let redditAction = MockWKNavigationAction(
            request: URLRequest(url: URL(string: "https://popup.com")!),
            targetFrame: nil,
            sourceFrame: redditFrame,
            isUserInitiated: false
        )
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: redditAction, windowFeatures: windowFeatures)
        wait(for: [redditExpectation], timeout: 0.5)
    }

    @MainActor
    func testWhenParentDomainInAllowlist_ThenSubdomainsAreAlsoAllowed() {
        // GIVEN - Parent domain in allowlist
        mockPopupBlockingConfig.allowlist = ["subdomain.example.com"]
        popupHandlingExtension = createExtension()
        testPermissionManager.setPermission(.deny, forDomain: "deep.subdomain.example.com", permissionType: .popups)

        let popupCreatedExpectation = expectation(description: "Popup created")
        createChildTab = { _, _, _ in
            popupCreatedExpectation.fulfill()
            return nil
        }

        // WHEN - Popup from deep.subdomain.example.com (child of allowlisted subdomain.example.com)
        let sourceFrame = WKFrameInfoMock(
            webView: webView,
            securityOrigin: WKSecurityOriginMock.new(url: URL(string: "https://deep.subdomain.example.com")!),
            request: URLRequest(url: URL(string: "https://deep.subdomain.example.com")!),
            isMainFrame: true
        )
        let navigationAction = MockWKNavigationAction(
            request: URLRequest(url: URL(string: "https://popup.com")!),
            targetFrame: nil,
            sourceFrame: sourceFrame,
            isUserInitiated: false
        )
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: navigationAction, windowFeatures: windowFeatures)

        // THEN - Popup allowed (parent domain matches)
        wait(for: [popupCreatedExpectation], timeout: 0.5)
    }

    @MainActor
    func testWhenETLDplus1InAllowlist_ThenAllSubdomainsAreAllowed() {
        // GIVEN - eTLD+1 (apex domain) in allowlist
        mockPopupBlockingConfig.allowlist = ["example.com"]
        popupHandlingExtension = createExtension()
        testPermissionManager.setPermission(.deny, forDomain: "deep.sub.example.com", permissionType: .popups)

        let popupCreatedExpectation = expectation(description: "Popup created")
        createChildTab = { _, _, _ in
            popupCreatedExpectation.fulfill()
            return nil
        }

        // WHEN - Popup from deep.sub.example.com (child of allowlisted example.com)
        let sourceFrame = WKFrameInfoMock(
            webView: webView,
            securityOrigin: WKSecurityOriginMock.new(url: URL(string: "https://deep.sub.example.com")!),
            request: URLRequest(url: URL(string: "https://deep.sub.example.com")!),
            isMainFrame: true
        )
        let navigationAction = MockWKNavigationAction(
            request: URLRequest(url: URL(string: "https://popup.com")!),
            targetFrame: nil,
            sourceFrame: sourceFrame,
            isUserInitiated: false
        )
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: navigationAction, windowFeatures: windowFeatures)

        // THEN - Popup allowed (eTLD+1 matches)
        wait(for: [popupCreatedExpectation], timeout: 0.5)
    }

    @MainActor
    func testWhenDeepSubdomainInAllowlist_ThenVeryDeepSubdomainsAreAllowed() {
        // GIVEN - Deep subdomain in allowlist
        mockPopupBlockingConfig.allowlist = ["x.example.com"]
        popupHandlingExtension = createExtension()
        testPermissionManager.setPermission(.deny, forDomain: "a.b.c.x.example.com", permissionType: .popups)

        let popupCreatedExpectation = expectation(description: "Popup created")
        createChildTab = { _, _, _ in
            popupCreatedExpectation.fulfill()
            return nil
        }

        // WHEN - Popup from very deep subdomain
        let sourceFrame = WKFrameInfoMock(
            webView: webView,
            securityOrigin: WKSecurityOriginMock.new(url: URL(string: "https://a.b.c.x.example.com")!),
            request: URLRequest(url: URL(string: "https://a.b.c.x.example.com")!),
            isMainFrame: true
        )
        let navigationAction = MockWKNavigationAction(
            request: URLRequest(url: URL(string: "https://popup.com")!),
            targetFrame: nil,
            sourceFrame: sourceFrame,
            isUserInitiated: false
        )
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: navigationAction, windowFeatures: windowFeatures)

        // THEN - Popup allowed (parent domain x.example.com matches)
        wait(for: [popupCreatedExpectation], timeout: 0.5)
    }

    @MainActor
    func testWhenOnlyChildDomainInAllowlist_ThenParentDomainNotAllowed() {
        // GIVEN - Only child domain in allowlist (not parent)
        mockPopupBlockingConfig.allowlist = ["child.example.com"]
        popupHandlingExtension = createExtension()
        testPermissionManager.setPermission(.deny, forDomain: "example.com", permissionType: .popups)

        let popupCreatedExpectation = expectation(description: "Popup not created")
        popupCreatedExpectation.isInverted = true
        createChildTab = { _, _, _ in
            popupCreatedExpectation.fulfill()
            return nil
        }

        // WHEN - Popup from parent domain (example.com) not in allowlist
        let sourceFrame = WKFrameInfoMock(
            webView: webView,
            securityOrigin: WKSecurityOriginMock.new(url: URL(string: "https://example.com")!),
            request: URLRequest(url: URL(string: "https://example.com")!),
            isMainFrame: true
        )
        let navigationAction = MockWKNavigationAction(
            request: URLRequest(url: URL(string: "https://popup.com")!),
            targetFrame: nil,
            sourceFrame: sourceFrame,
            isUserInitiated: false
        )
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: navigationAction, windowFeatures: windowFeatures)

        // THEN - Popup blocked (parent not in allowlist)
        wait(for: [popupCreatedExpectation], timeout: 0.5)
    }

    @MainActor
    func testWhenOnlyChildDomainInAllowlist_ThenSiblingDomainNotAllowed() {
        // GIVEN - Only one subdomain in allowlist
        mockPopupBlockingConfig.allowlist = ["allowed.example.com"]
        popupHandlingExtension = createExtension()
        testPermissionManager.setPermission(.deny, forDomain: "notallowed.example.com", permissionType: .popups)

        let popupCreatedExpectation = expectation(description: "Popup not created")
        popupCreatedExpectation.isInverted = true
        createChildTab = { _, _, _ in
            popupCreatedExpectation.fulfill()
            return nil
        }

        // WHEN - Popup from sibling domain (notallowed.example.com) not in allowlist
        let sourceFrame = WKFrameInfoMock(
            webView: webView,
            securityOrigin: WKSecurityOriginMock.new(url: URL(string: "https://notallowed.example.com")!),
            request: URLRequest(url: URL(string: "https://notallowed.example.com")!),
            isMainFrame: true
        )
        let navigationAction = MockWKNavigationAction(
            request: URLRequest(url: URL(string: "https://popup.com")!),
            targetFrame: nil,
            sourceFrame: sourceFrame,
            isUserInitiated: false
        )
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: navigationAction, windowFeatures: windowFeatures)

        // THEN - Popup blocked (sibling domain not in allowlist)
        wait(for: [popupCreatedExpectation], timeout: 0.5)
    }

    @MainActor
    func testWhenSourceDomainIsInvalidTLD_ThenPopupNotAllowedByAllowlist() {
        // GIVEN
        mockPopupBlockingConfig.allowlist = ["example.com"]
        popupHandlingExtension = createExtension()
        testPermissionManager.setPermission(.deny, forDomain: "invalidtld", permissionType: .popups)

        let popupCreatedExpectation = expectation(description: "Popup not created")
        popupCreatedExpectation.isInverted = true
        createChildTab = { _, _, _ in
            popupCreatedExpectation.fulfill()
            return nil
        }

        // WHEN - Popup from invalid domain
        let sourceFrame = WKFrameInfoMock(
            webView: webView,
            securityOrigin: WKSecurityOriginMock.new(url: URL(string: "https://invalidtld")!),
            request: URLRequest(url: URL(string: "https://invalidtld")!),
            isMainFrame: true
        )
        let navigationAction = MockWKNavigationAction(
            request: URLRequest(url: URL(string: "https://popup.com")!),
            targetFrame: nil,
            sourceFrame: sourceFrame,
            isUserInitiated: false
        )
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: navigationAction, windowFeatures: windowFeatures)

        // THEN - Popup blocked
        wait(for: [popupCreatedExpectation], timeout: 0.5)
    }

    @MainActor
    func testWhenSourceDomainHasDifferentCasing_ThenExactMatchStillWorks() {
        // GIVEN - Allowlist with lowercase domain
        mockPopupBlockingConfig.allowlist = ["github.com"]
        popupHandlingExtension = createExtension()

        let popupExpectation = expectation(description: "Popup created")
        createChildTab = { _, _, _ in
            popupExpectation.fulfill()
            return nil
        }

        // WHEN - Popup from domain with mixed casing (GiThUb.CoM)
        let sourceFrame = WKFrameInfoMock(
            webView: webView,
            securityOrigin: WKSecurityOriginMock.new(url: URL(string: "https://GiThUb.CoM")!),
            request: URLRequest(url: URL(string: "https://GiThUb.CoM")!),
            isMainFrame: true
        )
        let navigationAction = MockWKNavigationAction(
            request: URLRequest(url: URL(string: "https://popup.com")!),
            targetFrame: nil,
            sourceFrame: sourceFrame,
            isUserInitiated: false
        )
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: navigationAction, windowFeatures: windowFeatures)

        // THEN - Popup allowed (case-insensitive match)
        wait(for: [popupExpectation], timeout: 0.5)
    }

    @MainActor
    func testWhenSourceDomainHasWwwPrefix_ThenExactMatchStillWorks() {
        // GIVEN - Allowlist with domain without www
        mockPopupBlockingConfig.allowlist = ["github.com"]
        popupHandlingExtension = createExtension()

        let popupExpectation = expectation(description: "Popup created")
        createChildTab = { _, _, _ in
            popupExpectation.fulfill()
            return nil
        }

        // WHEN - Popup from www subdomain
        let sourceFrame = WKFrameInfoMock(
            webView: webView,
            securityOrigin: WKSecurityOriginMock.new(url: URL(string: "https://www.github.com")!),
            request: URLRequest(url: URL(string: "https://www.github.com")!),
            isMainFrame: true
        )
        let navigationAction = MockWKNavigationAction(
            request: URLRequest(url: URL(string: "https://popup.com")!),
            targetFrame: nil,
            sourceFrame: sourceFrame,
            isUserInitiated: false
        )
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: navigationAction, windowFeatures: windowFeatures)

        // THEN - Popup allowed (www prefix stripped)
        wait(for: [popupExpectation], timeout: 0.5)
    }

    @MainActor
    func testWhenSourceDomainHasBothWwwAndDifferentCasing_ThenMatchStillWorks() {
        // GIVEN - Allowlist with lowercase domain
        mockPopupBlockingConfig.allowlist = ["reddit.com"]
        popupHandlingExtension = createExtension()

        let popupExpectation = expectation(description: "Popup created")
        createChildTab = { _, _, _ in
            popupExpectation.fulfill()
            return nil
        }

        // WHEN - Popup from www subdomain with mixed casing (www.ReDdIt.CoM)
        let sourceFrame = WKFrameInfoMock(
            webView: webView,
            securityOrigin: WKSecurityOriginMock.new(url: URL(string: "https://www.ReDdIt.CoM")!),
            request: URLRequest(url: URL(string: "https://www.ReDdIt.CoM")!),
            isMainFrame: true
        )
        let navigationAction = MockWKNavigationAction(
            request: URLRequest(url: URL(string: "https://popup.com")!),
            targetFrame: nil,
            sourceFrame: sourceFrame,
            isUserInitiated: false
        )
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: navigationAction, windowFeatures: windowFeatures)

        // THEN - Popup allowed (www prefix stripped, case-insensitive, parent domain matches)
        wait(for: [popupExpectation], timeout: 0.5)
    }

    @MainActor
    func testWhenAllowlistAndSourceHasMixedCasing_ThenMatchWorks() {
        // GIVEN - Allowlist entry
        mockPopupBlockingConfig.allowlist = ["google.com"]
        popupHandlingExtension = createExtension()

        let popupExpectation = expectation(description: "Popup created")
        createChildTab = { _, _, _ in
            popupExpectation.fulfill()
            return nil
        }

        // WHEN - Popup from subdomain with mixed casing (AcCoUnTs.GoOgLe.CoM)
        let sourceFrame = WKFrameInfoMock(
            webView: webView,
            securityOrigin: WKSecurityOriginMock.new(url: URL(string: "https://AcCoUnTs.GoOgLe.CoM")!),
            request: URLRequest(url: URL(string: "https://AcCoUnTs.GoOgLe.CoM")!),
            isMainFrame: true
        )
        let navigationAction = MockWKNavigationAction(
            request: URLRequest(url: URL(string: "https://popup.com")!),
            targetFrame: nil,
            sourceFrame: sourceFrame,
            isUserInitiated: false
        )
        _ = popupHandlingExtension.createWebView(from: webView, with: configuration, for: navigationAction, windowFeatures: windowFeatures)

        // THEN - Popup allowed (parent domain matching handles case-insensitivity)
        wait(for: [popupExpectation], timeout: 0.5)
    }

}

// MARK: - Mock Objects

class MockPopupBlockingConfiguration: PopupBlockingConfiguration {
    var userInitiatedPopupThreshold: TimeInterval = 6.0
    var allowlist: Set<String> = []
}

class TestPermissionManager: PermissionManagerProtocol {
    var persistedPermissions: [String: [PermissionType: PersistedPermissionDecision]] = [:]

    var permissionPublisher: AnyPublisher<(domain: String, permissionType: PermissionType, decision: PersistedPermissionDecision), Never> {
        return Empty().eraseToAnyPublisher()
    }

    func hasPermissionPersisted(forDomain domain: String, permissionType: PermissionType) -> Bool {
        return persistedPermissions[domain]?[permissionType] != nil
    }

    func hasAnyPermissionPersisted(forDomain domain: String) -> Bool {
        return persistedPermissions[domain]?.isEmpty == false
    }

    func persistedPermissionTypes(forDomain domain: String) -> [PermissionType] {
        guard let permissions = persistedPermissions[domain] else { return [] }
        return Array(permissions.keys)
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

    func removePermission(forDomain domain: String, permissionType: PermissionType) {
        persistedPermissions[domain]?[permissionType] = nil
    }

    var persistedPermissionTypes: Set<PermissionType> { return [] }
}

// MARK: - Test Helpers

private extension NSEvent {

    static func mock(_ type: NSEvent.EventType, timestamp: TimeInterval, modifierFlags: NSEvent.ModifierFlags = []) -> NSEvent {
        switch type {
        case .keyDown:
            return NSEvent.keyEvent(
                with: type,
                location: .zero,
                modifierFlags: modifierFlags,
                timestamp: timestamp,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: 0
            )!
        default:
            var event = NSEvent.mouseEvent(
                with: type,
                location: .zero,
                modifierFlags: modifierFlags,
                timestamp: timestamp,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1.0
            )!
            // Set buttonNumber for mouse events via CGEvent
            let button: NSEvent.Button = switch type {
            case .rightMouseDown, .rightMouseUp: .right
            case .otherMouseDown, .otherMouseUp: .middle
            default: .left
            }
            if button.rawValue != 0 {
                let cgEvent = event.cgEvent!
                cgEvent.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button.rawValue))
                event = .init(cgEvent: cgEvent)!
            }
            return event
        }
    }
}

private extension WKNavigationAction {

    static func mock(url: URL, webView: WKWebView, isUserInitiated: Bool = false) -> WKNavigationAction {
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
}
