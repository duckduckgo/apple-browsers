//
//  SyncLoginNotificationService.swift
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

import DDGSync
import FeatureFlags_iOS
import Foundation
import PrivacyConfig
import UserNotifications
import os.log

@MainActor
final class SyncLoginNotificationService {
    nonisolated static let categoryIdentifier = "sync-login"
    nonisolated static let notificationCategory = UNNotificationCategory(identifier: categoryIdentifier,
                                                                        actions: [],
                                                                        intentIdentifiers: [])
    nonisolated static let activityType = "com.duckduckgo.sync.device-activity"
    nonisolated static let accountIDKey = "syncAccountID"

    private let syncService: DDGSyncing
    private let featureFlagger: FeatureFlagger
    private let notificationCenter: UNUserNotificationCenterRepresentable

    init(syncService: DDGSyncing,
         featureFlagger: FeatureFlagger,
         notificationCenter: UNUserNotificationCenterRepresentable = UNUserNotificationCenter.current()) {
        self.syncService = syncService
        self.featureFlagger = featureFlagger
        self.notificationCenter = notificationCenter
    }

    func deliver(_ notification: SyncLoginNotification) async {
        do {
            guard !notification.events.isEmpty, try canDeliver(for: notification.accountID) else { return }
            var status = await notificationCenter.authorizationStatus()
            if status == .notDetermined {
                guard try canDeliver(for: notification.accountID), !Task.isCancelled else { return }
                _ = try await notificationCenter.requestAuthorization(options: [.provisional, .alert])
                status = await notificationCenter.authorizationStatus()
            }
            guard status == .authorized || status == .provisional,
                  try canDeliver(for: notification.accountID), !Task.isCancelled else { return }
            let reviewDate = try syncService.auditLogReviewState(for: notification.accountID)?.reviewedThrough
            let events = notification.events.filter { event in reviewDate.map { event.occurredAt > $0 } ?? true }
            guard !events.isEmpty else { return }
            let content = UNMutableNotificationContent()
            content.title = UserText.syncLoginNotificationTitle
            content.body = events.count == 1 ? UserText.syncLoginNotificationBody : UserText.syncLoginNotificationPluralBody
            content.categoryIdentifier = Self.categoryIdentifier
            content.userInfo = [Self.accountIDKey: notification.accountID]
            // Await scheduling before DDGSync commits the poll. Delivery failure does not block the next poll.
            try await notificationCenter.add(UNNotificationRequest(identifier: notification.identifier, content: content, trigger: nil))
        } catch {
            Logger.sync.error("Failed to schedule Sync login notification: \(String(reflecting: error), privacy: .private)")
        }
    }

    private func canDeliver(for accountID: String) throws -> Bool {
        guard featureFlagger.isFeatureOn(.syncLoginAuditLog),
              featureFlagger.isFeatureOn(.syncLoginNotification) else { return false }
        return try syncService.isAuditLogPollingAvailable(forAccountID: accountID)
    }

    static func canOpenActivity(for accountID: String, syncService: DDGSyncing, featureFlagger: FeatureFlagger) -> Bool {
        featureFlagger.isFeatureOn(.syncLoginAuditLog)
            && syncService.account?.userId == accountID
            && (syncService.authState == .active || syncService.authState == .addingNewDevice)
    }

    nonisolated static func activity(for request: UNNotificationRequest) -> NSUserActivity? {
        guard request.content.categoryIdentifier == categoryIdentifier,
              let accountID = request.content.userInfo[accountIDKey] as? String else { return nil }
        let activity = NSUserActivity(activityType: activityType)
        activity.userInfo = [accountIDKey: accountID]
        return activity
    }
}
