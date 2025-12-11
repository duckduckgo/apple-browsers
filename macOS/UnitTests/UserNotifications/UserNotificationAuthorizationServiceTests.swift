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
@testable import DuckDuckGo

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

        let expectation = XCTestExpectation(description: "Status updated after app activation")
        expectation.expectedFulfillmentCount = 2

        service.authorizationStatusPublisher
            .dropFirst()
            .sink { _ in
                expectation.fulfill()
            }
            .store(in: &cancellables)

        try await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)

        appActivationSubject.send(Notification(name: NSApplication.didBecomeActiveNotification))

        try await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)

        await fulfillment(of: [expectation], timeout: 2.0)
    }

    func testWhenAuthorizationStatusQueriedThenReturnsCurrentStatus() async throws {
        service = UserNotificationAuthorizationService(appActivationPublisher: appActivationSubject.eraseToAnyPublisher())

        let status = await service.authorizationStatus

        XCTAssertTrue([.notDetermined, .denied, .authorized, .provisional, .ephemeral].contains(status))
    }

    func testWhenMultipleSubscribersExistThenAllReceiveUpdates() async throws {
        service = UserNotificationAuthorizationService(appActivationPublisher: appActivationSubject.eraseToAnyPublisher())

        let expectation1 = XCTestExpectation(description: "First subscriber receives update")
        let expectation2 = XCTestExpectation(description: "Second subscriber receives update")

        service.authorizationStatusPublisher
            .dropFirst()
            .first()
            .sink { _ in
                expectation1.fulfill()
            }
            .store(in: &cancellables)

        service.authorizationStatusPublisher
            .dropFirst()
            .first()
            .sink { _ in
                expectation2.fulfill()
            }
            .store(in: &cancellables)

        try await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)

        appActivationSubject.send(Notification(name: NSApplication.didBecomeActiveNotification))

        await fulfillment(of: [expectation1, expectation2], timeout: 2.0)
    }

    func testWhenMultipleAppActivationsOccurThenEachTriggersStatusCheck() async throws {
        service = UserNotificationAuthorizationService(appActivationPublisher: appActivationSubject.eraseToAnyPublisher())

        var updateCount = 0
        let expectation = XCTestExpectation(description: "Receives multiple status updates")
        expectation.expectedFulfillmentCount = 3

        service.authorizationStatusPublisher
            .dropFirst()
            .sink { _ in
                updateCount += 1
                expectation.fulfill()
            }
            .store(in: &cancellables)

        try await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)

        appActivationSubject.send(Notification(name: NSApplication.didBecomeActiveNotification))
        try await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)

        appActivationSubject.send(Notification(name: NSApplication.didBecomeActiveNotification))
        try await Task.sleep(nanoseconds: 100 * NSEC_PER_MSEC)

        await fulfillment(of: [expectation], timeout: 3.0)
        XCTAssertGreaterThanOrEqual(updateCount, 2)
    }
}

final class UserNotificationAuthorizationServiceMock: UserNotificationAuthorizationServicing {
    @PublishedAfter var currentAuthorizationStatus: UNAuthorizationStatus = .notDetermined

    var authorizationStatus: UNAuthorizationStatus {
        get async {
            return currentAuthorizationStatus
        }
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

