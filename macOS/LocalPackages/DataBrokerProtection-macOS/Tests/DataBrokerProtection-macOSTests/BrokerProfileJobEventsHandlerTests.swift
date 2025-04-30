//
//  BrokerProfileJobEventsHandlerTests.swift
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

import XCTest
import Configuration
import Persistence
@testable import DataBrokerProtection_macOS
import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils

final class BrokerProfileJobEventsHandlerTests: XCTestCase {

    private var sut: BrokerProfileJobEventsHandler!

    private var mockNotificationService: MockUserNotificationService!

    override func setUpWithError() throws {
        mockNotificationService = MockUserNotificationService()
    }

    func testWhenProfileSaved_thenRequestPermissionWasAsked() async throws {
        // Given
        sut = BrokerProfileJobEventsHandler(userNotificationService: mockNotificationService)

        mockNotificationService.reset()

        // When
        sut.fire(.profileSaved)

        // Then
        XCTAssertTrue(mockNotificationService.requestPermissionWasAsked)
    }

    func testWhenFirstScanCompleted_thenFirstScanNotificationWasSent() async throws {
        // Given
        sut = BrokerProfileJobEventsHandler(userNotificationService: mockNotificationService)

        mockNotificationService.reset()

        // When
        sut.fire(.firstScanCompleted)

        // Then
        XCTAssertTrue(mockNotificationService.firstScanNotificationWasSent)
    }

    func testWhenFirstScanCompletedAndMatchesFound_thenCheckInNotificationWasScheduled() async throws {
        // Given
        sut = BrokerProfileJobEventsHandler(userNotificationService: mockNotificationService)

        mockNotificationService.reset()

        // When
        sut.fire(.firstScanCompletedAndMatchesFound)

        // Then
        XCTAssertTrue(mockNotificationService.checkInNotificationWasScheduled)
    }

    func testWhenFirstProfileRemoved_thenFirstScanNotificationWasSent() async throws {
        // Given
        sut = BrokerProfileJobEventsHandler(userNotificationService: mockNotificationService)

        mockNotificationService.reset()

        // When
        sut.fire(.firstProfileRemoved)

        // Then
        XCTAssertTrue(mockNotificationService.firstRemovedNotificationWasSent)
    }

    func testWhenAllProfilesRemoved_thenAllInfoRemovedWasSent() async throws {
        // Given
        sut = BrokerProfileJobEventsHandler(userNotificationService: mockNotificationService)

        mockNotificationService.reset()

        // When
        sut.fire(.allProfilesRemoved)

        // Then
        XCTAssertTrue(mockNotificationService.allInfoRemovedWasSent)
    }

}
