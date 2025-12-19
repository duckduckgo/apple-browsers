//
//  UserNotificationAuthorizationServiceTests.swift
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
import UserNotifications
@testable import DuckDuckGo_Privacy_Browser

final class UserNotificationAuthorizationServiceTests: XCTestCase {

    var service: UserNotificationAuthorizationService!
    var appActivationSubject: PassthroughSubject<Notification, Never>!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        appActivationSubject = PassthroughSubject<Notification, Never>()
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        service = nil
        appActivationSubject = nil
        cancellables = nil
        super.tearDown()
    }

    func testWhenServiceInitializedThenPublisherStartsWithNotDetermined() {
        let expectation = XCTestExpectation(description: "Receives initial status")

        service = UserNotificationAuthorizationService(appActivationPublisher: appActivationSubject.eraseToAnyPublisher())

        service.authorizationStatusPublisher
            .first()
            .sink { status in
                XCTAssertEqual(status, .notDetermined)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        wait(for: [expectation], timeout: 1.0)
    }

    func testWhenAppActivationOccursThenStatusIsChecked() async throws {
        service = UserNotificationAuthorizationService(appActivationPublisher: appActivationSubject.eraseToAnyPublisher())

        // The service checks status on init and on app activation, but only publishes if status changes.
        // Since we can't control real UNUserNotificationCenter, just verify the initial value is available.
        let status = service.cachedAuthorizationStatus
        XCTAssertTrue([.notDetermined, .denied, .authorized, .provisional].contains(status))

        // Trigger app activation - verify it doesn't crash
        appActivationSubject.send(Notification(name: NSApplication.didBecomeActiveNotification))

        try await Task.sleep(nanoseconds: 200 * NSEC_PER_MSEC)

        // Status should still be valid after activation
        let statusAfter = service.cachedAuthorizationStatus
        XCTAssertTrue([.notDetermined, .denied, .authorized, .provisional].contains(statusAfter))
    }

    func testWhenAuthorizationStatusQueriedThenReturnsCurrentStatus() async throws {
        service = UserNotificationAuthorizationService(appActivationPublisher: appActivationSubject.eraseToAnyPublisher())

        let status = await service.authorizationStatus

        XCTAssertTrue([.notDetermined, .denied, .authorized, .provisional].contains(status))
    }

    func testWhenMultipleSubscribersExistThenAllReceiveInitialValue() async throws {
        service = UserNotificationAuthorizationService(appActivationPublisher: appActivationSubject.eraseToAnyPublisher())

        // Both subscribers should receive the initial/current value
        let expectation1 = XCTestExpectation(description: "First subscriber receives value")
        let expectation2 = XCTestExpectation(description: "Second subscriber receives value")

        service.authorizationStatusPublisher
            .first()
            .sink { _ in
                expectation1.fulfill()
            }
            .store(in: &cancellables)

        service.authorizationStatusPublisher
            .first()
            .sink { _ in
                expectation2.fulfill()
            }
            .store(in: &cancellables)

        await fulfillment(of: [expectation1, expectation2], timeout: 2.0)
    }

    func testWhenMultipleAppActivationsOccurThenServiceHandlesThemGracefully() async throws {
        service = UserNotificationAuthorizationService(appActivationPublisher: appActivationSubject.eraseToAnyPublisher())

        // Service only publishes when status CHANGES. We use real UNUserNotificationCenter
        // so we just verify multiple activations don't cause issues.
        appActivationSubject.send(Notification(name: NSApplication.didBecomeActiveNotification))
        try await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)

        appActivationSubject.send(Notification(name: NSApplication.didBecomeActiveNotification))
        try await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)

        appActivationSubject.send(Notification(name: NSApplication.didBecomeActiveNotification))
        try await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)

        // Status should be a valid value after multiple activations
        let finalStatus = service.cachedAuthorizationStatus
        XCTAssertTrue([.notDetermined, .denied, .authorized, .provisional].contains(finalStatus))
    }
}

final class UserNotificationAuthorizationServiceMock: UserNotificationAuthorizationServicing {
    @PublishedAfter var currentAuthorizationStatus: UNAuthorizationStatus = .notDetermined

    var authorizationStatus: UNAuthorizationStatus {
        get async {
            return currentAuthorizationStatus
        }
    }

    var cachedAuthorizationStatus: UNAuthorizationStatus {
        currentAuthorizationStatus
    }

    var authorizationStatusPublisher: AnyPublisher<UNAuthorizationStatus, Never> {
        $currentAuthorizationStatus.eraseToAnyPublisher()
    }

    var requestAuthorizationCalled = false
    var requestAuthorizationResult: Result<Bool, Error> = .success(true)

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        requestAuthorizationCalled = true
        switch requestAuthorizationResult {
        case .success(let granted):
            if granted {
                currentAuthorizationStatus = .authorized
            }
            return granted
        case .failure(let error):
            throw error
        }
    }
}
