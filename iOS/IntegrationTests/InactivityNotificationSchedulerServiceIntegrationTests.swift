//
//  InactivityNotificationSchedulerServiceIntegrationTests.swift
//  DuckDuckGo
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
@testable import DuckDuckGo
@testable import Core
@testable import BrowserServicesKit

final class MockNotificationServiceManager: NSObject, NotificationServiceManaging {}

final class InactivityNotificationSchedulerServiceTests: XCTestCase {
    
    var mockFeatureFlagger: MockFeatureFlagger!
    var mockPrivacyConfigManager: PrivacyConfigurationManagerMock!
    var mockNotificationServiceManager: MockNotificationServiceManager!
    var userNotificationCenter: UNUserNotificationCenterRepresentable!
    var service: InactivityNotificationSchedulerService!
    
    override func setUp() {
        super.setUp()
        mockPrivacyConfigManager = PrivacyConfigurationManagerMock()
        mockFeatureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.inactivityNotification])
        mockNotificationServiceManager = MockNotificationServiceManager()
        userNotificationCenter = UNUserNotificationCenter.current()
        
        service = InactivityNotificationSchedulerService(
            featureFlagger: mockFeatureFlagger,
            notificationServiceManager: mockNotificationServiceManager,
            privacyConfigurationManager: mockPrivacyConfigManager,
            userNotificationCenter: userNotificationCenter
        )
    }
    
    override func tearDown() {
        mockPrivacyConfigManager = nil
        mockFeatureFlagger = nil
        mockNotificationServiceManager = nil
        userNotificationCenter = nil
        service = nil
        super.tearDown()
    }
    
    func test_featureIsEnabled_scheduledOne() async throws {
        // Given
        let targetId = InactivityNotificationSchedulerService.Constants.notificationIdentifier
        mockFeatureFlagger.enabledFeatureFlags = [.inactivityNotification]

        // When
        await service.resume().value

        // Then
        let status = await userNotificationCenter.authorizationStatus()
        guard status == .provisional else {
            let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
            XCTAssertEqual(pending.filter { $0.identifier == targetId }.count, 0)
            return
        }
        
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        XCTAssertEqual(pending.filter { $0.identifier == targetId }.count, 1)
    }
    
    func test_featureIsEnabled_resumeCalledManyTimes_scheduledOne() async throws {
        // Given
        let targetId = InactivityNotificationSchedulerService.Constants.notificationIdentifier
        mockFeatureFlagger.enabledFeatureFlags = [.inactivityNotification]

        // When
        for _ in 0..<25 {
            await service.resume().value
        }

        // Then
        let status = await userNotificationCenter.authorizationStatus()
        guard status == .provisional else {
            let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
            XCTAssertEqual(pending.filter { $0.identifier == targetId }.count, 0)
            return
        }
        
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        XCTAssertEqual(pending.filter { $0.identifier == targetId }.count, 1)
    }
}
