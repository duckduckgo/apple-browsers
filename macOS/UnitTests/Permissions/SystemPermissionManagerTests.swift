//
//  SystemPermissionManagerTests.swift
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

import Combine
import UserNotifications
import XCTest

@testable import DuckDuckGo_Privacy_Browser

/// Tests for SystemPermissionManager's notification authorization logic.
final class SystemPermissionManagerTests: XCTestCase {

    var mockNotificationService: UserNotificationAuthorizationServiceMock!
    var mockGeolocationService: GeolocationServiceMock!
    var sut: SystemPermissionManager!

    override func setUp() {
        super.setUp()
        mockNotificationService = UserNotificationAuthorizationServiceMock()
        mockGeolocationService = GeolocationServiceMock()
        sut = SystemPermissionManager(
            geolocationService: mockGeolocationService,
            notificationService: mockNotificationService
        )
    }

    override func tearDown() {
        sut = nil
        mockNotificationService = nil
        mockGeolocationService = nil
        super.tearDown()
    }

    // MARK: - authorizationState(for: .notification) Tests

    func testWhenNotificationStatusIsAuthorizedThenAuthorizationStateReturnsAuthorized() async {
        mockNotificationService.currentAuthorizationStatus = .authorized

        let state = await sut.authorizationState(for: .notification)

        XCTAssertEqual(state, .authorized)
    }

    func testWhenNotificationStatusIsProvisionalThenAuthorizationStateReturnsAuthorized() async {
        mockNotificationService.currentAuthorizationStatus = .provisional

        let state = await sut.authorizationState(for: .notification)

        XCTAssertEqual(state, .authorized)
    }

    func testWhenNotificationStatusIsDeniedThenAuthorizationStateReturnsDenied() async {
        mockNotificationService.currentAuthorizationStatus = .denied

        let state = await sut.authorizationState(for: .notification)

        XCTAssertEqual(state, .denied)
    }

    func testWhenNotificationStatusIsNotDeterminedThenAuthorizationStateReturnsNotDetermined() async {
        mockNotificationService.currentAuthorizationStatus = .notDetermined

        let state = await sut.authorizationState(for: .notification)

        XCTAssertEqual(state, .notDetermined)
    }

    // MARK: - isAuthorizationRequired(for: .notification) Tests

    func testWhenNotificationStatusIsAuthorizedThenAuthorizationIsNotRequired() {
        mockNotificationService.currentAuthorizationStatus = .authorized

        let required = sut.isAuthorizationRequired(for: .notification)

        XCTAssertFalse(required)
    }

    func testWhenNotificationStatusIsProvisionalThenAuthorizationIsNotRequired() {
        mockNotificationService.currentAuthorizationStatus = .provisional

        let required = sut.isAuthorizationRequired(for: .notification)

        XCTAssertFalse(required)
    }

    func testWhenNotificationStatusIsNotDeterminedThenAuthorizationIsRequired() {
        mockNotificationService.currentAuthorizationStatus = .notDetermined

        let required = sut.isAuthorizationRequired(for: .notification)

        XCTAssertTrue(required)
    }

    func testWhenNotificationStatusIsDeniedThenAuthorizationIsRequired() {
        mockNotificationService.currentAuthorizationStatus = .denied

        let required = sut.isAuthorizationRequired(for: .notification)

        XCTAssertTrue(required)
    }

    // MARK: - requestAuthorization(for: .notification) Tests

    func testWhenRequestNotificationAuthorizationSucceedsThenCompletionReceivesAuthorized() {
        let expectation = XCTestExpectation(description: "Completion called")
        mockNotificationService.requestAuthorizationResult = .success(true)

        sut.requestAuthorization(for: .notification) { state in
            XCTAssertEqual(state, .authorized)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
        XCTAssertTrue(mockNotificationService.requestAuthorizationCalled)
    }

    func testWhenRequestNotificationAuthorizationDeniedThenCompletionReceivesDenied() {
        let expectation = XCTestExpectation(description: "Completion called")
        mockNotificationService.requestAuthorizationResult = .success(false)

        sut.requestAuthorization(for: .notification) { state in
            XCTAssertEqual(state, .denied)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    func testWhenRequestNotificationAuthorizationFailsThenCompletionReceivesDenied() {
        let expectation = XCTestExpectation(description: "Completion called")
        mockNotificationService.requestAuthorizationResult = .failure(NSError(domain: "test", code: 1))

        sut.requestAuthorization(for: .notification) { state in
            XCTAssertEqual(state, .denied)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Non-notification permission types

    func testWhenNonSystemPermissionTypeThenAuthorizationStateReturnsAuthorized() async {
        let state = await sut.authorizationState(for: .camera)

        XCTAssertEqual(state, .authorized)
    }

    func testWhenNonSystemPermissionTypeThenAuthorizationIsNotRequired() {
        XCTAssertFalse(sut.isAuthorizationRequired(for: .camera))
        XCTAssertFalse(sut.isAuthorizationRequired(for: .microphone))
        XCTAssertFalse(sut.isAuthorizationRequired(for: .popups))
    }
}
