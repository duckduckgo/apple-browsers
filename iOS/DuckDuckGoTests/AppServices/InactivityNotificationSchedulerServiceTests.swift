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
import FoundationExtensions
import PersistenceTestingUtils
@testable import DuckDuckGo
@testable import Core
@testable import BrowserServicesKit

final class MockNotificationServiceManager: NSObject, NotificationServiceManaging {}

final class InactivityNotificationSchedulerServiceTests: XCTestCase {

    var mockFeatureFlagger: MockFeatureFlagger!
    var mockPrivacyConfigManager: PrivacyConfigurationManagerMock!
    var mockNotificationServiceManager: MockNotificationServiceManager!
    var mockUserNotificationCenter: MockUNUserNotificationCenter!
    var stateStore: InactivityNotificationStateStoring!
    var service: InactivityNotificationSchedulerService!

    override func setUp() {
        super.setUp()
        mockPrivacyConfigManager = PrivacyConfigurationManagerMock()
        mockFeatureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.inactivityNotification])
        mockNotificationServiceManager = MockNotificationServiceManager()
        mockUserNotificationCenter = MockUNUserNotificationCenter()
        stateStore = InactivityNotificationStateStore(keyValueStore: MockKeyValueFileStore())

        service = InactivityNotificationSchedulerService(
            featureFlagger: mockFeatureFlagger,
            notificationServiceManager: mockNotificationServiceManager,
            privacyConfigurationManager: mockPrivacyConfigManager,
            stateStore: stateStore,
            userNotificationCenter: mockUserNotificationCenter
        )
    }

    override func tearDown() {
        mockPrivacyConfigManager = nil
        mockFeatureFlagger = nil
        mockNotificationServiceManager = nil
        mockUserNotificationCenter = nil
        stateStore = nil
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
        
        guard let daysInactive = notificationRequest.content.userInfo[ InactivityNotificationSchedulerService.Settings.daysInactive.rawValue] as? Int else {
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
    
    func test_resume_whenInteractionLimitReached_cancelsAndDoesNotSchedule() async throws {
        // Given
        mockUserNotificationCenter.authorizationStatus = .provisional
        for _ in 0..<4 { stateStore.recordInteraction() }

        // When
        await service.resume().value

        // Then
        XCTAssertTrue(mockUserNotificationCenter.removedIdentifiers.contains { $0.contains(InactivityNotificationSchedulerService.Constants.notificationIdentifier) })
        XCTAssertTrue(mockUserNotificationCenter.addedRequests.isEmpty)
    }

    func test_resume_whenRemoteMaxInteractionsDropsBelowCurrentCount_doesNotSchedule() async {
        // Given: remote config now caps interactions at 2, and the user has already interacted twice.
        (mockPrivacyConfigManager.privacyConfig as? PrivacyConfigurationMock)?.subfeatureSettings = [
            "inactivityNotification": """
                {"maxInteractions": 2}
            """
        ]
        mockUserNotificationCenter.authorizationStatus = .provisional
        for _ in 0..<2 { stateStore.recordInteraction() }

        // When
        await service.resume().value

        // Then
        XCTAssertTrue(mockUserNotificationCenter.addedRequests.isEmpty)
    }

    // MARK: - Schedule

    func test_schedule_statusAuthorized_schedules() async {
        // Given
        mockUserNotificationCenter.authorizationStatus = .authorized

        // When
        await service.schedule()

        // Then
        XCTAssertEqual(mockUserNotificationCenter.addedRequests.count, 1)
        XCTAssertFalse(mockUserNotificationCenter.didRequestAuthorization)
    }

    func test_schedule_statusDenied_doesNotSchedule() async {
        // Given
        mockUserNotificationCenter.authorizationStatus = .denied

        // When
        await service.schedule()

        // Then
        XCTAssertTrue(mockUserNotificationCenter.addedRequests.isEmpty)
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

    func test_schedule_whenInteractionLimitReachedBetweenResumeCheckAndSchedule_doesNotSchedule() async {
        // Given: simulates the race where `resume()`'s outer gate passed, but interactions were
        // recorded (e.g. from a concurrent notification response) before `schedule()`'s own
        // add() call runs. `schedule()` must re-check the cap itself as defense-in-depth.
        mockUserNotificationCenter.authorizationStatus = .provisional
        for _ in 0..<InactivityNotificationSchedulerService.Settings.maxInteractions.defaultValue {
            stateStore.recordInteraction()
        }

        // When
        await service.schedule()

        // Then
        XCTAssertTrue(mockUserNotificationCenter.addedRequests.isEmpty)
    }

    func test_scheduledContent_hasInactivityIdentifier() async throws {
        // Given
        mockUserNotificationCenter.authorizationStatus = .provisional

        // When
        await service.schedule()

        // Then
        let request = try XCTUnwrap(mockUserNotificationCenter.addedRequests.first)
        XCTAssertEqual(
            request.content.categoryIdentifier,
            InactivityNotificationSchedulerService.Constants.notificationIdentifier
        )
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
    
    // MARK: - daysInactive

    func test_daysInactive_readsConfiguredValue() {
        // Given
        (mockPrivacyConfigManager.privacyConfig as? PrivacyConfigurationMock)?.subfeatureSettings = [
            "inactivityNotification": """
                {"daysInactive": 5}
            """
        ]
        
        // When
        let result = service.daysInactive

        // Then
        XCTAssertEqual(result, 5)
    }
        
    func test_daysInactive_invalidValue_usesDefault() {
        // Given
        (mockPrivacyConfigManager.privacyConfig as? PrivacyConfigurationMock)?.subfeatureSettings = [
            "inactivityNotification": """
                {"daysInactive": "x"}
            """
        ]
        
        // When
        let result = service.daysInactive

        // Then
        XCTAssertEqual(result, 7)
    }
    
    func test_daysInactive_lessThanOne_usesDefault() {
        // Given
        (mockPrivacyConfigManager.privacyConfig as? PrivacyConfigurationMock)?.subfeatureSettings = [
            "inactivityNotification": """
                {"daysInactive": 0}
            """
        ]
        
        // When
        let result = service.daysInactive

        // Then
        XCTAssertEqual(result, 7)
    }
    
    func test_daysInactive_emptyValue_usesDefault() {
        // Given
        (mockPrivacyConfigManager.privacyConfig as? PrivacyConfigurationMock)?.subfeatureSettings = [:]
        
        // When
        let result = service.daysInactive

        // Then
        XCTAssertEqual(result, 7)
    }

    // MARK: - maxInteractions

    func test_maxInteractions_readsConfiguredValue() {
        // Given
        (mockPrivacyConfigManager.privacyConfig as? PrivacyConfigurationMock)?.subfeatureSettings = [
            "inactivityNotification": """
                {"maxInteractions": 3}
            """
        ]

        // When
        let result = service.maxInteractions

        // Then
        XCTAssertEqual(result, 3)
    }

    func test_maxInteractions_invalidValue_usesDefault() {
        // Given
        (mockPrivacyConfigManager.privacyConfig as? PrivacyConfigurationMock)?.subfeatureSettings = [
            "inactivityNotification": """
                {"maxInteractions": "x"}
            """
        ]

        // When
        let result = service.maxInteractions

        // Then
        XCTAssertEqual(result, InactivityNotificationSchedulerService.Settings.maxInteractions.defaultValue)
    }

    func test_maxInteractions_lessThanOne_usesDefault() {
        // Given
        (mockPrivacyConfigManager.privacyConfig as? PrivacyConfigurationMock)?.subfeatureSettings = [
            "inactivityNotification": """
                {"maxInteractions": 0}
            """
        ]

        // When
        let result = service.maxInteractions

        // Then
        XCTAssertEqual(result, InactivityNotificationSchedulerService.Settings.maxInteractions.defaultValue)
    }

    func test_maxInteractions_emptyValue_usesDefault() {
        // Given
        (mockPrivacyConfigManager.privacyConfig as? PrivacyConfigurationMock)?.subfeatureSettings = [:]

        // When
        let result = service.maxInteractions

        // Then
        XCTAssertEqual(result, InactivityNotificationSchedulerService.Settings.maxInteractions.defaultValue)
    }

    // MARK: - makeNotficationContent
        
    func test_makeNotificationContent_setsTitleBodyAndUserInfo() {
        // When
        let content = service.makeUNNotificationContent(with: 5)
        
        // Then
        XCTAssertEqual(content.title, UserText.inactivityNotificationTitle)
        XCTAssertEqual(content.body, UserText.inactivityNotificationBody)
        
        if let daysInactive = content.userInfo[InactivityNotificationSchedulerService.Settings.daysInactive.rawValue] as? Int {
            XCTAssertEqual(daysInactive, 5)
        } else {
            XCTFail("Expected daysInactive in userInfo")
        }
    }
    
    func test_makeNotificationContent_setsTitleBodyAndUserInfo_useDefaultValue() {
        // When
        let content = service.makeUNNotificationContent()
        
        // Then
        if let daysInactive = content.userInfo[InactivityNotificationSchedulerService.Settings.daysInactive.rawValue] as? Int {
            XCTAssertEqual(daysInactive, InactivityNotificationSchedulerService.Settings.daysInactive.defaultValue)
        } else {
            XCTFail("Expected daysInactive in userInfo")
        }
    }
}
