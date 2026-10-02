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
import UserNotifications
@_spi(Testing) import Persistence
@testable import DuckDuckGo
@testable import Core
@testable import BrowserServicesKit

final class MockNotificationServiceManager: NSObject, NotificationServiceManaging {}

final class InactivityNotificationSchedulerServiceTests: XCTestCase {

    var mockFeatureFlagger: MockFeatureFlagger!
    var mockPrivacyConfigManager: PrivacyConfigurationManagerMock!
    var mockNotificationServiceManager: MockNotificationServiceManager!
    var userNotificationCenter: UNUserNotificationCenterRepresentable!
    var stateStore: InactivityNotificationStateStoring!
    var service: InactivityNotificationSchedulerService!
    private var originalNotificationDelegate: UNUserNotificationCenterDelegate?

    override func setUp() {
        super.setUp()
        mockPrivacyConfigManager = PrivacyConfigurationManagerMock()
        mockFeatureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.inactivityNotification])
        mockNotificationServiceManager = MockNotificationServiceManager()
        userNotificationCenter = UNUserNotificationCenter.current()
        originalNotificationDelegate = userNotificationCenter.delegate
        stateStore = InactivityNotificationStateStore(keyValueStore: MockKeyValueFileStore())

        service = InactivityNotificationSchedulerService(
            featureFlagger: mockFeatureFlagger,
            notificationServiceManager: mockNotificationServiceManager,
            privacyConfigurationManager: mockPrivacyConfigManager,
            stateStore: stateStore,
            userNotificationCenter: userNotificationCenter
        )
    }

    override func tearDown() {
        userNotificationCenter.removePendingNotificationRequests(
            withIdentifiers: [InactivityNotificationSchedulerService.Constants.notificationIdentifier]
        )
        userNotificationCenter.delegate = originalNotificationDelegate
        originalNotificationDelegate = nil
        mockPrivacyConfigManager = nil
        mockFeatureFlagger = nil
        mockNotificationServiceManager = nil
        userNotificationCenter = nil
        stateStore = nil
        service = nil
        super.tearDown()
    }
    
    func test_featureIsEnabled_scheduledOne() async throws {
        // Given
        try await requireNotificationScheduling()
        let targetId = InactivityNotificationSchedulerService.Constants.notificationIdentifier
        mockFeatureFlagger.enabledFeatureFlags = [.inactivityNotification]

        // When
        await service.resume().value

        // Then
        let pending = await userNotificationCenter.pendingNotificationRequests()
        XCTAssertEqual(pending.filter { $0.identifier == targetId }.count, 1)
    }
    
    func test_featureIsEnabled_resumeCalledManyTimes_scheduledOne() async throws {
        // Given
        try await requireNotificationScheduling()
        let targetId = InactivityNotificationSchedulerService.Constants.notificationIdentifier
        mockFeatureFlagger.enabledFeatureFlags = [.inactivityNotification]

        // When
        for _ in 0..<25 {
            await service.resume().value
        }

        // Then
        let pending = await userNotificationCenter.pendingNotificationRequests()
        XCTAssertEqual(pending.filter { $0.identifier == targetId }.count, 1)
    }

    private func requireNotificationScheduling() async throws {
        if await userNotificationCenter.authorizationStatus() == .notDetermined {
            _ = try await userNotificationCenter.requestAuthorization(options: [.provisional])
        }

        let status = await userNotificationCenter.authorizationStatus()
        try XCTSkipUnless(status == .provisional || status == .authorized,
                          "Notification scheduling is unavailable: authorization status is \(status.stringValue).")

        // A simulator can report authorization while its notification repository rejects requests.
        // Check the system independently before exercising the scheduler; never skip a scheduler assertion.
        let identifier = "com.duckduckgo.tests.notification-capability.\(UUID().uuidString)"
        let content = UNMutableNotificationContent()
        content.title = "Notification integration test"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 86_400, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        defer { userNotificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier]) }

        do {
            try await userNotificationCenter.add(request)
        } catch {
            #if targetEnvironment(simulator)
            let notificationError = error as NSError
            // The iOS 27 CI simulator reports repository authorization denial as code 2003 with this marker.
            let repositoryAuthorizationStatus = notificationError.userInfo["UNAuthorizationStatus"] as? String
            let isRepositoryAuthorizationDenied = notificationError.code == 2003 && repositoryAuthorizationStatus == "Denied"
            if notificationError.domain == UNErrorDomain,
               notificationError.code == UNError.Code.notificationsNotAllowed.rawValue || isRepositoryAuthorizationDenied {
                throw XCTSkip("Simulator rejected an independent notification with authorization status \(status.stringValue): \(notificationError).")
            }
            #endif
            throw error
        }
    }
}
