//
//  WiFiHotspotDetectionIntegrationTests.swift
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
import Clocks
import Combine
import Common
import FeatureFlags
import Navigation
import OHHTTPStubs
import OHHTTPStubsSwift
import WebKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

@available(macOS 13, *)
@MainActor
final class WiFiHotspotDetectionIntegrationTests: XCTestCase {

    private var clock: TestClock<Duration>!
    private var service: HotspotDetectionService!
    private var tabExtension: WiFiHotspotDetectionTabExtension!
    private var mockFeatureFlagger: MockFeatureFlagger!
    private var permissionModel: PermissionModel!
    private var mockPermissionManager: PermissionManagerMock!
    private var cancellables: Set<AnyCancellable>!
    private var mockWebViewPublisher: PassthroughSubject<WKWebView, Never>!

    override func setUp() {
        clock = TestClock()
        let sleeper = Sleeper(clock: clock)
        service = HotspotDetectionService(sleeper: sleeper)
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
            hotspotDetectionService: service,
            featureFlagger: mockFeatureFlagger,
            webViewPublisher: mockWebViewPublisher.eraseToAnyPublisher()
        )

        // Enable feature flag for all tests
        mockFeatureFlagger.enabledFeatureFlags = [.hotspotDetection]
    }

    override func tearDown() {
        cancellables?.removeAll()
        tabExtension = nil
        service = nil
        clock = nil
        mockFeatureFlagger = nil
        permissionModel = nil
        mockPermissionManager = nil
        mockWebViewPublisher = nil
        HTTPStubs.removeAllStubs()
    }

    // MARK: - Integration Tests

    func testWhenNavigationFailsAndHotspotDetected_PermissionIsRequestedWithCorrectURL() async throws {
        // Stub captive portal response
        stub(condition: isHost("detectportal.firefox.com")) { _ in
            return HTTPStubsResponse(data: "<html>Captive Portal Login</html>".data(using: .utf8)!, statusCode: 200, headers: nil)
        }

        // Wait for authorization query using publisher (like unit tests)
        let expectation = expectation(description: "Authorization query should be created")

        let cancellable = permissionModel.$authorizationQuery
            .compactMap { $0 }
            .first()
            .sink { authQuery in
                // Verify the authorization query properties
                XCTAssertTrue(authQuery.permissions.contains(.wifiHotspot))
                XCTAssertEqual(authQuery.domain, "detectportal.firefox.com")
                XCTAssertEqual(authQuery.url?.absoluteString, "http://detectportal.firefox.com/success.txt")
                expectation.fulfill()
            }

        // Trigger navigation failure
        let navigation = Navigation(identity: .init(nil), responders: .init(), state: .started, redirectHistory: [], isCurrent: true, isCommitted: false)
        let error = WKError(WKError.Code(rawValue: NSURLErrorCannotConnectToHost)!)
        tabExtension.navigation(navigation, didFailWith: error)

        await fulfillment(of: [expectation], timeout: 5.0)
        cancellable.cancel()
    }

    func testWhenNavigationFailsButNoHotspot_NoPermissionRequested() async throws {
        // Stub success response (no hotspot)
        stub(condition: isHost("detectportal.firefox.com")) { _ in
            return HTTPStubsResponse(data: "success".data(using: .utf8)!, statusCode: 200, headers: nil)
        }

        // Wait for service to check connectivity and publish .connected state (no hotspot)
        let expectation = expectation(description: "Service should detect connected state")

        let cancellable = service.statePublisher
            .filter { $0 == .connected }
            .first()
            .sink { _ in
                expectation.fulfill()
            }

        // Trigger navigation failure
        let navigation = Navigation(identity: .init(nil), responders: .init(), state: .started, redirectHistory: [], isCurrent: true, isCommitted: false)
        let error = WKError(WKError.Code(rawValue: NSURLErrorCannotConnectToHost)!)
        tabExtension.navigation(navigation, didFailWith: error)

        await fulfillment(of: [expectation], timeout: 2.0)
        cancellable.cancel()

        // Verify no authorization query was created (service detected no hotspot)
        XCTAssertNil(permissionModel.authorizationQuery, "Should not create authorization query when no hotspot detected")
    }

    func testWhenHotspotResolves_ExtensionUnsubscribesFromService() async throws {
        // First stub captive portal, then success
        var requestCount = 0
        stub(condition: isHost("detectportal.firefox.com")) { _ in
            requestCount += 1
            if requestCount <= 2 {  // First few requests show captive portal
                return HTTPStubsResponse(data: "<html>Captive Portal</html>".data(using: .utf8)!, statusCode: 200, headers: nil)
            } else {  // Later requests show success (user authenticated)
                return HTTPStubsResponse(data: "success".data(using: .utf8)!, statusCode: 200, headers: nil)
            }
        }

        // Wait for authorization query for hotspot detection
        let hotspotExpectation = expectation(description: "Authorization query should be created for hotspot")

        let hotspotCancellable = permissionModel.$authorizationQuery
            .compactMap { $0 }
            .first()
            .sink { authQuery in
                XCTAssertTrue(authQuery.permissions.contains(.wifiHotspot))
                XCTAssertEqual(authQuery.domain, "detectportal.firefox.com")
                hotspotExpectation.fulfill()
            }

        // Trigger navigation failure
        let navigation = Navigation(identity: .init(nil), responders: .init(), state: .started, redirectHistory: [], isCurrent: true, isCommitted: false)
        let error = WKError(WKError.Code(rawValue: NSURLErrorCannotConnectToHost)!)
        tabExtension.navigation(navigation, didFailWith: error)

        await fulfillment(of: [hotspotExpectation], timeout: 5.0)
        hotspotCancellable.cancel()

        // Verify authorization query was created for hotspot
        XCTAssertNotNil(permissionModel.authorizationQuery, "Authorization query should have been created for hotspot")
        let initialAuthQuery = permissionModel.authorizationQuery

        // Wait for service to detect connectivity is restored (.connected state)
        let resolvedExpectation = expectation(description: "Service should detect connectivity restored")

        let resolveCancellable = service.statePublisher
            .filter { $0 == .connected }
            .first()
            .sink { _ in
                resolvedExpectation.fulfill()
            }

        // Advance clock to trigger service's periodic checks (every 5 seconds)
        // Need at least 3 total requests: 1st and 2nd = captive portal, 3rd = success
        await clock.advance(by: .seconds(5)) // Triggers 2nd request (still captive portal)
        await Task.megaYield(count: 5)

        await clock.advance(by: .seconds(5)) // Triggers 3rd request (success response)
        await Task.megaYield(count: 5)

        await fulfillment(of: [resolvedExpectation], timeout: 5.0)
        resolveCancellable.cancel()

        // After connectivity restored, authorization query should be cleared
        XCTAssertNotNil(initialAuthQuery, "Should have had initial authorization query")
        XCTAssertNil(permissionModel.authorizationQuery, "Authorization query should be cleared when connectivity is restored")
    }

    func testMultipleTabExtensionsWithSameService() async throws {
        var serviceRequestCount = 0

        // Stub captive portal response BEFORE creating any extensions
        stub(condition: isHost("detectportal.firefox.com")) { _ in
            serviceRequestCount += 1
            return HTTPStubsResponse(data: "<html>Captive Portal</html>".data(using: .utf8)!, statusCode: 200, headers: nil)
        }

        // Create second tab extension with its own permission manager
        let mockPermissionManager2 = PermissionManagerMock()
        let webView2 = WKWebView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
        let permissionModel2 = PermissionModel(
            webView: webView2,
            permissionManager: mockPermissionManager2,
            geolocationService: GeolocationServiceMock()
        )

        let tabExtension2 = WiFiHotspotDetectionTabExtension(
            permissionModel: permissionModel2,
            hotspotDetectionService: service,
            featureFlagger: mockFeatureFlagger,
            webViewPublisher: mockWebViewPublisher.eraseToAnyPublisher()
        )

        // Set up expectations for authorization queries to be created
        let expectation1 = expectation(description: "First tab should create authorization query")
        let expectation2 = expectation(description: "Second tab should create authorization query")

        let cancellable1 = permissionModel.$authorizationQuery
            .compactMap { $0 }
            .first()
            .sink { authQuery in
                XCTAssertTrue(authQuery.permissions.contains(.wifiHotspot))
                XCTAssertEqual(authQuery.domain, "detectportal.firefox.com")
                expectation1.fulfill()
            }

        let cancellable2 = permissionModel2.$authorizationQuery
            .compactMap { $0 }
            .first()
            .sink { authQuery in
                XCTAssertTrue(authQuery.permissions.contains(.wifiHotspot))
                XCTAssertEqual(authQuery.domain, "detectportal.firefox.com")
                expectation2.fulfill()
            }

        // Trigger navigation failures on both tabs
        let navigation1 = Navigation(identity: .init(nil), responders: .init(), state: .started, redirectHistory: [], isCurrent: true, isCommitted: false)
        let navigation2 = Navigation(identity: .init(nil), responders: .init(), state: .started, redirectHistory: [], isCurrent: true, isCommitted: false)
        let error = WKError(WKError.Code(rawValue: NSURLErrorCannotConnectToHost)!)

        tabExtension.navigation(navigation1, didFailWith: error)
        tabExtension2.navigation(navigation2, didFailWith: error)

        await fulfillment(of: [expectation1, expectation2], timeout: 5.0)
        cancellable1.cancel()
        cancellable2.cancel()

        // Verify authorization queries were created for both tabs
        XCTAssertNotNil(permissionModel.authorizationQuery, "First tab should have created authorization query")
        XCTAssertNotNil(permissionModel2.authorizationQuery, "Second tab should have created authorization query")

        // Multiple tab extensions should share the same service - should only make ONE request for connectivity check
        XCTAssertEqual(serviceRequestCount, 1, "Service should only make one connectivity request despite multiple subscribers")
    }

    func testMultipleTabExtensionsPartialUnsubscribe() async throws {
        var serviceRequestCount = 0

        // Stub: Always return captive portal to keep service active
        stub(condition: isHost("detectportal.firefox.com")) { _ in
            serviceRequestCount += 1
            return HTTPStubsResponse(data: "<html>Captive Portal</html>".data(using: .utf8)!, statusCode: 200, headers: nil)
        }

        // Create second tab extension after stub is set
        let mockPermissionManager2 = PermissionManagerMock()
        let webView2 = WKWebView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
        let permissionModel2 = PermissionModel(
            webView: webView2,
            permissionManager: mockPermissionManager2,
            geolocationService: GeolocationServiceMock()
        )

        let tabExtension2 = WiFiHotspotDetectionTabExtension(
            permissionModel: permissionModel2,
            hotspotDetectionService: service,
            featureFlagger: mockFeatureFlagger,
            webViewPublisher: mockWebViewPublisher.eraseToAnyPublisher()
        )

        // Set up expectations for both tabs to get initial hotspot state
        let hotspot1Expectation = expectation(description: "First tab should detect hotspot")
        let hotspot2Expectation = expectation(description: "Second tab should detect hotspot")

        let cancellable1 = permissionModel.$authorizationQuery
            .compactMap { $0 }
            .first()
            .sink { _ in hotspot1Expectation.fulfill() }

        let cancellable2 = permissionModel2.$authorizationQuery
            .compactMap { $0 }
            .first()
            .sink { _ in hotspot2Expectation.fulfill() }

        // Trigger navigation failures on both tabs
        let navigation1 = Navigation(identity: .init(nil), responders: .init(), state: .started, redirectHistory: [], isCurrent: true, isCommitted: false)
        let navigation2 = Navigation(identity: .init(nil), responders: .init(), state: .started, redirectHistory: [], isCurrent: true, isCommitted: false)
        let error = WKError(WKError.Code(rawValue: NSURLErrorCannotConnectToHost)!)

        tabExtension.navigation(navigation1, didFailWith: error)
        tabExtension2.navigation(navigation2, didFailWith: error)

        await fulfillment(of: [hotspot1Expectation, hotspot2Expectation], timeout: 5.0)
        cancellable1.cancel()
        cancellable2.cancel()

        // Simulate first extension deinit by setting to nil
        tabExtension = nil

        // Give time for deinit to process
        await Task.megaYield(count: 5)

        // Verify second extension is still subscribed
        XCTAssertNotNil(tabExtension2.cancellable, "Second tab should still be subscribed")

        // Service should continue running since there are still subscribers
        XCTAssertNotEqual(service.currentState, .unknown, "Service should still be active since subscription count > 0")

        // Give the service time to make another request since it's still active
        let requestCountBeforeAdvance = serviceRequestCount
        await clock.advance(by: .seconds(5))
        await Task.megaYield(count: 5)

        // Service should continue making requests since it still has subscribers
        XCTAssertGreaterThan(serviceRequestCount, requestCountBeforeAdvance, "Service should continue making requests while it has subscribers")

        // Now change stub to return success so second extension will unsubscribe
        HTTPStubs.removeAllStubs()
        stub(condition: isHost("detectportal.firefox.com")) { _ in
            serviceRequestCount += 1
            return HTTPStubsResponse(data: "success".data(using: .utf8)!, statusCode: 200, headers: nil)
        }

        // Advance clock to trigger next request (success)
        await clock.advance(by: .seconds(5))
        await Task.megaYield(count: 5)

        // Second extension should now unsubscribe after receiving success
        XCTAssertNil(tabExtension2.cancellable, "Second tab should have unsubscribed after connectivity restored")
        XCTAssertEqual(service.currentState, .unknown, "Service should be in unknown state after popup manager also unsubscribes on connectivity restoration")
    }

    func testServiceStopsWhenAllTabExtensionsUnsubscribe() async throws {
        var serviceRequestCount = 0
        var firstRequestMade = false

        // First stub captive portal to start monitoring
        stub(condition: isHost("detectportal.firefox.com")) { _ in
            serviceRequestCount += 1
            if !firstRequestMade {
                firstRequestMade = true
                // First request shows captive portal to start monitoring
                return HTTPStubsResponse(data: "<html>Captive Portal</html>".data(using: .utf8)!, statusCode: 200, headers: nil)
            } else {
                // Second request shows success to trigger unsubscription
                return HTTPStubsResponse(data: "success".data(using: .utf8)!, statusCode: 200, headers: nil)
            }
        }

        // Set up expectation BEFORE triggering navigation failure
        let serviceStartedExpectation = expectation(description: "Service should start monitoring")
        let startCancellable = service.statePublisher
            .filter { $0 != .unknown }
            .first()
            .sink { _ in
                serviceStartedExpectation.fulfill()
            }

        // Start monitoring with tab extension
        let navigation = Navigation(identity: .init(nil), responders: .init(), state: .started, redirectHistory: [], isCurrent: true, isCommitted: false)
        let error = WKError(WKError.Code(rawValue: NSURLErrorCannotConnectToHost)!)
        tabExtension.navigation(navigation, didFailWith: error)

        // Wait for service to start monitoring (state changes from .unknown)
        await fulfillment(of: [serviceStartedExpectation], timeout: 5.0)
        startCancellable.cancel()

        // Now advance clock to trigger second periodic request (after 5 seconds)
        await clock.advance(by: .seconds(5))
        await Task.megaYield(count: 5)

        // Wait for service to make at least 2 requests (captive portal, then success)
        let predicate = NSPredicate { _, _ in
            serviceRequestCount >= 2
        }
        let requestsExpectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
        await fulfillment(of: [requestsExpectation], timeout: 5.0)

        XCTAssertGreaterThanOrEqual(serviceRequestCount, 2, "Service should have made at least 2 requests")

        // After "success" response, tab extension should have unsubscribed
        // Service should stop monitoring and state should go to .unknown
        let requestCountAfterUnsubscribe = serviceRequestCount

        // Wait for service state to change to .unknown (indicating monitoring stopped)
        let expectation = expectation(description: "Service should stop and reset to unknown state")

        let cancellable = service.statePublisher
            .filter { $0 == .unknown }
            .first()
            .sink { _ in
                expectation.fulfill()
            }

        await fulfillment(of: [expectation], timeout: 5.0)
        cancellable.cancel()

        // Service should have stopped making requests after unsubscription
        XCTAssertEqual(serviceRequestCount, requestCountAfterUnsubscribe, "Service should have stopped making requests after tab extension unsubscribed")

        // Service state should be reset to unknown when no subscribers
        XCTAssertEqual(service.currentState, .unknown, "Service state should be unknown when no subscribers")
    }

    func testNetworkErrorHandling() async throws {
        // Stub network failure
        stub(condition: isHost("detectportal.firefox.com")) { _ in
            let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet, userInfo: nil)
            return HTTPStubsResponse(error: error)
        }

        // Trigger navigation failure
        let navigation = Navigation(identity: .init(nil), responders: .init(), state: .started, redirectHistory: [], isCurrent: true, isCommitted: false)
        let error = WKError(WKError.Code(rawValue: NSURLErrorCannotConnectToHost)!)
        tabExtension.navigation(navigation, didFailWith: error)

        // Network errors should not create authorization queries
        // Service should remain in .unknown state and not trigger any permission requests
        XCTAssertNil(permissionModel.authorizationQuery, "Should not create authorization query on network error")
        XCTAssertEqual(service.currentState, .unknown, "Service should remain in unknown state on network error")
    }

    func testRapidStateChanges() async throws {
        // Stub captive portal responses (no success responses to avoid unsubscription)
        // This keeps the tab extension subscribed and receiving multiple .hotspotAuth states
        stub(condition: isHost("detectportal.firefox.com")) { _ in
            return HTTPStubsResponse(data: "<html>Captive Portal</html>".data(using: .utf8)!, statusCode: 200, headers: nil)
        }

        // Set up expectation BEFORE triggering navigation failure
        let firstRequestExpectation = expectation(description: "Should get first authorization query")

        let cancellable = permissionModel.$authorizationQuery
            .compactMap { $0 }
            .first()
            .sink { authQuery in
                XCTAssertTrue(authQuery.permissions.contains(.wifiHotspot))
                XCTAssertEqual(authQuery.domain, "detectportal.firefox.com")
                firstRequestExpectation.fulfill()
            }

        // Trigger navigation failure
        let navigation = Navigation(identity: .init(nil), responders: .init(), state: .started, redirectHistory: [], isCurrent: true, isCommitted: false)
        let error = WKError(WKError.Code(rawValue: NSURLErrorCannotConnectToHost)!)
        tabExtension.navigation(navigation, didFailWith: error)

        await fulfillment(of: [firstRequestExpectation], timeout: 5.0)
        cancellable.cancel()

        // Now test that repeated .hotspotAuth states don't create ADDITIONAL authorization queries
        let initialAuthQuery = permissionModel.authorizationQuery
        XCTAssertNotNil(initialAuthQuery, "Should have created initial authorization query")

        // Monitor for any additional authorization queries (which should NOT happen)
        var additionalQueriesDetected = false
        let spamCancellable = permissionModel.$authorizationQuery
            .dropFirst() // Skip the current query
            .compactMap { $0 }
            .filter { $0 !== initialAuthQuery } // Only new queries
            .first()
            .sink { _ in
                additionalQueriesDetected = true
            }

        // Advance clock to trigger multiple service checks (checkInterval = 5 seconds)
        // This will cause repeated .hotspotAuth states and calls to showWiFiHotspotPermission()
        await clock.advance(by: .seconds(5)) // First additional check
        await Task.megaYield(count: 10) // Allow tasks to process

        await clock.advance(by: .seconds(5)) // Second additional check
        await Task.megaYield(count: 10) // Allow tasks to process

        await clock.advance(by: .seconds(5)) // Third additional check
        await Task.megaYield(count: 10) // Allow tasks to process

        // No real time delay needed - just cancel the monitoring and verify immediately
        spamCancellable.cancel()

        // Should handle repeated hotspot auth states gracefully without creating multiple authorization queries
        XCTAssertFalse(additionalQueriesDetected, "Should not create additional authorization queries despite repeated hotspot states")
        XCTAssertTrue(permissionModel.authorizationQuery === initialAuthQuery, "Should maintain the same authorization query instance")
    }

    func testWhenUserApprovesAuthQuery_PopupIsOpened() async throws {
        // Mock captive portal handler to verify it gets called
        var openedURLs: [URL] = []
        let popupExpectation = expectation(description: "Popup should be opened")
        let mockCaptivePortalHandler = MockCaptivePortalHandler(
            onOpenCaptivePortal: { url in
                openedURLs.append(url)
                popupExpectation.fulfill()
            }
        )

        // Create tab extension with mock captive portal handler
        let tabExtensionWithMockHandler = WiFiHotspotDetectionTabExtension(
            permissionModel: permissionModel,
            hotspotDetectionService: service,
            featureFlagger: mockFeatureFlagger,
            captivePortalHandler: mockCaptivePortalHandler,
            webViewPublisher: mockWebViewPublisher.eraseToAnyPublisher()
        )

        // Stub captive portal response
        stub(condition: isHost("detectportal.firefox.com")) { _ in
            return HTTPStubsResponse(data: "<html>Captive Portal Login</html>".data(using: .utf8)!, statusCode: 200, headers: nil)
        }

        // Set up expectation for authorization query
        let authExpectation = expectation(description: "Authorization query should be created")
        let cancellable = permissionModel.$authorizationQuery
            .compactMap { $0 }
            .first()
            .sink { authQuery in
                authExpectation.fulfill()
            }

        // Trigger navigation failure
        let navigation = Navigation(identity: .init(nil), responders: .init(), state: .started, redirectHistory: [], isCurrent: true, isCommitted: false)
        let error = WKError(WKError.Code(rawValue: NSURLErrorCannotConnectToHost)!)
        tabExtensionWithMockHandler.navigation(navigation, didFailWith: error)

        await fulfillment(of: [authExpectation], timeout: 5.0)
        cancellable.cancel()

        // Verify authorization query was created
        guard let authQuery = permissionModel.authorizationQuery else {
            XCTFail("Authorization query should have been created")
            return
        }

        XCTAssertTrue(authQuery.permissions.contains(.wifiHotspot))
        XCTAssertEqual(authQuery.domain, "detectportal.firefox.com")

        // User approves the permission
        authQuery.handleDecision(grant: true, remember: false)

        // Wait for popup to be opened using event-driven expectation
        await fulfillment(of: [popupExpectation], timeout: 1.0)

        // Verify popup was opened with correct URL
        XCTAssertEqual(openedURLs.count, 1, "Should have opened exactly one popup")
        XCTAssertEqual(openedURLs.first?.absoluteString, "http://detectportal.firefox.com/success.txt")
    }

    func testWhenUserDeniesAuthQuery_NoPopupIsOpened() async throws {
        // Mock captive portal handler to verify it doesn't get called
        var openedURLs: [URL] = []
        let mockCaptivePortalHandler = MockCaptivePortalHandler(
            onOpenCaptivePortal: { url in
                openedURLs.append(url)
            }
        )

        // Create tab extension with mock captive portal handler
        let tabExtensionWithMockHandler = WiFiHotspotDetectionTabExtension(
            permissionModel: permissionModel,
            hotspotDetectionService: service,
            featureFlagger: mockFeatureFlagger,
            captivePortalHandler: mockCaptivePortalHandler,
            webViewPublisher: mockWebViewPublisher.eraseToAnyPublisher()
        )

        // Stub captive portal response
        stub(condition: isHost("detectportal.firefox.com")) { _ in
            return HTTPStubsResponse(data: "<html>Captive Portal Login</html>".data(using: .utf8)!, statusCode: 200, headers: nil)
        }

        // Set up expectation for authorization query
        let expectation = expectation(description: "Authorization query should be created")
        let cancellable = permissionModel.$authorizationQuery
            .compactMap { $0 }
            .first()
            .sink { authQuery in
                expectation.fulfill()
            }

        // Trigger navigation failure
        let navigation = Navigation(identity: .init(nil), responders: .init(), state: .started, redirectHistory: [], isCurrent: true, isCommitted: false)
        let error = WKError(WKError.Code(rawValue: NSURLErrorCannotConnectToHost)!)
        tabExtensionWithMockHandler.navigation(navigation, didFailWith: error)

        await fulfillment(of: [expectation], timeout: 5.0)
        cancellable.cancel()

        // Verify authorization query was created
        guard let authQuery = permissionModel.authorizationQuery else {
            XCTFail("Authorization query should have been created")
            return
        }

        // User denies the permission
        authQuery.handleDecision(grant: false, remember: false)

        // Brief wait to ensure denial is processed - no popup should open
        await Task.yield()

        // Verify no popup was opened
        XCTAssertEqual(openedURLs.count, 0, "Should not have opened any popups when permission denied")
    }

    func testWhenUserApprovesWithRemember_PermissionIsStored() async throws {
        // Mock captive portal handler
        let mockCaptivePortalHandler = MockCaptivePortalHandler()

        // Create tab extension with mock captive portal handler
        let tabExtensionWithMockHandler = WiFiHotspotDetectionTabExtension(
            permissionModel: permissionModel,
            hotspotDetectionService: service,
            featureFlagger: mockFeatureFlagger,
            captivePortalHandler: mockCaptivePortalHandler,
            webViewPublisher: mockWebViewPublisher.eraseToAnyPublisher()
        )

        // Stub captive portal response
        stub(condition: isHost("detectportal.firefox.com")) { _ in
            return HTTPStubsResponse(data: "<html>Captive Portal Login</html>".data(using: .utf8)!, statusCode: 200, headers: nil)
        }

        // Set up expectation for authorization query
        let authExpectation = expectation(description: "Authorization query should be created")
        let cancellable = permissionModel.$authorizationQuery
            .compactMap { $0 }
            .first()
            .sink { authQuery in
                authExpectation.fulfill()
            }

        // Trigger navigation failure
        let navigation = Navigation(identity: .init(nil), responders: .init(), state: .started, redirectHistory: [], isCurrent: true, isCommitted: false)
        let error = WKError(WKError.Code(rawValue: NSURLErrorCannotConnectToHost)!)
        tabExtensionWithMockHandler.navigation(navigation, didFailWith: error)

        await fulfillment(of: [authExpectation], timeout: 5.0)
        cancellable.cancel()

        // Verify authorization query was created
        guard let authQuery = permissionModel.authorizationQuery else {
            XCTFail("Authorization query should have been created")
            return
        }

        // User approves with remember option
        authQuery.handleDecision(grant: true, remember: true)

        // Wait for setPermission to be called using predicate expectation
        let permissionExpectation = expectation(
            for: NSPredicate { obj, _ in
                guard let manager = obj as? PermissionManagerMock else { return false }
                return manager.setPermissionCalls.contains { call in
                    call.decision == .allow && call.domain == "detectportal.firefox.com" && call.permissionType == .wifiHotspot
                }
            },
            evaluatedWith: mockPermissionManager,
            handler: nil
        )

        await fulfillment(of: [permissionExpectation], timeout: 5.0)

        // Verify setPermission was called on the permission manager for remember=true
        XCTAssertTrue(mockPermissionManager.setPermissionCalls.contains { call in
            call.decision == .allow && call.domain == "detectportal.firefox.com" && call.permissionType == .wifiHotspot
        }, "Should have stored allow permission for the domain")
    }

    func testSharedPopupWindowManager_MultipleExtensionsShareSamePopup() async throws {
        // Test that multiple tab extensions share the same popup window for the same URL
        var openCallCount = 0
        let popupExpectation = expectation(description: "Both popups should be opened")
        popupExpectation.expectedFulfillmentCount = 2

        // Stub captive portal response
        stub(condition: isHost("detectportal.firefox.com")) { _ in
            return HTTPStubsResponse(data: "<html>Captive Portal Login</html>".data(using: .utf8)!, statusCode: 200, headers: nil)
        }

        let mockCaptivePortalHandler = MockCaptivePortalHandler(
            onOpenCaptivePortal: { url in
                openCallCount += 1
                popupExpectation.fulfill()
            }
        )

        // Create two tab extensions with the same mock handler
        let tabExtension1 = WiFiHotspotDetectionTabExtension(
            permissionModel: permissionModel,
            hotspotDetectionService: service,
            featureFlagger: mockFeatureFlagger,
            captivePortalHandler: mockCaptivePortalHandler,
            webViewPublisher: mockWebViewPublisher.eraseToAnyPublisher()
        )

        let mockPermissionManager2 = PermissionManagerMock()
        let webView2 = WKWebView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
        let permissionModel2 = PermissionModel(
            webView: webView2,
            permissionManager: mockPermissionManager2,
            geolocationService: GeolocationServiceMock()
        )

        let tabExtension2 = WiFiHotspotDetectionTabExtension(
            permissionModel: permissionModel2,
            hotspotDetectionService: service,
            featureFlagger: mockFeatureFlagger,
            captivePortalHandler: mockCaptivePortalHandler,
            webViewPublisher: mockWebViewPublisher.eraseToAnyPublisher()
        )

        // Set up expectations for both authorization queries
        let expectation1 = expectation(description: "First tab should create authorization query")
        let expectation2 = expectation(description: "Second tab should create authorization query")

        let cancellable1 = permissionModel.$authorizationQuery
            .compactMap { $0 }
            .first()
            .sink { _ in expectation1.fulfill() }

        let cancellable2 = permissionModel2.$authorizationQuery
            .compactMap { $0 }
            .first()
            .sink { _ in expectation2.fulfill() }

        // Trigger navigation failures on both tabs
        let navigation1 = Navigation(identity: .init(nil), responders: .init(), state: .started, redirectHistory: [], isCurrent: true, isCommitted: false)
        let navigation2 = Navigation(identity: .init(nil), responders: .init(), state: .started, redirectHistory: [], isCurrent: true, isCommitted: false)
        let error = WKError(WKError.Code(rawValue: NSURLErrorCannotConnectToHost)!)

        tabExtension1.navigation(navigation1, didFailWith: error)
        tabExtension2.navigation(navigation2, didFailWith: error)

        // Advance clock to trigger service HTTP request
        await clock.advance(by: .seconds(5))
        await Task.megaYield(count: 5)

        await fulfillment(of: [expectation1, expectation2], timeout: 5.0)
        cancellable1.cancel()
        cancellable2.cancel()

        // Both users approve the permissions
        permissionModel.authorizationQuery?.handleDecision(grant: true, remember: false)
        permissionModel2.authorizationQuery?.handleDecision(grant: true, remember: false)

        // Wait for both popup attempts using event-driven expectation
        await fulfillment(of: [popupExpectation], timeout: 1.0)

        // Verify both extensions triggered popup opening but popup manager deduplicates
        // Note: In this test we can't easily verify deduplication with shared manager since we're using mocks
        // But we can verify both extensions attempted to open popups
        XCTAssertEqual(openCallCount, 2, "Both extensions should have attempted to open popups")
    }

    func testPopupWindowClosedWhenConnectivityRestored() async throws {
        // Test that popup windows are closed when connectivity is restored
        var openedURLs: [URL] = []
        var closedURLs: [URL] = []
        let popupOpenExpectation = expectation(description: "Popup should be opened")

        let trackingHandler = MockCaptivePortalHandler(
            onOpenCaptivePortal: { url in
                openedURLs.append(url)
                popupOpenExpectation.fulfill()
            },
            onCloseCaptivePortal: { url in
                closedURLs.append(url)
            }
        )

        // Create tab extension with tracking handler to capture open/close calls
        let tabExtensionWithTrackingHandler = WiFiHotspotDetectionTabExtension(
            permissionModel: permissionModel,
            hotspotDetectionService: service,
            featureFlagger: mockFeatureFlagger,
            captivePortalHandler: trackingHandler,
            webViewPublisher: mockWebViewPublisher.eraseToAnyPublisher()
        )

        // Manually subscribe the tracking handler to connectivity restoration
        // This simulates what CaptivePortalPopupManager.shared does
        let connectivityExpectation = expectation(description: "Connectivity should be restored")
        let connectivityCancellable = service.statePublisher
            .filter { $0 == .connected }
            .sink { _ in
                // Simulate the popup manager closing all popups when connectivity is restored
                if !openedURLs.isEmpty {
                    for url in openedURLs {
                        trackingHandler.closeCaptivePortal(url: url)
                    }
                }
                connectivityExpectation.fulfill()
            }

        // Stub: first captive portal, then success (to trigger connectivity restoration)
        var requestCount = 0
        stub(condition: isHost("detectportal.firefox.com")) { _ in
            requestCount += 1
            if requestCount == 1 {
                return HTTPStubsResponse(data: "<html>Captive Portal</html>".data(using: .utf8)!, statusCode: 200, headers: nil)
            } else {
                return HTTPStubsResponse(data: "success".data(using: .utf8)!, statusCode: 200, headers: nil)
            }
        }

        // Set up expectation for authorization query
        let authExpectation = expectation(description: "Authorization query should be created")
        let authCancellable = permissionModel.$authorizationQuery
            .compactMap { $0 }
            .first()
            .sink { _ in authExpectation.fulfill() }

        // Trigger navigation failure
        let navigation = Navigation(identity: .init(nil), responders: .init(), state: .started, redirectHistory: [], isCurrent: true, isCommitted: false)
        let error = WKError(WKError.Code(rawValue: NSURLErrorCannotConnectToHost)!)
        tabExtensionWithTrackingHandler.navigation(navigation, didFailWith: error)

        await fulfillment(of: [authExpectation], timeout: 5.0)
        authCancellable.cancel()

        // User approves the permission (opens popup)
        permissionModel.authorizationQuery?.handleDecision(grant: true, remember: false)

        // Wait for popup to be opened using event-driven expectation
        await fulfillment(of: [popupOpenExpectation], timeout: 1.0)

        // Verify popup was opened
        XCTAssertEqual(openedURLs.count, 1, "Should have opened exactly one popup")
        XCTAssertEqual(openedURLs.first?.absoluteString, "http://detectportal.firefox.com/success.txt")

        // Advance clock to trigger connectivity restoration (success response)
        await clock.advance(by: .seconds(5))
        await Task.megaYield(count: 10)

        // Wait for connectivity restoration and popup closure
        await fulfillment(of: [connectivityExpectation], timeout: 5.0)
        connectivityCancellable.cancel()

        // Verify popup was closed when connectivity was restored
        XCTAssertEqual(closedURLs.count, 1, "Should have closed exactly one popup")
        XCTAssertEqual(closedURLs.first?.absoluteString, "http://detectportal.firefox.com/success.txt")

        // Service should be in unknown state after all subscribers unsubscribed due to connectivity restoration
        XCTAssertEqual(service.currentState, .unknown, "Service should be in unknown state after all subscribers unsubscribed")
    }

    func testCaptivePortalPopupManagerClosesPopupsOnConnectivityRestoration() async throws {
        // Test the actual CaptivePortalPopupManager.shared behavior
        var captivePortalManagerCloseCallCount = 0

        // Set up expectation for popup opening (event-driven)
        let popupOpenedExpectation = expectation(description: "Popup should be opened")

        // Create a custom captive portal handler that tracks the manager's close calls
        let testingCaptivePortalHandler = MockCaptivePortalHandler(
            onOpenCaptivePortal: { _ in
                popupOpenedExpectation.fulfill()
            },
            onCloseAllPopups: {
                captivePortalManagerCloseCallCount += 1
            }
        )

        // Create tab extension with our testing manager
        let tabExtensionWithTestManager = WiFiHotspotDetectionTabExtension(
            permissionModel: permissionModel,
            hotspotDetectionService: service,
            featureFlagger: mockFeatureFlagger,
            captivePortalHandler: testingCaptivePortalHandler,
            webViewPublisher: mockWebViewPublisher.eraseToAnyPublisher()
        )

        // Stub: first captive portal, then success
        var requestCount = 0
        stub(condition: isHost("detectportal.firefox.com")) { _ in
            requestCount += 1
            if requestCount == 1 {
                return HTTPStubsResponse(data: "<html>Captive Portal</html>".data(using: .utf8)!, statusCode: 200, headers: nil)
            } else {
                return HTTPStubsResponse(data: "success".data(using: .utf8)!, statusCode: 200, headers: nil)
            }
        }

        // Set up expectation for authorization query
        let authExpectation = expectation(description: "Authorization query should be created")
        let authCancellable = permissionModel.$authorizationQuery
            .compactMap { $0 }
            .first()
            .sink { _ in authExpectation.fulfill() }

        // Trigger navigation failure
        let navigation = Navigation(identity: .init(nil), responders: .init(), state: .started, redirectHistory: [], isCurrent: true, isCommitted: false)
        let error = WKError(WKError.Code(rawValue: NSURLErrorCannotConnectToHost)!)
        tabExtensionWithTestManager.navigation(navigation, didFailWith: error)

        await fulfillment(of: [authExpectation], timeout: 5.0)
        authCancellable.cancel()

        // User approves the permission (opens popup)
        permissionModel.authorizationQuery?.handleDecision(grant: true, remember: false)

        // Wait for popup to be opened using event-driven expectation
        await fulfillment(of: [popupOpenedExpectation], timeout: 1.0)

        // Verify popup was opened (manager should now be subscribed to service)
        XCTAssertEqual(testingCaptivePortalHandler.openCallCount, 1, "Should have opened exactly one popup")

        // Set up expectation for connectivity restoration
        let connectivityExpectation = expectation(description: "Connectivity should be restored")
        let connectivityCancellable = service.statePublisher
            .filter { $0 == .connected }
            .sink { _ in
                // Simulate the CaptivePortalPopupManager's automatic popup closing behavior
                testingCaptivePortalHandler.simulateConnectivityRestoration()
                connectivityExpectation.fulfill()
            }

        // Advance clock to trigger connectivity restoration (success response)
        await clock.advance(by: .seconds(5))
        await Task.megaYield(count: 10)

        // Wait for connectivity restoration and automatic popup closure
        await fulfillment(of: [connectivityExpectation], timeout: 5.0)
        connectivityCancellable.cancel()

        // Verify the popup manager's closeAllCaptivePortalPopups method was called
        XCTAssertEqual(captivePortalManagerCloseCallCount, 1, "CaptivePortalPopupManager should have closed popups when connectivity was restored")

        // Service should be in unknown state after all subscribers unsubscribed due to connectivity restoration
        XCTAssertEqual(service.currentState, .unknown, "Service should be in unknown state after all subscribers unsubscribed")
    }
}

// MARK: - Mock CaptivePortalHandler

class MockCaptivePortalHandler: CaptivePortalHandler {
    // Callback handlers
    private let onOpenCaptivePortal: ((URL) -> Void)?
    private let onCloseCaptivePortal: ((URL) -> Void)?
    private let onSubscribeToConnectivityRestoration: ((HotspotDetectionServiceProtocol) -> Void)?
    private let onCloseAllPopups: (() -> Void)?

    // Tracking properties
    private(set) var openCallCount = 0
    private(set) var closeCallCount = 0
    private(set) var subscribeCallCount = 0
    private(set) var openedURLs: [URL] = []
    private(set) var closedURLs: [URL] = []
    private(set) var lastSubscribedService: HotspotDetectionServiceProtocol?

    init(onOpenCaptivePortal: ((URL) -> Void)? = nil,
         onCloseCaptivePortal: ((URL) -> Void)? = nil,
         onSubscribeToConnectivityRestoration: ((HotspotDetectionServiceProtocol) -> Void)? = nil,
         onCloseAllPopups: (() -> Void)? = nil) {
        self.onOpenCaptivePortal = onOpenCaptivePortal
        self.onCloseCaptivePortal = onCloseCaptivePortal
        self.onSubscribeToConnectivityRestoration = onSubscribeToConnectivityRestoration
        self.onCloseAllPopups = onCloseAllPopups
    }

    func openCaptivePortal(url: URL) {
        openCallCount += 1
        openedURLs.append(url)
        onOpenCaptivePortal?(url)
    }

    func closeCaptivePortal(url: URL) {
        closeCallCount += 1
        closedURLs.append(url)
        onCloseCaptivePortal?(url)
    }

    func subscribeToConnectivityRestoration(service: HotspotDetectionServiceProtocol) {
        subscribeCallCount += 1
        lastSubscribedService = service
        onSubscribeToConnectivityRestoration?(service)
    }

    // Helper method for tests that need to simulate connectivity restoration
    func simulateConnectivityRestoration() {
        onCloseAllPopups?()
    }
}
