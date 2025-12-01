//
//  WebNotificationsHandlerTests.swift
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

import BrowserServicesKit
import UserNotifications
import WebKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

// MARK: - Mock Dependencies

/// Mock notification service for isolated testing without real UNUserNotificationCenter calls.
final class MockWebNotificationService: WebNotificationService {

    var authorizationStatusToReturn: UNAuthorizationStatus = .authorized
    var requestAuthorizationResult: Bool = true
    var requestAuthorizationError: Error?
    var addNotificationError: Error?

    private(set) var requestAuthorizationCalled = false
    private(set) var requestAuthorizationOptions: UNAuthorizationOptions?
    private(set) var addedRequests: [UNNotificationRequest] = []

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        requestAuthorizationCalled = true
        requestAuthorizationOptions = options
        if let error = requestAuthorizationError {
            throw error
        }
        return requestAuthorizationResult
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        return authorizationStatusToReturn
    }

    func add(_ request: UNNotificationRequest) async throws {
        if let error = addNotificationError {
            throw error
        }
        addedRequests.append(request)
    }
}

/// Mock icon fetcher for isolated testing without network calls.
final class MockNotificationIconFetcher: NotificationIconFetching {

    var attachmentToReturn: UNNotificationAttachment?

    private(set) var fetchIconCalled = false
    private(set) var fetchedURL: URL?

    func fetchIcon(from url: URL) async -> UNNotificationAttachment? {
        fetchIconCalled = true
        fetchedURL = url
        return attachmentToReturn
    }
}

/// Mock WKScriptMessage for testing message handlers without a real WebView.
private class WebNotificationMockScriptMessage: WKScriptMessage {

    let mockedName: String
    let mockedBody: Any
    let mockedWebView: WKWebView?
    let mockedFrameInfo: WKFrameInfo

    override var name: String { mockedName }
    override var body: Any { mockedBody }
    override var webView: WKWebView? { mockedWebView }
    override var frameInfo: WKFrameInfo { mockedFrameInfo }

    init(name: String, body: Any, webView: WKWebView? = nil, frameInfo: WKFrameInfo? = nil, isMainFrame: Bool = true) {
        self.mockedName = name
        self.mockedBody = body
        self.mockedWebView = webView
        self.mockedFrameInfo = frameInfo ?? WKFrameInfoMock(
            webView: webView ?? WKWebView(frame: .zero),
            securityOrigin: WKSecurityOriginMock.new(url: URL(string: "https://example.com")!),
            request: URLRequest(url: URL(string: "https://example.com")!),
            isMainFrame: isMainFrame
        )
        super.init()
    }
}

// MARK: - Test Case

/// Tests for WebNotificationsHandler with isolated mocks.
/// Each test exercises one behavior with injected dependencies - no real UNUserNotificationCenter calls.
final class WebNotificationsHandlerTests: XCTestCase {

    var mockNotificationService: MockWebNotificationService!
    var mockIconFetcher: MockNotificationIconFetcher!
    var mockFeatureFlagger: MockFeatureFlagger!
    var handler: WebNotificationsHandler!

    override func setUp() {
        super.setUp()
        mockNotificationService = MockWebNotificationService()
        mockIconFetcher = MockNotificationIconFetcher()
        mockFeatureFlagger = MockFeatureFlagger()
        mockFeatureFlagger.enableFeatures([.webNotifications])
        handler = WebNotificationsHandler(
            notificationService: mockNotificationService,
            iconFetcher: mockIconFetcher,
            featureFlagger: mockFeatureFlagger)
    }

    override func tearDown() {
        handler = nil
        mockIconFetcher = nil
        mockNotificationService = nil
        mockFeatureFlagger = nil
        super.tearDown()
    }

    // MARK: - Configuration Tests

    func testFeatureNameIsWebNotifications() {
        XCTAssertEqual(handler.featureName, "webCompat")
    }

    func testMessageOriginPolicyIsAll() {
        // MessageOriginPolicy doesn't conform to Equatable, so check the specific case
        if case .all = handler.messageOriginPolicy {
            // Pass
        } else {
            XCTFail("Expected messageOriginPolicy to be .all")
        }
    }

    // MARK: - Handler Registration Tests

    func testHandlerExistsForShowNotification() {
        XCTAssertNotNil(handler.handler(forMethodNamed: "showNotification"))
    }

    func testHandlerExistsForCloseNotification() {
        XCTAssertNotNil(handler.handler(forMethodNamed: "closeNotification"))
    }

    func testHandlerExistsForRequestPermission() {
        XCTAssertNotNil(handler.handler(forMethodNamed: "requestPermission"))
    }

    func testHandlerReturnsNilForUnknownMethod() {
        XCTAssertNil(handler.handler(forMethodNamed: "unknownMethod"))
    }

    // MARK: - requestPermission Tests

    func testWhenSystemAuthorizationIsGrantedThenRequestPermissionReturnsGranted() async {
        mockNotificationService.authorizationStatusToReturn = .authorized
        let params: [String: Any] = [:]
        let mockMessage = WebNotificationMockScriptMessage(name: "webCompat", body: params)

        let handlerFunc = handler.handler(forMethodNamed: "requestPermission")
        let result = try? await handlerFunc?(params, mockMessage)

        guard let response = result as? WebNotificationsHandler.RequestPermissionResponse else {
            XCTFail("Expected RequestPermissionResponse")
            return
        }
        XCTAssertEqual(response.permission, "granted")
    }

    func testWhenProvisionallyAuthorizedThenRequestPermissionReturnsGranted() async {
        mockNotificationService.authorizationStatusToReturn = .provisional
        let params: [String: Any] = [:]
        let mockMessage = WebNotificationMockScriptMessage(name: "webCompat", body: params)

        let handlerFunc = handler.handler(forMethodNamed: "requestPermission")
        let result = try? await handlerFunc?(params, mockMessage)

        guard let response = result as? WebNotificationsHandler.RequestPermissionResponse else {
            XCTFail("Expected RequestPermissionResponse")
            return
        }
        XCTAssertEqual(response.permission, "granted")
    }

    func testWhenSystemAuthorizationIsDeniedThenRequestPermissionReturnsDenied() async {
        mockNotificationService.authorizationStatusToReturn = .denied
        let params: [String: Any] = [:]
        let mockMessage = WebNotificationMockScriptMessage(name: "webCompat", body: params)

        let handlerFunc = handler.handler(forMethodNamed: "requestPermission")
        let result = try? await handlerFunc?(params, mockMessage)

        guard let response = result as? WebNotificationsHandler.RequestPermissionResponse else {
            XCTFail("Expected RequestPermissionResponse")
            return
        }
        XCTAssertEqual(response.permission, "denied")
    }

    func testWhenSystemAuthorizationIsNotDeterminedThenRequestPermissionRequestsAuthorization() async {
        mockNotificationService.authorizationStatusToReturn = .notDetermined
        mockNotificationService.requestAuthorizationResult = true
        let params: [String: Any] = [:]
        let mockMessage = WebNotificationMockScriptMessage(name: "webCompat", body: params)

        let handlerFunc = handler.handler(forMethodNamed: "requestPermission")
        let result = try? await handlerFunc?(params, mockMessage)

        XCTAssertTrue(mockNotificationService.requestAuthorizationCalled)
        XCTAssertEqual(mockNotificationService.requestAuthorizationOptions, [.alert, .sound])

        guard let response = result as? WebNotificationsHandler.RequestPermissionResponse else {
            XCTFail("Expected RequestPermissionResponse")
            return
        }
        XCTAssertEqual(response.permission, "granted")
    }

    func testWhenAuthorizationRequestFailsThenRequestPermissionReturnsDenied() async {
        mockNotificationService.authorizationStatusToReturn = .notDetermined
        mockNotificationService.requestAuthorizationError = NSError(domain: "test", code: 1)
        let params: [String: Any] = [:]
        let mockMessage = WebNotificationMockScriptMessage(name: "webCompat", body: params)

        let handlerFunc = handler.handler(forMethodNamed: "requestPermission")
        let result = try? await handlerFunc?(params, mockMessage)

        guard let response = result as? WebNotificationsHandler.RequestPermissionResponse else {
            XCTFail("Expected RequestPermissionResponse")
            return
        }
        XCTAssertEqual(response.permission, "denied")
    }

    func testWhenInFireWindowThenRequestPermissionReturnsDenied() async throws {
        mockNotificationService.authorizationStatusToReturn = .authorized
        let params: [String: Any] = [:]

        // Create a webView with non-persistent data store (simulates Fire Window)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let fireWindowWebView = WKWebView(frame: .zero, configuration: config)
        let mockMessage = WebNotificationMockScriptMessage(name: "webCompat", body: params, webView: fireWindowWebView)

        let handlerFunc = handler.handler(forMethodNamed: "requestPermission")
        let result = try await handlerFunc?(params, mockMessage)

        guard let response = result as? WebNotificationsHandler.RequestPermissionResponse else {
            XCTFail("Expected RequestPermissionResponse")
            return
        }
        XCTAssertEqual(response.permission, "denied")
    }

    func testWhenFeatureFlagDisabledThenRequestPermissionReturnsDenied() async {
        mockFeatureFlagger.enableFeatures([])
        mockNotificationService.authorizationStatusToReturn = .authorized
        let params: [String: Any] = [:]
        let mockMessage = WebNotificationMockScriptMessage(name: "webCompat", body: params)

        let handlerFunc = handler.handler(forMethodNamed: "requestPermission")
        let result = try? await handlerFunc?(params, mockMessage)

        guard let response = result as? WebNotificationsHandler.RequestPermissionResponse else {
            XCTFail("Expected RequestPermissionResponse")
            return
        }
        XCTAssertEqual(response.permission, "denied")
    }

    // MARK: - showNotification Tests

    func testWhenAuthorizedThenShowNotificationPostsNotification() async {
        mockNotificationService.authorizationStatusToReturn = .authorized
        let params: [String: Any] = [
            "id": "test-id-123",
            "title": "Test Title",
            "body": "Test Body"
        ]
        let mockMessage = WebNotificationMockScriptMessage(name: "webCompat", body: params)

        let handlerFunc = handler.handler(forMethodNamed: "showNotification")
        _ = try? await handlerFunc?(params, mockMessage)

        XCTAssertEqual(mockNotificationService.addedRequests.count, 1)
        let addedRequest = mockNotificationService.addedRequests.first
        XCTAssertEqual(addedRequest?.identifier, "test-id-123")
        XCTAssertEqual(addedRequest?.content.title, "Test Title")
        XCTAssertEqual(addedRequest?.content.body, "Test Body")
    }

    func testWhenProvisionallyAuthorizedThenShowNotificationPosts() async {
        mockNotificationService.authorizationStatusToReturn = .provisional
        let params: [String: Any] = [
            "id": "test-provisional",
            "title": "Provisional Test"
        ]
        let mockMessage = WebNotificationMockScriptMessage(name: "webCompat", body: params)

        let handlerFunc = handler.handler(forMethodNamed: "showNotification")
        _ = try? await handlerFunc?(params, mockMessage)

        XCTAssertEqual(mockNotificationService.addedRequests.count, 1)
        XCTAssertEqual(mockNotificationService.addedRequests.first?.identifier, "test-provisional")
    }

    func testWhenNotDeterminedThenShowNotificationDoesNotPostOrPrompt() async {
        // showNotification should only check authorization, not prompt
        // If not yet determined, it should block without prompting
        mockNotificationService.authorizationStatusToReturn = .notDetermined
        let params: [String: Any] = [
            "id": "test-id-456",
            "title": "Test Title"
        ]
        let mockMessage = WebNotificationMockScriptMessage(name: "webCompat", body: params)

        let handlerFunc = handler.handler(forMethodNamed: "showNotification")
        _ = try? await handlerFunc?(params, mockMessage)

        XCTAssertFalse(mockNotificationService.requestAuthorizationCalled)
        XCTAssertTrue(mockNotificationService.addedRequests.isEmpty)
    }

    func testWhenAuthorizationDeniedThenShowNotificationDoesNotPost() async {
        mockNotificationService.authorizationStatusToReturn = .denied
        let params: [String: Any] = [
            "id": "test-id-789",
            "title": "Test Title"
        ]
        let mockMessage = WebNotificationMockScriptMessage(name: "webCompat", body: params)

        let handlerFunc = handler.handler(forMethodNamed: "showNotification")
        _ = try? await handlerFunc?(params, mockMessage)

        XCTAssertTrue(mockNotificationService.addedRequests.isEmpty)
    }

    @MainActor
    func testWhenInFireWindowThenShowNotificationIsBlocked() async {
        mockNotificationService.authorizationStatusToReturn = .authorized
        let params: [String: Any] = [
            "id": "test-id-fire",
            "title": "Fire Window Test"
        ]

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let fireWindowWebView = WKWebView(frame: .zero, configuration: config)
        let mockMessage = WebNotificationMockScriptMessage(name: "webCompat", body: params, webView: fireWindowWebView)

        let handlerFunc = handler.handler(forMethodNamed: "showNotification")
        _ = try? await handlerFunc?(params, mockMessage)

        XCTAssertTrue(mockNotificationService.addedRequests.isEmpty)
    }

    func testWhenFeatureFlagDisabledThenShowNotificationIsBlocked() async {
        mockFeatureFlagger.enableFeatures([])
        mockNotificationService.authorizationStatusToReturn = .authorized
        let params: [String: Any] = [
            "id": "test-flag-disabled",
            "title": "Flag Disabled Test"
        ]
        let mockMessage = WebNotificationMockScriptMessage(name: "webCompat", body: params)

        let handlerFunc = handler.handler(forMethodNamed: "showNotification")
        _ = try? await handlerFunc?(params, mockMessage)

        XCTAssertTrue(mockNotificationService.addedRequests.isEmpty)
    }

    func testWhenInvalidPayloadThenShowNotificationDoesNotPost() async {
        mockNotificationService.authorizationStatusToReturn = .authorized
        let params = "invalid string params"
        let mockMessage = await WebNotificationMockScriptMessage(name: "webCompat", body: params)

        let handlerFunc = handler.handler(forMethodNamed: "showNotification")
        _ = try? await handlerFunc?(params, mockMessage)

        XCTAssertTrue(mockNotificationService.addedRequests.isEmpty)
    }

    // MARK: - Icon Fetching Tests

    func testWhenIconURLProvidedThenIconFetcherIsCalled() async {
        mockNotificationService.authorizationStatusToReturn = .authorized
        let params: [String: Any] = [
            "id": "test-icon-id",
            "title": "Icon Test",
            "icon": "https://example.com/icon.png"
        ]
        let mockMessage = await WebNotificationMockScriptMessage(name: "webCompat", body: params)

        let handlerFunc = handler.handler(forMethodNamed: "showNotification")
        _ = try? await handlerFunc?(params, mockMessage)

        XCTAssertTrue(mockIconFetcher.fetchIconCalled)
        XCTAssertEqual(mockIconFetcher.fetchedURL?.absoluteString, "https://example.com/icon.png")
    }

    func testWhenIconFetchFailsThenNotificationStillPosts() async {
        // Icon fetch returns nil (failure) but notification should still post
        mockNotificationService.authorizationStatusToReturn = .authorized
        mockIconFetcher.attachmentToReturn = nil
        let params: [String: Any] = [
            "id": "test-icon-fail",
            "title": "Icon Fail Test",
            "icon": "https://example.com/icon.png"
        ]
        let mockMessage = WebNotificationMockScriptMessage(name: "webCompat", body: params)

        let handlerFunc = handler.handler(forMethodNamed: "showNotification")
        _ = try? await handlerFunc?(params, mockMessage)

        XCTAssertEqual(mockNotificationService.addedRequests.count, 1)
        XCTAssertTrue(mockNotificationService.addedRequests.first?.content.attachments.isEmpty ?? false)
    }

    func testWhenNoIconURLProvidedThenIconFetcherIsNotCalled() async {
        mockNotificationService.authorizationStatusToReturn = .authorized
        let params: [String: Any] = [
            "id": "test-no-icon",
            "title": "No Icon Test"
        ]
        let mockMessage = WebNotificationMockScriptMessage(name: "webCompat", body: params)

        let handlerFunc = handler.handler(forMethodNamed: "showNotification")
        _ = try? await handlerFunc?(params, mockMessage)

        XCTAssertFalse(mockIconFetcher.fetchIconCalled)
        XCTAssertEqual(mockNotificationService.addedRequests.count, 1)
    }

    func testWhenIconURLIsEmptyStringThenIconFetcherIsNotCalled() async {
        mockNotificationService.authorizationStatusToReturn = .authorized
        let params: [String: Any] = [
            "id": "test-empty-icon",
            "title": "Empty Icon Test",
            "icon": ""
        ]
        let mockMessage = WebNotificationMockScriptMessage(name: "webCompat", body: params)

        let handlerFunc = handler.handler(forMethodNamed: "showNotification")
        _ = try? await handlerFunc?(params, mockMessage)

        XCTAssertFalse(mockIconFetcher.fetchIconCalled)
        XCTAssertEqual(mockNotificationService.addedRequests.count, 1)
    }

    func testShowNotificationIncludesAllProvidedFields() async {
        mockNotificationService.authorizationStatusToReturn = .authorized
        let params: [String: Any] = [
            "id": "test-all-fields",
            "title": "Full Title",
            "body": "Full Body",
            "tag": "test-tag"
        ]
        let mockMessage = WebNotificationMockScriptMessage(name: "webCompat", body: params)

        let handlerFunc = handler.handler(forMethodNamed: "showNotification")
        _ = try? await handlerFunc?(params, mockMessage)

        XCTAssertEqual(mockNotificationService.addedRequests.count, 1)
        let request = mockNotificationService.addedRequests.first
        XCTAssertEqual(request?.identifier, "test-all-fields")
        XCTAssertEqual(request?.content.title, "Full Title")
        XCTAssertEqual(request?.content.body, "Full Body")
        XCTAssertEqual(request?.content.threadIdentifier, "test-tag")
    }

    func testMultipleNotificationsPostWithUniqueIds() async {
        mockNotificationService.authorizationStatusToReturn = .authorized
        let mockMessage = WebNotificationMockScriptMessage(name: "webCompat", body: [:])

        let handlerFunc = handler.handler(forMethodNamed: "showNotification")

        let params1: [String: Any] = ["id": "notif-1", "title": "First"]
        let params2: [String: Any] = ["id": "notif-2", "title": "Second"]
        let params3: [String: Any] = ["id": "notif-3", "title": "Third"]

        _ = try? await handlerFunc?(params1, mockMessage)
        _ = try? await handlerFunc?(params2, mockMessage)
        _ = try? await handlerFunc?(params3, mockMessage)

        XCTAssertEqual(mockNotificationService.addedRequests.count, 3)
        let ids = mockNotificationService.addedRequests.map { $0.identifier }
        XCTAssertEqual(Set(ids), Set(["notif-1", "notif-2", "notif-3"]))
    }

    // MARK: - closeNotification Tests

    func testCloseNotificationHandlerWithValidParams() async {
        let params: [String: Any] = ["id": "test-close-id"]
        let mockMessage = WebNotificationMockScriptMessage(name: "webCompat", body: params)

        let handlerFunc = handler.handler(forMethodNamed: "closeNotification")
        let result = try? await handlerFunc?(params, mockMessage)

        // closeNotification returns nil (Step 7 will implement actual removal)
        XCTAssertNil(result)
    }

    func testCloseNotificationHandlerWithInvalidParams() async {
        let params: [String: Any] = [:] // Missing required id
        let mockMessage = WebNotificationMockScriptMessage(name: "webCompat", body: params)

        let handlerFunc = handler.handler(forMethodNamed: "closeNotification")
        let result = try? await handlerFunc?(params, mockMessage)

        XCTAssertNil(result)
    }

    func testWhenFeatureFlagDisabledThenCloseNotificationIsBlocked() async {
        mockFeatureFlagger.enableFeatures([])
        let params: [String: Any] = ["id": "test-close-flag"]
        let mockMessage = WebNotificationMockScriptMessage(name: "webCompat", body: params)

        let handlerFunc = handler.handler(forMethodNamed: "closeNotification")
        let result = try? await handlerFunc?(params, mockMessage)

        // When feature flag is disabled, closeNotification should return early
        XCTAssertNil(result)
    }

    // MARK: - Notification Content Tests

    func testNotificationContentIncludesUserInfo() async {
        mockNotificationService.authorizationStatusToReturn = .authorized
        let params: [String: Any] = [
            "id": "test-userinfo",
            "title": "UserInfo Test"
        ]
        let webView = WKWebView(frame: .zero)
        let mockMessage = WebNotificationMockScriptMessage(name: "webCompat", body: params, webView: webView)

        let handlerFunc = handler.handler(forMethodNamed: "showNotification")
        _ = try? await handlerFunc?(params, mockMessage)

        let addedRequest = mockNotificationService.addedRequests.first
        XCTAssertEqual(addedRequest?.content.userInfo["notificationId"] as? String, "test-userinfo")
    }
}
