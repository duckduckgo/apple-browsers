//
//  SyncNotificationSettings.swift
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

import Core
import Persistence
import SyncUI_iOS
import UIKit
import UserNotifications

enum SyncNotificationSettingsKey: String, StorageKeyDescribing {
    case isEnabled = "sync-login-notifications-enabled"
    case isPermissionCardDismissed = "sync-login-notifications-permission-card-dismissed"
}

struct SyncNotificationSettingsStorageKeys: StoringKeys {
    let isEnabled = StorageKey<Bool>(SyncNotificationSettingsKey.isEnabled)
    let isPermissionCardDismissed = StorageKey<Bool>(SyncNotificationSettingsKey.isPermissionCardDismissed)
}

@MainActor
protocol SyncNotificationSettingsReading: AnyObject {
    var isEnabled: Bool { get }
    func authorizationStatus() async -> UNAuthorizationStatus
}

@MainActor
final class SyncNotificationSettings: SyncNotificationSettingsProviding, SyncNotificationSettingsReading {
    static let didChange = Notification.Name("SyncNotificationSettingsDidChange")
    private let changes: NotificationCenter
    private let storage: any KeyedStoring<SyncNotificationSettingsStorageKeys>
    private let notificationCenter: UNUserNotificationCenterRepresentable

    var isEnabled: Bool {
        get { storage.isEnabled ?? true }
        set {
            guard isEnabled != newValue else { return }
            storage.isEnabled = newValue
            changes.post(name: Self.didChange, object: nil)
        }
    }

    var isPermissionCardDismissed: Bool {
        get { storage.isPermissionCardDismissed ?? false }
        set { storage.isPermissionCardDismissed = newValue }
    }

    init(storage: any KeyedStoring<SyncNotificationSettingsStorageKeys> = UserDefaults.app.keyedStoring(),
         notificationCenter: UNUserNotificationCenterRepresentable = UNUserNotificationCenter.current(),
         changes: NotificationCenter = .default) {
        self.changes = changes
        self.storage = storage
        self.notificationCenter = notificationCenter
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await notificationCenter.authorizationStatus()
    }

    func requestAuthorization() async throws {
        defer { changes.post(name: Self.didChange, object: nil) }
        _ = try await notificationCenter.requestAuthorization(options: [.alert])
    }

    func openNotificationSettings() async {
        _ = await UIApplication.shared.openAppNotificationSettings()
    }
}
