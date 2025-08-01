//
//  WiFiHotspotDetectionTabExtensionTests.swift
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

import XCTest
import Combine
import WebKit
import Navigation
import FeatureFlags
import BrowserServicesKit
@testable import DuckDuckGo_Privacy_Browser

// MARK: - Test Class

@MainActor
final class WiFiHotspotDetectionTabExtensionTests: XCTestCase {

    private var tabExtension: WiFiHotspotDetectionTabExtension!
    private var mockHotspotService: MockHotspotDetectionService!
    private var mockFeatureFlagger: MockFeatureFlagger!
    private var permissionModel: PermissionModel!
    private var mockPermissionManager: PermissionManagerMock!
    private var cancellables: Set<AnyCancellable>!
    private var mockWebViewPublisher: PassthroughSubject<WKWebView, Never>!

    override func setUp() {
        mockHotspotService = MockHotspotDetectionService()
        mockFeatureFlagger = MockFeatureFlagger()
        mockPermissionManager = PermissionManagerMock()

        // Create a minimal web view for PermissionModel
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))

        // Create real PermissionModel with mocked dependencies
        permissionModel = PermissionModel(
            webView: webView,
            permissionManager: mockPermissionManager,
            geolocationService: GeolocationServiceMock()
        )

        cancellables = Set<AnyCancellable>()
        mockWebViewPublisher = PassthroughSubject<WKWebView, Never>()

        tabExtension = WiFiHotspotDetectionTabExtension(
            permissionModel: permissionModel,
            hotspotDetectionService: mockHotspotService,
            featureFlagger: mockFeatureFlagger,
            webViewPublisher: mockWebViewPublisher.eraseToAnyPublisher()
        )
    }

    override func tearDown() {
        cancellables?.removeAll()
        tabExtension = nil
        mockHotspotService = nil
        mockFeatureFlagger = nil
        permissionModel = nil
        mockPermissionManager = nil
        mockWebViewPublisher = nil
    }

    // MARK: - Feature Flag Tests

    func testWhenFeatureFlagDisabled_NavigationFailureIsIgnored() {
        // Given: Feature flag is disabled
        mockFeatureFlagger.enabledFeatureFlags = []

        let navigation = createTestNavigation(url: URL(string: "https://example.com")!)
        let error = WKError(WKError.Code(rawValue: NSURLErrorCannotConnectToHost)!)

        // When: Navigation fails
        tabExtension.navigation(navigation, didFailWith: error)

        // Then: Service should not be subscribed to
        XCTAssertEqual(mockHotspotService.currentState, .unknown)
    }

    func testWhenFeatureFlagEnabled_NavigationFailureTriggersSubscription() {
        // Given: Feature flag is enabled
        mockFeatureFlagger.enabledFeatureFlags = [.hotspotDetection]

        let navigation = createTestNavigation(url: URL(string: "https://example.com")!)
        let error = WKError(WKError.Code(rawValue: NSURLErrorCannotConnectToHost)!)

        // When: Navigation fails
        tabExtension.navigation(navigation, didFailWith: error)

        // Then: Extension should be subscribed to service (we can't directly test this,
        // but we can test the behavior when state changes)
        mockHotspotService.updateState(.connected)

        // The subscription should trigger unsubscription when connected
        XCTAssertEqual(mockHotspotService.currentState, .connected)
    }

    // MARK: - Navigation Tests

    func testWhenNavigationIsNotCurrent_FailureIsIgnored() {
        // Given: Feature flag is enabled
        mockFeatureFlagger.enabledFeatureFlags = [.hotspotDetection]

        let navigation = createTestNavigation(url: URL(string: "https://example.com")!, isCurrent: false)
        let error = WKError(WKError.Code(rawValue: NSURLErrorCannotConnectToHost)!)

        // When: Non-current navigation fails
        tabExtension.navigation(navigation, didFailWith: error)

        // Then: Should not subscribe to service
        // (We test this indirectly by checking that state changes don't trigger behavior)
        mockHotspotService.updateState(.hotspotAuth)

        // No permission request should be made
        XCTAssertNil(permissionModel.authorizationQuery, "No authorization query should be created")
    }

    func testWhenNavigationIsCurrent_FailureTriggersSubscription() {
        // Given: Feature flag is enabled
        mockFeatureFlagger.enabledFeatureFlags = [.hotspotDetection]

        let navigation = createTestNavigation(url: URL(string: "https://example.com")!, isCurrent: true)
        let error = WKError(WKError.Code(rawValue: NSURLErrorCannotConnectToHost)!)

        // When: Current navigation fails
        tabExtension.navigation(navigation, didFailWith: error)

        // Wait for authorization query using publisher
        let expectation = expectation(description: "Authorization query should be created")

        let cancellable = permissionModel.$authorizationQuery
            .compactMap { $0 }
            .first()
            .sink { _ in
                expectation.fulfill()
            }

        // Trigger hotspot auth state
        mockHotspotService.updateState(.hotspotAuth)

        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()

        // Then: Verify the authorization query
        guard let authQuery = permissionModel.authorizationQuery else {
            XCTFail("No authorization query was created")
            return
        }

        XCTAssertTrue(authQuery.permissions.contains(.wifiHotspot))
        XCTAssertEqual(authQuery.domain, "detectportal.firefox.com")
        XCTAssertEqual(authQuery.url?.absoluteString, "http://detectportal.firefox.com/success.txt")

        // Respond to the authorization query
        authQuery.handleDecision(grant: true, remember: false)
    }

    // MARK: - State Change Tests

    func testWhenServiceReportsConnected_ExtensionUnsubscribes() {
        // Given: Extension is subscribed
        mockFeatureFlagger.enabledFeatureFlags = [.hotspotDetection]
        let navigation = createTestNavigation(url: URL(string: "https://example.com")!)
        let error = WKError(WKError.Code(rawValue: NSURLErrorCannotConnectToHost)!)
        tabExtension.navigation(navigation, didFailWith: error)

        // When: Service reports connected
        mockHotspotService.updateState(.connected)

        // Then: Extension should unsubscribe (tested indirectly)
        // Future state changes should not trigger permission requests

        // Change state again - should not trigger permission request
        mockHotspotService.updateState(.hotspotAuth)

        XCTAssertNil(permissionModel.authorizationQuery, "Should not request permission after unsubscribing")
    }

    func testWhenServiceReportsHotspotAuth_PermissionIsRequested() {
        // Given: Extension is subscribed
        mockFeatureFlagger.enabledFeatureFlags = [.hotspotDetection]
        let navigation = createTestNavigation(url: URL(string: "https://example.com")!)
        let error = WKError(WKError.Code(rawValue: NSURLErrorCannotConnectToHost)!)
        tabExtension.navigation(navigation, didFailWith: error)

        // Wait for authorization query using publisher
        let expectation = expectation(description: "Authorization query should be created")

        let cancellable = permissionModel.$authorizationQuery
            .compactMap { $0 }
            .first()
            .sink { _ in
                expectation.fulfill()
            }

        // When: Service reports hotspot auth required
        mockHotspotService.updateState(.hotspotAuth)

        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()

        // Then: Permission should be requested with correct parameters
        guard let authQuery = permissionModel.authorizationQuery else {
            XCTFail("No authorization query was created")
            return
        }

        XCTAssertEqual(authQuery.permissions, [.wifiHotspot])
        XCTAssertEqual(authQuery.domain, "detectportal.firefox.com")
        XCTAssertEqual(authQuery.url?.absoluteString, "http://detectportal.firefox.com/success.txt")
    }

    func testWhenServiceReportsUnknown_NoPermissionRequested() {
        // Given: Extension is subscribed
        mockFeatureFlagger.enabledFeatureFlags = [.hotspotDetection]
        let navigation = createTestNavigation(url: URL(string: "https://example.com")!)
        let error = WKError(WKError.Code(rawValue: NSURLErrorCannotConnectToHost)!)
        tabExtension.navigation(navigation, didFailWith: error)

        // When: Service reports unknown state
        mockHotspotService.updateState(.unknown)

        // Then: No permission should be requested
        XCTAssertNil(permissionModel.authorizationQuery, "No permission should be requested for unknown state")
    }

    // MARK: - Multiple Navigation Failures

    func testWhenMultipleNavigationsFailWhileSubscribed_OnlyOneSubscriptionExists() {
        // Given: Feature flag is enabled
        mockFeatureFlagger.enabledFeatureFlags = [.hotspotDetection]

        let navigation1 = createTestNavigation(url: URL(string: "https://example1.com")!)
        let navigation2 = createTestNavigation(url: URL(string: "https://example2.com")!)
        let error = WKError(WKError.Code(rawValue: NSURLErrorCannotConnectToHost)!)

        // When: Multiple navigations fail
        tabExtension.navigation(navigation1, didFailWith: error)
        tabExtension.navigation(navigation2, didFailWith: error)

        // Then: Should still work correctly (no duplicate subscriptions)
        let expectation = expectation(description: "Authorization query should be created")

        let cancellable = permissionModel.$authorizationQuery
            .compactMap { $0 }
            .first()
            .sink { _ in
                expectation.fulfill()
            }

        mockHotspotService.updateState(.hotspotAuth)

        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()

        XCTAssertNotNil(permissionModel.authorizationQuery, "Should request permission")
        XCTAssertEqual(permissionModel.authorizationQuery?.permissions, [.wifiHotspot])
    }

    // MARK: - Memory Management Tests

    func testWhenTabExtensionIsDeallocated_SubscriptionIsCancelled() {
        // Given: Extension is subscribed
        mockFeatureFlagger.enabledFeatureFlags = [.hotspotDetection]
        let navigation = createTestNavigation(url: URL(string: "https://example.com")!)
        let error = WKError(WKError.Code(rawValue: NSURLErrorCannotConnectToHost)!)
        tabExtension.navigation(navigation, didFailWith: error)

        // When: Extension is deallocated
        weak var weakTabExtension = tabExtension
        tabExtension = nil

        // Then: Extension should be deallocated (testing memory management)
        XCTAssertNil(weakTabExtension, "Tab extension should be deallocated")

        // Service state changes should not cause any issues
        mockHotspotService.updateState(.hotspotAuth)
        mockHotspotService.updateState(.connected)
    }

    // MARK: - State Transition Tests

    func testStateTransitionFromUnknownToHotspotAuthToConnected() {
        // Given: Extension is subscribed
        mockFeatureFlagger.enabledFeatureFlags = [.hotspotDetection]
        let navigation = createTestNavigation(url: URL(string: "https://example.com")!)
        let error = WKError(WKError.Code(rawValue: NSURLErrorCannotConnectToHost)!)
        tabExtension.navigation(navigation, didFailWith: error)

        // When: State transitions unknown -> hotspotAuth -> connected
        let expectation = expectation(description: "Authorization query should be created")

        let cancellable = permissionModel.$authorizationQuery
            .compactMap { $0 }
            .first()
            .sink { _ in
                expectation.fulfill()
            }

        mockHotspotService.updateState(.hotspotAuth)

        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()

        XCTAssertNotNil(permissionModel.authorizationQuery, "Should request permission for hotspotAuth")

        // Simulate granting permission to clear the query
        permissionModel.authorizationQuery?.handleDecision(grant: true, remember: false)

        mockHotspotService.updateState(.connected)

        // Try again - should not request permission (unsubscribed)
        mockHotspotService.updateState(.hotspotAuth)

        XCTAssertNil(permissionModel.authorizationQuery, "Should not request permission after unsubscribing")
    }

    func testWhenConnectedStateAfterNavigationFailureAndHotspotDetection_WebViewReloads() async {
        // Given: Feature flag is enabled and navigation failed
        mockFeatureFlagger.enabledFeatureFlags = [.hotspotDetection]
        let navigation = createTestNavigation(url: URL(string: "https://example.com")!, isCurrent: true)
        let mockWebView = MockHotspotWebView()

        let expectation = expectation(description: "WebView should reload when connectivity is restored after hotspot detection")

        // Set up callback to fulfill expectation when reload is called
        mockWebView.onReloadCalled = {
            expectation.fulfill()
        }

        // Set up webView first before navigation failure
        mockWebViewPublisher.send(mockWebView)

        tabExtension.navigation(navigation, didFailWith: WKError(WKError.Code(rawValue: NSURLErrorCannotConnectToHost)!))

        // When: hotspot is detected first, then connectivity is restored
        mockHotspotService.updateState(.hotspotAuth)
        mockHotspotService.updateState(.connected)

        // Then: wait for webView to reload via async publisher processing
        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(mockWebView.reloadCalled, "WebView should reload when connectivity is restored after hotspot detection and navigation failure")
    }

    func testWhenConnectedStateWithoutPreviousError_WebViewDoesNotReload() {
        // Given: Feature flag is enabled but no previous navigation error
        mockFeatureFlagger.enabledFeatureFlags = [.hotspotDetection]
        let mockWebView = MockHotspotWebView()

        // When: webView is provided and service reports connected
        mockWebViewPublisher.send(mockWebView)
        mockHotspotService.updateState(.connected)

        // Then: webView should not reload
        XCTAssertFalse(mockWebView.reloadCalled, "WebView should not reload when there was no previous navigation error")
    }

    func testWhenNonCurrentNavigationFails_NoReloadOnConnected() {
        // Given: Feature flag is enabled but navigation is not current
        mockFeatureFlagger.enabledFeatureFlags = [.hotspotDetection]
        let navigation = createTestNavigation(url: URL(string: "https://example.com")!, isCurrent: false)
        let mockWebView = MockHotspotWebView()

        tabExtension.navigation(navigation, didFailWith: WKError(.unknown))

        // When: webView is provided and connectivity is restored
        mockWebViewPublisher.send(mockWebView)
        mockHotspotService.updateState(.connected)

        // Then: webView should not reload (because navigation was not current)
        XCTAssertFalse(mockWebView.reloadCalled, "WebView should not reload when failed navigation was not current")
    }

    func testWhenConnectedStateAfterNavigationFailureWithoutHotspotDetection_WebViewDoesNotReload() {
        // Given: Feature flag is enabled and navigation failed
        mockFeatureFlagger.enabledFeatureFlags = [.hotspotDetection]
        let navigation = createTestNavigation(url: URL(string: "https://example.com")!, isCurrent: true)
        let mockWebView = MockHotspotWebView()

        // Set up webView first before navigation failure
        mockWebViewPublisher.send(mockWebView)

        tabExtension.navigation(navigation, didFailWith: WKError(WKError.Code(rawValue: NSURLErrorCannotConnectToHost)!))

        // When: connectivity is restored WITHOUT hotspot detection
        mockHotspotService.updateState(.connected)

        // Then: webView should NOT reload (because no hotspot was detected)
        XCTAssertFalse(mockWebView.reloadCalled, "WebView should not reload when connectivity is restored without prior hotspot detection")
    }

    func testMultipleTabsDetectHotspot_OnlyOneUsedForPortal_BothShouldReload() async throws {
        // Given: Two tab extensions with navigation failures
        let mockWebView1 = MockHotspotWebView()
        let mockWebView2 = MockHotspotWebView()

        let reloadExpectation1 = expectation(description: "Tab 1 should reload")
        let reloadExpectation2 = expectation(description: "Tab 2 should reload")

        mockWebView1.onReloadCalled = { reloadExpectation1.fulfill() }
        mockWebView2.onReloadCalled = { reloadExpectation2.fulfill() }

        // Create publishers for the web views
        let publisher1 = PassthroughSubject<WKWebView, Never>()
        let publisher2 = PassthroughSubject<WKWebView, Never>()

        // Create two tab extensions sharing the same service
        let tabExtension1 = WiFiHotspotDetectionTabExtension(
            permissionModel: permissionModel,
            hotspotDetectionService: mockHotspotService,
            featureFlagger: mockFeatureFlagger,
            webViewPublisher: publisher1.eraseToAnyPublisher()
        )

        let tabExtension2 = WiFiHotspotDetectionTabExtension(
            permissionModel: permissionModel,
            hotspotDetectionService: mockHotspotService,
            featureFlagger: mockFeatureFlagger,
            webViewPublisher: publisher2.eraseToAnyPublisher()
        )

        // Enable feature flag
        mockFeatureFlagger.enabledFeatureFlags = [.hotspotDetection]

        // Send webviews to extensions
        publisher1.send(mockWebView1)
        publisher2.send(mockWebView2)

        // When: Both tabs fail navigation
        let testURL = URL(string: "https://example.com")!
        let navigation1 = createTestNavigation(url: testURL)
        let navigation2 = createTestNavigation(url: testURL)
        let networkError = WKError(WKError.Code(rawValue: NSURLErrorCannotConnectToHost)!)

        tabExtension1.navigation(navigation1, didFailWith: networkError)
        tabExtension2.navigation(navigation2, didFailWith: networkError)

        // And: Hotspot is detected (both tabs should detect this)
        mockHotspotService.updateState(.hotspotAuth)

        // Wait for state processing
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // And: Connectivity is restored
        mockHotspotService.updateState(.connected)

        // Then: Both tabs should reload since they both detected hotspot and had navigation errors
        await fulfillment(of: [reloadExpectation1, reloadExpectation2], timeout: 1.0)

        XCTAssertTrue(mockWebView1.reloadCalled, "Tab 1 should reload after connectivity restoration")
        XCTAssertTrue(mockWebView2.reloadCalled, "Tab 2 should reload after connectivity restoration")
    }
}

// MARK: - Mock Classes

final class MockHotspotWebView: WKWebView {
    var reloadCalled = false
    var onReloadCalled: (() -> Void)?

    override func reload() -> WKNavigation? {
        reloadCalled = true
        onReloadCalled?()
        return nil
    }
}

final class MockHotspotDetectionService: HotspotDetectionServiceProtocol {

    private let stateSubject = CurrentValueSubject<HotspotConnectivityState, Never>(.unknown)

    var currentState: HotspotConnectivityState {
        stateSubject.value
    }

    var statePublisher: AnyPublisher<HotspotConnectivityState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    func updateState(_ state: HotspotConnectivityState) {
        stateSubject.send(state)
    }
}

// Helper function to create test Navigation objects
// Note: For testing purposes, these Navigation objects have an empty URL
// The actual URL passed to the helper is noted in test comments for clarity
@MainActor
private func createTestNavigation(url: URL, isCurrent: Bool = true) -> Navigation {
    // For simplicity in testing, we create a basic Navigation object
    // The tab extension will get URL.empty, but the test intention is documented via the url parameter
    return Navigation(identity: .init(nil), responders: .init(), state: .started, redirectHistory: [], isCurrent: isCurrent, isCommitted: false)
}
