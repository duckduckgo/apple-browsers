//
//  InactivityNotificationSchedulerService.swift
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

import UIKit
import UserNotifications
import Core
import BrowserServicesKit

final class InactivityNotificationSchedulerService {
    
    private let featureFlagger: FeatureFlagger
    private let userNotificationCenter: UNUserNotificationCenter
    private let notificationPermissionsController: NotificationsAuthorizationControlling
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    
    static let notificationIdentifier = "com.duckduckgo.inactivity.notification"
    private let defaultNotificationSchedulingTime: Double = 7 * 60 * 60 * 24 // default to 7 days
    private let subfeature: any PrivacySubfeature = iOSBrowserConfigSubfeature.inactivityNotification
    
    init(featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         userNotificationCenter: UNUserNotificationCenter = UNUserNotificationCenter.current(),
         notificationPermissionsController: NotificationsAuthorizationControlling = NotificationsAuthorizationController(),
         privacyConfigurationManager: PrivacyConfigurationManaging = ContentBlocking.shared.privacyConfigurationManager,
    ) {
        self.featureFlagger = featureFlagger
        self.userNotificationCenter = userNotificationCenter
        self.notificationPermissionsController = notificationPermissionsController
        self.privacyConfigurationManager = privacyConfigurationManager
    }
    
    // MARK: - Public
    
    func resume() {
        guard isFeatureEnabled() else {
            cancelPendingNotifications()
            return
        }
        
        schedule()
    }
    
    // MARK: - Private
    
    private func isFeatureEnabled() -> Bool {
        return featureFlagger.isFeatureOn(.inactivityNotification)
    }
    
    private func schedule() {
        Task { @MainActor in
            cancelPendingNotifications()
            await requestProvisionalAuthorizationIfNeeded()
            let request = buildUNNotificationRequest()
            try? await userNotificationCenter.add(request)
        }
    }
    
    private func cancelPendingNotifications() {
        userNotificationCenter.removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])
    }
    
    private func requestProvisionalAuthorizationIfNeeded() async {
        let currentStatus = await notificationPermissionsController.authorizationStatus
        
        switch currentStatus {
        case .notDetermined:
            do {
                let granted = try await userNotificationCenter.requestAuthorization(options: [.provisional])
            } catch {
                break
            }
        default:
            break
        }
    }
    
    private func buildUNNotificationRequest() -> UNNotificationRequest {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: makeTimeInterval(), repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.notificationIdentifier,
            content: makeUNNotificationContent(),
            trigger: trigger
        )
        return request
    }
    
    private func makeUNNotificationContent() -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = UserText.inactivityNotificationTitle
        content.body = UserText.inactivityNotificationBody
        return content
    }
    
    private func makeTimeInterval() -> Double {
        guard let settings = privacyConfigurationManager.privacyConfig.settings(for: subfeature),
              let jsonData = settings.data(using: .utf8) else { return defaultNotificationSchedulingTime }
        do {
            if let settingsDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: String],
               let daysInactiveStr = settingsDict["daysInactive"],
               let daysInactive = Double(daysInactiveStr)
            {
                return daysInactive * 24 * 60 * 60
            }
        } catch {
            // No op
        }
        return defaultNotificationSchedulingTime
    }
}
