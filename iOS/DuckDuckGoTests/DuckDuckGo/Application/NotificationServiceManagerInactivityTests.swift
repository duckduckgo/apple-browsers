//
//  NotificationServiceManagerInactivityTests.swift
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

import XCTest
import UserNotifications
@_spi(Testing) import PixelKit
@testable import DuckDuckGo
@testable import Core

final class NotificationServiceManagerInactivityTests: XCTestCase {

    private var stateStore: MockInactivityNotificationStateStore!
    private var pixelKitMock: PixelKitMock!
    private let daysInactiveKey = InactivityNotificationSchedulerService.Settings.daysInactive.rawValue
    private let tappedPixelName = Pixel.Event.inactiveUserProvisionalPushNotificationTapped.name

    override func setUp() {
        super.setUp()
        stateStore = MockInactivityNotificationStateStore()
        pixelKitMock = PixelKitMock()
    }

    override func tearDown() {
        stateStore = nil
        pixelKitMock = nil
        super.tearDown()
    }

    // MARK: - Category registration

    func test_notificationCategories_includesInactivityCategoryWithCustomDismissAction() throws {
        let category = try XCTUnwrap(NotificationServiceManager.notificationCategories.first {
            $0.identifier == InactivityNotificationSchedulerService.Constants.notificationIdentifier
        })
        XCTAssertTrue(category.options.contains(.customDismissAction),
                      "The inactivity category must register .customDismissAction, otherwise the dismiss callback is never delivered")
    }

    func test_registerNotificationCategories_registersInactivityCategoryOnCenter() throws {
        let center = MockUNUserNotificationCenter()

        NotificationServiceManager.registerNotificationCategories(on: center)

        XCTAssertTrue(center.registeredCategories.contains {
            $0.identifier == InactivityNotificationSchedulerService.Constants.notificationIdentifier
        })
    }

    // MARK: - Tap (default action)

    func test_defaultAction_recordsInteractionOnceAndFiresTapPixel() {
        NotificationServiceManager.handleInactivityNotification(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: [daysInactiveKey: 5],
            stateStore: stateStore,
            pixelFiring: pixelKitMock
        )

        XCTAssertEqual(stateStore.recordInteractionCallCount, 1)
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.pixel.name == tappedPixelName }, "Tap pixel should have fired")
    }

    func test_defaultAction_missingDaysInactiveInUserInfo_stillRecordsAndFiresUsingDefaultDays() {
        NotificationServiceManager.handleInactivityNotification(
            actionIdentifier: UNNotificationDefaultActionIdentifier,
            userInfo: [:],
            stateStore: stateStore,
            pixelFiring: pixelKitMock
        )

        XCTAssertEqual(stateStore.recordInteractionCallCount, 1)
        XCTAssertTrue(pixelKitMock.actualFireCalls.contains { $0.pixel.name == tappedPixelName })
    }

    // MARK: - Dismiss

    func test_dismissAction_recordsInteractionOnceAndFiresNoPixel() {
        NotificationServiceManager.handleInactivityNotification(
            actionIdentifier: UNNotificationDismissActionIdentifier,
            userInfo: [daysInactiveKey: 5],
            stateStore: stateStore,
            pixelFiring: pixelKitMock
        )

        XCTAssertEqual(stateStore.recordInteractionCallCount, 1)
        XCTAssertTrue(pixelKitMock.actualFireCalls.isEmpty, "Tap pixel should not have fired")
    }

    func test_dismissAction_missingDaysInactiveInUserInfo_stillRecordsInteraction() {
        NotificationServiceManager.handleInactivityNotification(
            actionIdentifier: UNNotificationDismissActionIdentifier,
            userInfo: [:],
            stateStore: stateStore
        )

        XCTAssertEqual(stateStore.recordInteractionCallCount, 1)
    }

    // MARK: - Other action identifiers unaffected

    func test_otherActionIdentifier_doesNotRecordInteractionOrFireAnyPixel() {
        NotificationServiceManager.handleInactivityNotification(
            actionIdentifier: "com.duckduckgo.some.other.action",
            userInfo: [daysInactiveKey: 5],
            stateStore: stateStore,
            pixelFiring: pixelKitMock
        )

        XCTAssertEqual(stateStore.recordInteractionCallCount, 0)
        XCTAssertTrue(pixelKitMock.actualFireCalls.isEmpty)
    }
}

// MARK: - Mocks

final class MockInactivityNotificationStateStore: InactivityNotificationStateStoring {
    private(set) var recordInteractionCallCount = 0
    private(set) var resetCallCount = 0
    var interactionCount: Int = 0

    func recordInteraction() {
        recordInteractionCallCount += 1
        interactionCount += 1
    }

    func reset() {
        resetCallCount += 1
        interactionCount = 0
    }
}
