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
    var mockUserNotificationCenter: MockUNUserNotificationCenter!
    var service: InactivityNotificationSchedulerService!
    
    override func setUp() {
        super.setUp()
        mockPrivacyConfigManager = PrivacyConfigurationManagerMock()
        mockFeatureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.inactivityNotification])
        mockNotificationServiceManager = MockNotificationServiceManager()
        mockUserNotificationCenter = MockUNUserNotificationCenter()
        
        service = InactivityNotificationSchedulerService(
            featureFlagger: mockFeatureFlagger,
            notificationServiceManager: mockNotificationServiceManager,
            privacyConfigurationManager: mockPrivacyConfigManager,
            userNotificationCenter: mockUserNotificationCenter
        )
    }

    override func tearDown() {
        mockPrivacyConfigManager = nil
        mockFeatureFlagger = nil
        mockNotificationServiceManager = nil
        mockUserNotificationCenter = nil
        service = nil
        super.tearDown()
    }
    
    // MARK: - Resume
    
    func test_resume_featureIsOff_cancelsAndDoesNotReschedule() async {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = []
        
        // When
        await service.resume().value
        
        // Then
        XCTAssertTrue(mockUserNotificationCenter.removedIdentifiers.contains { $0.contains(InactivityNotificationSchedulerService.Constants.notificationIdentifier) })
        XCTAssertTrue(mockUserNotificationCenter.addedRequests.isEmpty)
    }
    
    func test_resume_featureIsEnabled_cancelsAndReschedule() async throws {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.inactivityNotification]
        
        // When
        await service.resume().value
        
        // Then
        XCTAssertTrue(mockUserNotificationCenter.removedIdentifiers.contains { $0.contains(InactivityNotificationSchedulerService.Constants.notificationIdentifier) })
        XCTAssertEqual(mockUserNotificationCenter.addedRequests.count, 1)
        XCTAssertEqual(mockUserNotificationCenter.addedRequests.first?.identifier, InactivityNotificationSchedulerService.Constants.notificationIdentifier)
        
        let notificationRequest = try XCTUnwrap(mockUserNotificationCenter.addedRequests.first)
        XCTAssertEqual(notificationRequest.content.title, UserText.inactivityNotificationTitle)
        XCTAssertEqual(notificationRequest.content.body, UserText.inactivityNotificationBody)
        XCTAssertEqual(notificationRequest.trigger, UNTimeIntervalNotificationTrigger(timeInterval: .days(7), repeats: false))
        
        guard let daysInactive = notificationRequest.content.userInfo[ InactivityNotificationSchedulerService.Constants.daysInactiveSettingKey] as? Int else {
            return XCTFail("Expected Int for daysInactive in userInfo")
        }
        XCTAssertEqual(daysInactive, 7)
    }
    
    func test_resume_calledManyTimes_cancelsAndReschedule() async {
        // Given
        mockFeatureFlagger.enabledFeatureFlags = [.inactivityNotification]
        mockUserNotificationCenter.authorizationStatus = .provisional

        // When
        for _ in 0..<25 {
            await service.resume().value
        }

        // Then
        XCTAssertTrue(mockUserNotificationCenter.removedIdentifiers.contains { $0.contains(InactivityNotificationSchedulerService.Constants.notificationIdentifier) })
        XCTAssertEqual(mockUserNotificationCenter.addedRequests.count, 1)
        XCTAssertEqual(mockUserNotificationCenter.addedRequests.first?.identifier, InactivityNotificationSchedulerService.Constants.notificationIdentifier)
    }
    
    func test_resume_featureTogglesManyTimes_cancelsAndReschedule() async {
        // Given
        mockUserNotificationCenter.authorizationStatus = .provisional

        // When
        for _ in 0..<25 {
            if Bool.random() {
                mockFeatureFlagger.enabledFeatureFlags = [.inactivityNotification]
            } else {
                mockFeatureFlagger.enabledFeatureFlags = []
            }

            await service.resume().value
        }

        // Then
        if mockFeatureFlagger.enabledFeatureFlags.contains(.inactivityNotification) {
            XCTAssertTrue(mockUserNotificationCenter.removedIdentifiers.contains { $0.contains(InactivityNotificationSchedulerService.Constants.notificationIdentifier) })
            XCTAssertEqual(mockUserNotificationCenter.addedRequests.count, 1)
            XCTAssertEqual(mockUserNotificationCenter.addedRequests.first?.identifier, InactivityNotificationSchedulerService.Constants.notificationIdentifier)
        } else {
            XCTAssertTrue(mockUserNotificationCenter.removedIdentifiers.contains { $0.contains(InactivityNotificationSchedulerService.Constants.notificationIdentifier) })
            XCTAssertEqual(mockUserNotificationCenter.addedRequests.count, 0)
        }
    }
    
    // MARK: - Schedule
    
    func test_schedule_statusNotProvisional_doNotSchedule() async {
        // Given
        mockUserNotificationCenter.authorizationStatus = .authorized
        
        // When
        await service.schedule()
        
        
        // Then
        XCTAssertTrue(mockUserNotificationCenter.removedIdentifiers.contains { $0.contains(InactivityNotificationSchedulerService.Constants.notificationIdentifier) })
        XCTAssertTrue(mockUserNotificationCenter.didCheckAuthorizationStatus)
        XCTAssertFalse(mockUserNotificationCenter.didRequestAuthorization)
    }
    
    func test_schedule_statusIsNotDetermined_requestAndSchedule() async {
        // Given
        mockUserNotificationCenter.authorizationStatus = .notDetermined
        
        // When
        await service.schedule()
        
        // Then
        XCTAssertTrue(mockUserNotificationCenter.removedIdentifiers.contains { $0.contains(InactivityNotificationSchedulerService.Constants.notificationIdentifier) })
        XCTAssertTrue(mockUserNotificationCenter.didCheckAuthorizationStatus)
        XCTAssertTrue(mockUserNotificationCenter.didRequestAuthorization)
        XCTAssertEqual(mockUserNotificationCenter.addedRequests.count, 1)
        XCTAssertEqual(mockUserNotificationCenter.addedRequests.first?.identifier, InactivityNotificationSchedulerService.Constants.notificationIdentifier)
    }

    func test_schedule_statusIsProvisional_schedule() async {
        // Given
        mockUserNotificationCenter.authorizationStatus = .provisional
        
        // When
        await service.schedule()
        
        // Then
        XCTAssertTrue(mockUserNotificationCenter.removedIdentifiers.contains { $0.contains(InactivityNotificationSchedulerService.Constants.notificationIdentifier) })
        XCTAssertTrue(mockUserNotificationCenter.didCheckAuthorizationStatus)
        XCTAssertFalse(mockUserNotificationCenter.didRequestAuthorization)
        XCTAssertEqual(mockUserNotificationCenter.addedRequests.count, 1)
        XCTAssertEqual(mockUserNotificationCenter.addedRequests.first?.identifier, InactivityNotificationSchedulerService.Constants.notificationIdentifier)
    }
    
    func test_schedule_whenAddThrows_logsAndContinues() async {
        // Given
        mockUserNotificationCenter.authorizationStatus = .provisional
        mockUserNotificationCenter.addRequestError = .addRequestError
        
        // When
        await service.schedule()
        
        // Then
        XCTAssertTrue(mockUserNotificationCenter.removedIdentifiers.contains { $0.contains(InactivityNotificationSchedulerService.Constants.notificationIdentifier) })
        XCTAssertTrue(mockUserNotificationCenter.didCheckAuthorizationStatus)
        XCTAssertFalse(mockUserNotificationCenter.didRequestAuthorization)
        XCTAssertEqual(mockUserNotificationCenter.addedRequests.count, 0)
    }
    
    // MARK: - RequestAuthorizationIfNeeded
    
    func test_requestAuthIfNeeded_statusIsNotNotDetermined_doNotRequest() async {
        // Given
        mockUserNotificationCenter.authorizationStatus = .denied
        
        // When
        await service.requestProvisionalAuthorizationIfNeeded()
        
        // Then
        XCTAssertTrue(mockUserNotificationCenter.didCheckAuthorizationStatus)
        XCTAssertFalse(mockUserNotificationCenter.didRequestAuthorization)
    }
    
    func test_requestAuthIfNeeded_statusIsNotDetermined_requestForProvisional() async {
        // Given
        mockUserNotificationCenter.authorizationStatus = .notDetermined
        
        // When
        await service.requestProvisionalAuthorizationIfNeeded()
        
        // Then
        XCTAssertTrue(mockUserNotificationCenter.didCheckAuthorizationStatus)
        XCTAssertTrue(mockUserNotificationCenter.didRequestAuthorization)
        XCTAssertTrue(mockUserNotificationCenter.requestedAuthorizationOptions.contains(.provisional))
    }
    
    func test_requestAuthIfNeeded_whenRequestThrows_doesNotCrash() async {
        // Given
        mockUserNotificationCenter.authorizationStatus = .notDetermined
        mockUserNotificationCenter.requestAuthError = .requestAuthError

        // When
        await service.requestProvisionalAuthorizationIfNeeded()

        // Then
        XCTAssertTrue(mockUserNotificationCenter.didCheckAuthorizationStatus)
        XCTAssertTrue(mockUserNotificationCenter.didRequestAuthorization)
        XCTAssertTrue(mockUserNotificationCenter.requestedAuthorizationOptions.contains(.provisional))
    }
    
    // MARK: - MakeDaysInactive
    
    func test_makeDaysInactive_readsConfiguredValue() {
        // Given
        (mockPrivacyConfigManager.privacyConfig as? PrivacyConfigurationMock)?.subfeatureSettings = [
            "inactivityNotification": """
                {"daysInactive": "5"}
            """
        ]
        
        // When
        let result = service.makeDaysInactive()
        
        // Then
        XCTAssertEqual(result, 5)
    }
        
    func test_makeDaysInactive_invalidValue_usesDefault() {
        // Given
        (mockPrivacyConfigManager.privacyConfig as? PrivacyConfigurationMock)?.subfeatureSettings = [
            "inactivityNotification": """
                {"daysInactive": "x"}
            """
        ]
        
        // When
        let result = service.makeDaysInactive()
        
        // Then
        XCTAssertEqual(result, 7)
    }
    
    func test_makeDaysInactive_lessThanOne_usesDefault() {
        // Given
        (mockPrivacyConfigManager.privacyConfig as? PrivacyConfigurationMock)?.subfeatureSettings = [
            "inactivityNotification": """
                {"daysInactive": "0"}
            """
        ]
        
        // When
        let result = service.makeDaysInactive()
        
        // Then
        XCTAssertEqual(result, 7)
    }
    
    func test_makeDaysInactive_emptyValue_usesDefault() {
        // Given
        (mockPrivacyConfigManager.privacyConfig as? PrivacyConfigurationMock)?.subfeatureSettings = [:]
        
        // When
        let result = service.makeDaysInactive()
        
        // Then
        XCTAssertEqual(result, 7)
    }
    
    // MARK: - makeNotficationContent
        
    func test_makeNotificationContent_setsTitleBodyAndUserInfo() {
        // When
        let content = service.makeUNNotificationContent(with: 5)
        
        // Then
        XCTAssertEqual(content.title, UserText.inactivityNotificationTitle)
        XCTAssertEqual(content.body, UserText.inactivityNotificationBody)
        
        if let daysInactive = content.userInfo[InactivityNotificationSchedulerService.Constants.daysInactiveSettingKey] as? Int {
            XCTAssertEqual(daysInactive, 5)
        } else {
            XCTFail("Expected daysInactive in userInfo")
        }
    }
    
    func test_makeNotificationContent_setsTitleBodyAndUserInfo_useDefaultValue() {
        // When
        let content = service.makeUNNotificationContent()
        
        // Then
        if let daysInactive = content.userInfo[InactivityNotificationSchedulerService.Constants.daysInactiveSettingKey] as? Int {
            XCTAssertEqual(daysInactive, InactivityNotificationSchedulerService.Constants.defaultDaysInactive)
        } else {
            XCTFail("Expected daysInactive in userInfo")
        }
    }
}
