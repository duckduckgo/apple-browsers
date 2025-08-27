//
//  InactivityNotificationSchedulerServiceTests.swift
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
    var service: InactivityNotificationSchedulerService!
    
    override func setUp() {
        super.setUp()
        mockPrivacyConfigManager = PrivacyConfigurationManagerMock()
        mockFeatureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.inactivityNotification])
        mockNotificationServiceManager = MockNotificationServiceManager()
        service = InactivityNotificationSchedulerService(
            featureFlagger: mockFeatureFlagger,
            privacyConfigurationManager: mockPrivacyConfigManager,
            notificationServiceManager: mockNotificationServiceManager
        )
    }

    override func tearDown() {
        mockPrivacyConfigManager = nil
        mockFeatureFlagger = nil
        mockNotificationServiceManager = nil
        super.tearDown()
    }
    
    func test_configuredDaysInactive_readsConfiguredValue() {
        // Given
        (mockPrivacyConfigManager.privacyConfig as? PrivacyConfigurationMock)?.subfeatureSettings = [
            "inactivityNotification": """
                {"daysInactive": "5"}
            """
        ]
        
        // When
        let result = service.makeDaysInactive()
        
        // Then
        XCTAssertEqual(result, 5.0)
    }
        
    func test_configuredDaysInactive_invalidValue_usesDefault() {
        // Given
        (mockPrivacyConfigManager.privacyConfig as? PrivacyConfigurationMock)?.subfeatureSettings = [
            "inactivityNotification": """
                {"daysInactive": "x"}
            """
        ]
        
        // When
        let result = service.makeDaysInactive()
        
        // Then
        XCTAssertEqual(result, 7.0)
    }
    
    func test_configuredDaysInactive_emptyValue_usesDefault() {
        // Given
        (mockPrivacyConfigManager.privacyConfig as? PrivacyConfigurationMock)?.subfeatureSettings = [:]
        
        // When
        let result = service.makeDaysInactive()
        
        // Then
        XCTAssertEqual(result, 7.0)
    }
        
    func test_makeNotificationContent_setsTitleBodyAndUserInfo() {
        // When
        let content = service.makeUNNotificationContent(with: 5.0)
        
        // Then
        XCTAssertEqual(content.title, UserText.inactivityNotificationTitle)
        XCTAssertEqual(content.body, UserText.inactivityNotificationBody)
        
        if let daysInactive = content.userInfo[InactivityNotificationSchedulerService.daysInactiveSettingKey] as? Double {
            XCTAssertEqual(daysInactive, 5.0)
        } else {
            XCTFail("Expected daysInactive in userInfo")
        }
    }
    
    func test_makeNotificationContent_setsTitleBodyAndUserInfo_useDefaultValue() {
        // When
        let content = service.makeUNNotificationContent()
        
        // Then
        if let daysInactive = content.userInfo[InactivityNotificationSchedulerService.daysInactiveSettingKey] as? Double {
            XCTAssertEqual(daysInactive, InactivityNotificationSchedulerService.defaultDaysInactive)
        } else {
            XCTFail("Expected daysInactive in userInfo")
        }
    }
}
