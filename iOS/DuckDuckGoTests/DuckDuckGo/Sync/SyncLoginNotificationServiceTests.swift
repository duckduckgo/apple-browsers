//
//  SyncLoginNotificationServiceTests.swift
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
@testable import DDGSync
import UserNotifications
@_spi(Testing) import Persistence
@testable import DuckDuckGo

@MainActor
final class SyncLoginNotificationServiceTests: XCTestCase {
    private var sync: MockDDGSyncing!
    private var flags: MockFeatureFlagger!
    private var center: MockUNUserNotificationCenter!
    private var service: SyncLoginNotificationService!
    private var settingsStorage: (any KeyedStoring<SyncNotificationSettingsStorageKeys>)!

    override func setUpWithError() throws {
        sync = MockDDGSyncing(authState: .active, isSyncInProgress: false)
        sync.account = SyncAccount(deviceId: "this", deviceName: "This device", deviceType: "phone", userId: "account",
                                   primaryKey: Data(), secretKey: Data(), token: "token", state: .active)
        sync.isAuditLogPollingAvailableStub = true
        flags = MockFeatureFlagger(enabledFeatureFlags: [.syncLoginAuditLog, .syncLoginNotification])
        center = MockUNUserNotificationCenter()
        settingsStorage = MockKeyValueStore().keyedStoring()
        service = SyncLoginNotificationService(syncService: sync, featureFlagger: flags, notificationCenter: center,
                                               settings: SyncNotificationSettings(storage: settingsStorage, notificationCenter: center))
    }

    private func notification(count: Int = 1, accountID: String = "account") -> SyncLoginNotification {
        SyncLoginNotification(identifier: "sync-login-batch", accountID: accountID,
                              events: (0..<count).map {
            SyncLoginEvent(id: "event-\($0)", occurredAt: Date(), deviceName: "Phone")
        })
    }

    func testDeliveryDoesNotRequireUIReadiness() async {
        sync.authState = .initializing
        center.authorizationStatus = .authorized

        await service.deliver(notification())

        XCTAssertEqual(center.addedRequests.count, 1)
        XCTAssertFalse(SyncLoginNotificationService.canOpenActivity(for: "account", syncService: sync, featureFlagger: flags))
    }

    func testUnavailablePollingPreventsDeliveryAndPermissionRequest() async {
        sync.isAuditLogPollingAvailableStub = false

        await service.deliver(notification())

        XCTAssertFalse(center.didRequestAuthorization)
        XCTAssertTrue(center.addedRequests.isEmpty)
    }

    func testPollingBecomingUnavailableDuringAuthorizationPreventsDelivery() async {
        center.authorizationStatusHandler = { [unowned self] in
            self.sync.isAuditLogPollingAvailableStub = false
            return .notDetermined
        }

        await service.deliver(notification())

        XCTAssertFalse(center.didRequestAuthorization)
        XCTAssertTrue(center.addedRequests.isEmpty)
    }

    func testStorageFailurePreventsDeliveryAndPermissionRequest() async {
        sync.isAuditLogPollingAvailableError = SyncError.failedToReadSecureStore(status: -25308)

        await service.deliver(notification())

        XCTAssertFalse(center.didRequestAuthorization)
        XCTAssertTrue(center.addedRequests.isEmpty)
    }

    func testNotDeterminedRequestsProvisionalAuthorizationAndSchedulesSingularCopy() async throws {
        await service.deliver(notification())
        XCTAssertTrue(center.didRequestAuthorization)
        XCTAssertTrue(center.requestedAuthorizationOptions.contains(.provisional))
        let request = try XCTUnwrap(center.addedRequests.first)
        XCTAssertTrue(NotificationServiceManager.notificationCategories.contains(SyncLoginNotificationService.notificationCategory))
        XCTAssertEqual(request.content.categoryIdentifier, SyncLoginNotificationService.notificationCategory.identifier)
        XCTAssertEqual(request.content.title, "Sync & Backup Activity")
        XCTAssertEqual(request.content.body, "A new device has been added to Sync & Backup.")
        XCTAssertEqual(request.content.userInfo[SyncLoginNotificationService.accountIDKey] as? String, "account")
        XCTAssertNil(request.trigger)
    }

    func testExistingPermissionSchedulesOneCombinedNotificationWithoutPrompt() async throws {
        for status: UNAuthorizationStatus in [.authorized, .provisional] {
            center.authorizationStatus = status
            await service.deliver(notification(count: 3))
        }
        XCTAssertFalse(center.didRequestAuthorization)
        XCTAssertEqual(center.addedRequests.count, 2)
        XCTAssertTrue(center.addedRequests.allSatisfy { $0.content.body == "New devices have been added to Sync & Backup." })
    }

    func testOptOutPreventsQuietAndFullDeliveryAndRuntimeChangesTakeEffect() async {
        settingsStorage.isEnabled = false
        for status: UNAuthorizationStatus in [.notDetermined, .provisional, .authorized] {
            center.authorizationStatus = status
            await service.deliver(notification())
        }
        XCTAssertFalse(center.didRequestAuthorization)
        XCTAssertTrue(center.addedRequests.isEmpty)
        settingsStorage.isEnabled = true
        for status: UNAuthorizationStatus in [.provisional, .authorized] {
            center.authorizationStatus = status
            await service.deliver(notification())
        }
        XCTAssertEqual(center.addedRequests.count, 2)
    }

    func testNotificationSettingsPersistAndRequestFullAuthorization() async throws {
        let settings = SyncNotificationSettings(storage: settingsStorage, notificationCenter: center)
        XCTAssertTrue(settings.isEnabled)
        XCTAssertFalse(settings.isPermissionCardDismissed)
        settings.isEnabled = false
        settings.isPermissionCardDismissed = true
        let reopened = SyncNotificationSettings(storage: settingsStorage, notificationCenter: center)
        XCTAssertFalse(reopened.isEnabled)
        XCTAssertTrue(reopened.isPermissionCardDismissed)
        try await reopened.requestAuthorization()
        XCTAssertEqual(center.requestedAuthorizationOptions, [.alert])
        XCTAssertFalse(center.requestedAuthorizationOptions.contains(.provisional))
    }

    func testDeniedAuthorizationNeverPromptsOrSchedules() async {
        center.authorizationStatus = .denied
        await service.deliver(notification())
        XCTAssertFalse(center.didRequestAuthorization)
        XCTAssertTrue(center.addedRequests.isEmpty)
    }

    func testBothFlagsAreRequiredAndRuntimeChangesTakeEffect() async {
        center.authorizationStatus = .authorized
        flags.enabledFeatureFlags = [.syncLoginAuditLog]
        await service.deliver(notification())
        flags.enabledFeatureFlags = [.syncLoginNotification]
        await service.deliver(notification())
        flags.enabledFeatureFlags = []
        await service.deliver(notification())
        XCTAssertTrue(center.addedRequests.isEmpty)
        flags.enabledFeatureFlags = [.syncLoginAuditLog, .syncLoginNotification]
        await service.deliver(notification())
        XCTAssertEqual(center.addedRequests.count, 1)
    }

    func testAccountChangeOrFlagDisableDuringAuthorizationPreventsScheduling() async {
        center.authorizationStatusHandler = { [unowned self] in
            self.sync.account = nil
            return .authorized
        }
        await service.deliver(notification())
        XCTAssertTrue(center.addedRequests.isEmpty)
        center.authorizationStatusHandler = { [unowned self] in
            self.flags.enabledFeatureFlags = [.syncLoginAuditLog]
            return .authorized
        }
        sync.account = SyncAccount(deviceId: "this", deviceName: "This", deviceType: "phone", userId: "account",
                                   primaryKey: Data(), secretKey: Data(), token: "token", state: .active)
        await service.deliver(notification())
        XCTAssertTrue(center.addedRequests.isEmpty)
    }

    func testSchedulingAndAuthorizationErrorsReturnWithoutThrowing() async {
        center.requestAuthError = .requestAuthError
        await service.deliver(notification())
        center.requestAuthError = nil
        center.authorizationStatus = .authorized
        center.addRequestError = .addRequestError
        await service.deliver(notification())
        XCTAssertTrue(center.addedRequests.isEmpty)
    }

    func testEmptyBatchAndWrongAccountDoNotRequestPermission() async {
        await service.deliver(notification(count: 0))
        await service.deliver(notification(accountID: "previous-account"))
        XCTAssertFalse(center.didRequestAuthorization)
        XCTAssertTrue(center.addedRequests.isEmpty)
    }

    func testTapRoutingRequiresCurrentAccountAndAuditLogFlagButNotNotificationFlag() {
        XCTAssertTrue(SyncLoginNotificationService.canOpenActivity(for: "account", syncService: sync, featureFlagger: flags))
        flags.enabledFeatureFlags = [.syncLoginAuditLog]
        XCTAssertTrue(SyncLoginNotificationService.canOpenActivity(for: "account", syncService: sync, featureFlagger: flags))
        XCTAssertFalse(SyncLoginNotificationService.canOpenActivity(for: "old-account", syncService: sync, featureFlagger: flags))
        sync.authState = .inactive
        XCTAssertFalse(SyncLoginNotificationService.canOpenActivity(for: "account", syncService: sync, featureFlagger: flags))
        sync.authState = .active
        flags.enabledFeatureFlags = []
        XCTAssertFalse(SyncLoginNotificationService.canOpenActivity(for: "account", syncService: sync, featureFlagger: flags))
    }

    func testNotificationActivityIsDeferredUntilSceneAndForegroundAreReady() throws {
        let content = UNMutableNotificationContent()
        content.categoryIdentifier = SyncLoginNotificationService.categoryIdentifier
        content.userInfo = [SyncLoginNotificationService.accountIDKey: "account"]
        let request = UNNotificationRequest(identifier: "batch", content: content, trigger: nil)
        let activity = try XCTUnwrap(SyncLoginNotificationService.activity(for: request))
        let machine = AppStateMachine(initialState: .initializing(MockInitializing()))
        machine.handle(.didFinishLaunching(isTesting: false))
        XCTAssertTrue(NotificationServiceManager.handleSyncNotification(request: request) { machine.handle($0) })
        guard case .handleUserActivity(let retained)? = machine.actionToHandle else { return XCTFail("Expected deferred activity") }
        XCTAssertEqual(retained.activityType, activity.activityType)
        XCTAssertEqual(retained.userInfo?[SyncLoginNotificationService.accountIDKey] as? String, "account")
        machine.handle(.willConnectToWindow(window: UIWindow()))
        machine.handle(.didBecomeActive)
        XCTAssertNil(machine.actionToHandle)
        guard case .foreground(let foreground) = machine.currentState,
              let mock = foreground as? MockForeground,
              case .handleUserActivity(let delivered)? = mock.actionToHandle else { return XCTFail("Expected activity delivered to foreground") }
        XCTAssertEqual(delivered.activityType, activity.activityType)
        XCTAssertEqual(delivered.userInfo?[SyncLoginNotificationService.accountIDKey] as? String, "account")
    }

    func testUnrelatedOrMalformedNotificationDoesNotCreateActivity() {
        let content = UNMutableNotificationContent()
        let request = UNNotificationRequest(identifier: "unrelated", content: content, trigger: nil)
        XCTAssertNil(SyncLoginNotificationService.activity(for: request))
        content.categoryIdentifier = SyncLoginNotificationService.categoryIdentifier
        XCTAssertNil(SyncLoginNotificationService.activity(for: UNNotificationRequest(identifier: "malformed", content: content, trigger: nil)))
    }

    func testReviewedEntriesAreFilteredAgainAfterAuthorizationCompletes() async throws {
        center.authorizationStatus = .authorized
        let cutoff = Date(timeIntervalSince1970: 100)
        let batch = SyncLoginNotification(identifier: "batch", accountID: "account", events: [
            SyncLoginEvent(id: "reviewed", occurredAt: cutoff, deviceName: "First"),
            SyncLoginEvent(id: "new", occurredAt: Date(timeIntervalSince1970: 101), deviceName: "Second")
        ])
        center.authorizationStatusHandler = { [unowned self] in
            try? self.sync.setAuditLogReviewState(SyncAuditLogReviewState(reviewedThrough: cutoff, isInitialized: true), for: "account")
            return .authorized
        }
        await service.deliver(batch)
        XCTAssertEqual(center.addedRequests.count, 1)
        XCTAssertEqual(center.addedRequests.first?.content.body, "A new device has been added to Sync & Backup.")
    }

    func testFullyReviewedBatchDoesNotScheduleNotification() async throws {
        center.authorizationStatus = .authorized
        try sync.setAuditLogReviewState(SyncAuditLogReviewState(reviewedThrough: .distantFuture, isInitialized: true), for: "account")
        await service.deliver(notification(count: 2))
        XCTAssertTrue(center.addedRequests.isEmpty)
    }

}
