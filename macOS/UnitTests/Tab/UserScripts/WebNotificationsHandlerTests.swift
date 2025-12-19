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
import Combine
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

/// Mock permission model for isolated testing of permission flows.
final class MockWebNotificationPermissionModel: WebNotificationPermissionProviding {

    var isPermissionGrantedResult = true
    var requestPermissionResult = true

    private(set) var isPermissionGrantedCalled = false
    private(set) var requestCalled = false
    private(set) var lastRequestedDomain: String?

    func isPermissionGranted(_ permission: PermissionType, forDomain domain: String) -> Bool {
        isPermissionGrantedCalled = true
        lastRequestedDomain = domain
        return isPermissionGrantedResult
    }

    func request(_ permissions: [PermissionType], forDomain domain: String, url: URL?) -> Future<Bool, Never> {
        requestCalled = true
        lastRequestedDomain = domain
        return Future { [weak self] fulfill in
            fulfill(.success(self?.requestPermissionResult ?? false))
        }
    }
}

/// Mock WKWebView that returns a specific URL for testing permission checks.
private final class WebNotificationMockURLWebView: WKWebView {
    private let mockedURL: URL

    init(url: URL, configuration: WKWebViewConfiguration = WKWebViewConfiguration()) {
        self.mockedURL = url
        super.init(frame: .zero, configuration: configuration)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var url: URL? { mockedURL }

    /// Creates a mock webView simulating a Fire Window (non-persistent data store)
    static func fireWindow(url: URL = URL(string: "https://example.com")!) -> WebNotificationMockURLWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        return WebNotificationMockURLWebView(url: url, configuration: config)
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
        let effectiveWebView = webView ?? WebNotificationMockURLWebView(url: URL(string: "https://example.com")!)
        self.mockedName = name
        self.mockedBody = body
        self.mockedWebView = effectiveWebView
        self.mockedFrameInfo = frameInfo ?? WKFrameInfoMock(
            webView: effectiveWebView,
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
    var mockPermissionModel: MockWebNotificationPermissionModel!
    var handler: WebNotificationsHandler!
    let testTabUUID = "test-tab-uuid-123"

    override func setUp() {
        super.setUp()
        mockNotificationService = MockWebNotificationService()
        mockIconFetcher = MockNotificationIconFetcher()
        mockPermissionModel = MockWebNotificationPermissionModel()
        mockFeatureFlagger = MockFeatureFlagger()
        mockFeatureFlagger.enableFeatures([.webNotifications, .newPermissionView])
        handler = WebNotificationsHandler(
            tabUUID: testTabUUID,
            notificationService: mockNotificationService,
            iconFetcher: mockIconFetcher,
            featureFlagger: mockFeatureFlagger)
        handler.permissionModel = mockPermissionModel
    }

    override func tearDown() {
        handler = nil
        mockIconFetcher = nil
        mockNotificationService = nil
        mockPermissionModel = nil
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
        let mockMessage = await WebNotificationMockScriptMessage(name: "webCompat", body: params)

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
        let mockMessage = await WebNotificationMockScriptMessage(name: "webCompat", body: params)

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
        let mockMessage = await WebNotificationMockScriptMessage(name: "webCompat", body: params)

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
        let mockMessage = await WebNotificationMockScriptMessage(name: "webCompat", body: params)

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
        let mockMessage = await WebNotificationMockScriptMessage(name: "webCompat", body: params)

        let handlerFunc = handler.handler(forMethodNamed: "requestPermission")
        let result = try? await handlerFunc?(params, mockMessage)

        guard let response = result as? WebNotificationsHandler.RequestPermissionResponse else {
            XCTFail("Expected RequestPermissionResponse")
            return
        }
        XCTAssertEqual(response.permission, "denied")
    }

    func testWhenInFireWindowWithSystemAuthThenRequestPermissionReturnsGranted() async throws {
        // Fire Windows use PermissionManager like normal windows; permissions cleared on burn
        mockNotificationService.authorizationStatusToReturn = .authorized
        let params: [String: Any] = [:]

        let fireWindowWebView = await WebNotificationMockURLWebView.fireWindow()
        let mockMessage = await WebNotificationMockScriptMessage(name: "webCompat", body: params, webView: fireWindowWebView)

        let handlerFunc = handler.handler(forMethodNamed: "requestPermission")
        let result = try await handlerFunc?(params, mockMessage)

        guard let response = result as? WebNotificationsHandler.RequestPermissionResponse else {
            XCTFail("Expected RequestPermissionResponse")
            return
        }
        XCTAssertEqual(response.permission, "granted")
    }

    func testWhenInFireWindowWithSystemDeniedThenRequestPermissionReturnsDenied() async throws {
        // Fire Windows use PermissionManager like normal windows; permissions cleared on burn
        mockNotificationService.authorizationStatusToReturn = .denied
        let params: [String: Any] = [:]

        let fireWindowWebView = await WebNotificationMockURLWebView.fireWindow()
        let mockMessage = await WebNotificationMockScriptMessage(name: "webCompat", body: params, webView: fireWindowWebView)

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
        let mockMessage = await WebNotificationMockScriptMessage(name: "webCompat", body: params)

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
        let mockMessage = await WebNotificationMockScriptMessage(name: "webCompat", body: params)

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
        let mockMessage = await WebNotificationMockScriptMessage(name: "webCompat", body: params)

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
        let mockMessage = await WebNotificationMockScriptMessage(name: "webCompat", body: params)

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
        let mockMessage = await WebNotificationMockScriptMessage(name: "webCompat", body: params)

        let handlerFunc = handler.handler(forMethodNamed: "showNotification")
        _ = try? await handlerFunc?(params, mockMessage)

        XCTAssertTrue(mockNotificationService.addedRequests.isEmpty)
    }

    @MainActor
    func testWhenInFireWindowWithSystemAuthThenShowNotificationPosts() async {
        // Fire Windows use PermissionManager like normal windows; permissions cleared on burn
        mockNotificationService.authorizationStatusToReturn = .authorized
        let params: [String: Any] = [
            "id": "test-id-fire",
            "title": "Fire Window Test"
        ]

        let fireWindowWebView = WebNotificationMockURLWebView.fireWindow()
        let mockMessage = WebNotificationMockScriptMessage(name: "webCompat", body: params, webView: fireWindowWebView)

        let handlerFunc = handler.handler(forMethodNamed: "showNotification")
        _ = try? await handlerFunc?(params, mockMessage)

        XCTAssertEqual(mockNotificationService.addedRequests.count, 1)
    }

    func testWhenInFireWindowWithSystemDeniedThenShowNotificationIsBlocked() async {
        // Fire Windows use PermissionManager like normal windows; permissions cleared on burn
        mockNotificationService.authorizationStatusToReturn = .denied
        let params: [String: Any] = [
            "id": "test-id-fire",
            "title": "Fire Window Test"
        ]

        let fireWindowWebView = await WebNotificationMockURLWebView.fireWindow()
        let mockMessage = await WebNotificationMockScriptMessage(name: "webCompat", body: params, webView: fireWindowWebView)

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
        let mockMessage = await WebNotificationMockScriptMessage(name: "webCompat", body: params)

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

    /// When permission model returns false for isPermissionGranted, notification should be blocked.
    func testWhenPermissionModelDeniesPermissionThenShowNotificationDoesNotPost() async {
        mockNotificationService.authorizationStatusToReturn = .authorized
        mockPermissionModel.isPermissionGrantedResult = false

        let params: [String: Any] = [
            "id": "test-permission-blocked",
            "title": "Permission Blocked Test"
        ]
        let mockMessage = await WebNotificationMockScriptMessage(name: "webCompat", body: params)

        let handlerFunc = handler.handler(forMethodNamed: "showNotification")
        _ = try? await handlerFunc?(params, mockMessage)

        XCTAssertTrue(mockPermissionModel.isPermissionGrantedCalled)
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
        let mockMessage = await WebNotificationMockScriptMessage(name: "webCompat", body: params)

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
        let mockMessage = await WebNotificationMockScriptMessage(name: "webCompat", body: params)

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
        let mockMessage = await WebNotificationMockScriptMessage(name: "webCompat", body: params)

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
        let mockMessage = await WebNotificationMockScriptMessage(name: "webCompat", body: params)

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
        let mockMessage = await WebNotificationMockScriptMessage(name: "webCompat", body: [:])

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
        let mockMessage = await WebNotificationMockScriptMessage(name: "webCompat", body: params)

        let handlerFunc = handler.handler(forMethodNamed: "closeNotification")
        let result = try? await handlerFunc?(params, mockMessage)

        // closeNotification returns nil (Step 7 will implement actual removal)
        XCTAssertNil(result)
    }

    func testCloseNotificationHandlerWithInvalidParams() async {
        let params: [String: Any] = [:] // Missing required id
        let mockMessage = await WebNotificationMockScriptMessage(name: "webCompat", body: params)

        let handlerFunc = handler.handler(forMethodNamed: "closeNotification")
        let result = try? await handlerFunc?(params, mockMessage)

        XCTAssertNil(result)
    }

    func testWhenFeatureFlagDisabledThenCloseNotificationIsBlocked() async {
        mockFeatureFlagger.enableFeatures([])
        let params: [String: Any] = ["id": "test-close-flag"]
        let mockMessage = await WebNotificationMockScriptMessage(name: "webCompat", body: params)

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
        let mockMessage = await WebNotificationMockScriptMessage(name: "webCompat", body: params)

        let handlerFunc = handler.handler(forMethodNamed: "showNotification")
        _ = try? await handlerFunc?(params, mockMessage)

        let addedRequest = mockNotificationService.addedRequests.first
        XCTAssertEqual(addedRequest?.content.userInfo["notificationId"] as? String, "test-userinfo")
    }

    func testNotificationContentIncludesTabUUID() async {
        mockNotificationService.authorizationStatusToReturn = .authorized
        let params: [String: Any] = [
            "id": "test-tab-uuid",
            "title": "Tab UUID Test"
        ]
        let mockMessage = await WebNotificationMockScriptMessage(name: "webCompat", body: params)

        let handlerFunc = handler.handler(forMethodNamed: "showNotification")
        _ = try? await handlerFunc?(params, mockMessage)

        let addedRequest = mockNotificationService.addedRequests.first
        XCTAssertEqual(addedRequest?.content.userInfo["tabUUID"] as? String, testTabUUID)
    }

    // MARK: - Click Event Tests

    func testSendClickEventUsesStoredWebView() {
        let webView = WKWebView(frame: .zero)
        handler.webView = webView

        // sendClickEvent doesn't throw, it just sends to broker
        // Without a broker, it's a no-op - we're testing the method exists and uses webView
        handler.sendClickEvent(notificationId: "test-click-id")

        // The method should not crash and should use the stored webView
        XCTAssertNotNil(handler.webView)
    }

    func testSendClickEventWithNilWebViewDoesNotCrash() {
        handler.webView = nil

        // Should not crash when webView is nil
        handler.sendClickEvent(notificationId: "test-click-nil")

        XCTAssertNil(handler.webView)
    }

}
