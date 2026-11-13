//
//  SyncNotificationSettingsViewModelTests.swift
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

import Testing
import UserNotifications
import UIKit
@testable import SyncUI_iOS

@MainActor
@Suite("Sync notification settings")
struct SyncNotificationSettingsViewModelTests {
    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [UNAuthorizationStatus.notDetermined, .provisional, .denied])
    func permissionWithoutFullAuthorizationShowsToggleOffAndCard(status: UNAuthorizationStatus) async {
        let provider = MockSyncNotificationSettingsProvider(status: status)
        let model = SyncNotificationSettingsViewModel(provider: provider)
        await model.refresh()
        #expect(!model.isToggleOn)
        #expect(model.shouldShowPermissionCard)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func authorizedDefaultsOnButPreservesOptOut() async {
        let provider = MockSyncNotificationSettingsProvider(status: .authorized)
        let model = SyncNotificationSettingsViewModel(provider: provider)
        await model.refresh()
        #expect(model.isToggleOn)
        #expect(!model.shouldShowPermissionCard)
        await model.setEnabled(false)
        #expect(!provider.isEnabled)
        await model.refresh()
        #expect(!model.isToggleOn)
        await model.setEnabled(true)
        #expect(provider.isEnabled)
        #expect(model.isToggleOn)
        #expect(provider.requestCount == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [UNAuthorizationStatus.notDetermined, .provisional])
    func enablingRequestsFullPermissionAndUpdatesToggle(status: UNAuthorizationStatus) async {
        let provider = MockSyncNotificationSettingsProvider(status: status)
        provider.isEnabled = false
        provider.requestResult = .authorized
        let model = SyncNotificationSettingsViewModel(provider: provider)
        await model.setEnabled(true)
        #expect(provider.requestCount == 1)
        #expect(model.isToggleOn)
        #expect(provider.isEnabled)
        #expect(!model.shouldShowPermissionCard)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func denialKeepsToggleOffAndNextAttemptOffersSettings() async {
        let provider = MockSyncNotificationSettingsProvider(status: .provisional)
        provider.requestResult = .denied
        let model = SyncNotificationSettingsViewModel(provider: provider)
        await model.enableNotifications()
        #expect(!model.isToggleOn)
        #expect(!model.isSettingsAlertPresented)
        await model.enableNotifications()
        #expect(provider.requestCount == 1)
        #expect(model.isSettingsAlertPresented)
        #expect(provider.openSettingsCount == 0)
        await model.openNotificationSettings()
        #expect(provider.openSettingsCount == 1)
        #expect(!model.isToggleOn)
        provider.status = .authorized
        await model.refresh()
        #expect(model.isToggleOn)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func failedPermissionRequestPreservesPreferenceAndAllowsRetry() async {
        let provider = MockSyncNotificationSettingsProvider(status: .provisional)
        provider.isEnabled = false
        provider.requestError = TestError.failed
        let model = SyncNotificationSettingsViewModel(provider: provider)
        await model.enableNotifications()
        #expect(!model.isRequestingPermission)
        #expect(!model.isToggleOn)
        #expect(!provider.isEnabled)
        provider.requestError = nil
        provider.requestResult = .authorized
        await model.enableNotifications()
        #expect(model.isToggleOn)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func dismissalPersistsWithoutDisablingNotificationsOrBlockingToggle() async {
        let provider = MockSyncNotificationSettingsProvider(status: .provisional)
        let model = SyncNotificationSettingsViewModel(provider: provider)
        await model.refresh()
        model.dismissPermissionCard()
        #expect(!model.shouldShowPermissionCard)
        #expect(provider.isPermissionCardDismissed)
        #expect(provider.isEnabled)
        let reopened = SyncNotificationSettingsViewModel(provider: provider)
        await reopened.refresh()
        #expect(!reopened.shouldShowPermissionCard)
        provider.requestResult = .authorized
        await reopened.setEnabled(true)
        #expect(reopened.isToggleOn)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func returningFromSettingsReflectsPermissionChangesWithoutLosingPreference() async {
        let provider = MockSyncNotificationSettingsProvider(status: .authorized)
        let model = SyncNotificationSettingsViewModel(provider: provider)
        await model.refresh()
        provider.status = .denied
        await model.refresh()
        #expect(!model.isToggleOn)
        #expect(provider.isEnabled)
        #expect(model.shouldShowPermissionCard)
        provider.status = .authorized
        await model.refresh()
        #expect(model.isToggleOn)
        #expect(!model.shouldShowPermissionCard)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func denialDoesNotSaveSyncOptOutWhenAppPermissionIsLaterGranted() async {
        let provider = MockSyncNotificationSettingsProvider(status: .provisional)
        provider.requestResult = .denied
        let model = SyncNotificationSettingsViewModel(provider: provider)
        await model.enableNotifications()
        #expect(!model.isToggleOn)
        #expect(provider.isEnabled)
        provider.status = .authorized
        await model.refresh()
        #expect(model.isToggleOn)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func explicitOptOutSurvivesAppPermissionChangesAndReopening() async {
        let provider = MockSyncNotificationSettingsProvider(status: .authorized)
        let model = SyncNotificationSettingsViewModel(provider: provider)
        await model.setEnabled(false)
        provider.status = .denied
        await model.refresh()
        provider.status = .authorized
        let reopened = SyncNotificationSettingsViewModel(provider: provider)
        await reopened.refresh()
        #expect(!reopened.isToggleOn)
        #expect(!provider.isEnabled)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func descriptionUsesDeviceTypeWithGenericFallback() {
        #expect(UserText.syncNotificationsDescription(for: .phone) == "Get notified whenever a new device syncs with this iPhone.")
        #expect(UserText.syncNotificationsDescription(for: .pad) == "Get notified whenever a new device syncs with this iPad.")
        #expect(UserText.syncNotificationsDescription(for: .unspecified) == "Get notified whenever a new device syncs with this device.")
        #expect(UserText.syncNotificationsDescription(for: .mac) == "Get notified whenever a new device syncs with this device.")
    }

    private enum TestError: Error { case failed }
}

@MainActor
final class MockSyncNotificationSettingsProvider: SyncNotificationSettingsProviding {
    var isEnabled = true
    var isPermissionCardDismissed = false
    var status: UNAuthorizationStatus
    var requestResult: UNAuthorizationStatus = .authorized
    var requestError: Error?
    var requestCount = 0
    var openSettingsCount = 0

    init(status: UNAuthorizationStatus) {
        self.status = status
    }

    func authorizationStatus() async -> UNAuthorizationStatus { status }

    func requestAuthorization() async throws {
        requestCount += 1
        if let requestError { throw requestError }
        status = requestResult
    }

    func openNotificationSettings() async { openSettingsCount += 1 }
}
