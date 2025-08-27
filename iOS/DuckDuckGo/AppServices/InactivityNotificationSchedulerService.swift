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
    
    // MARK: - Dependencies
    
    private let featureFlagger: FeatureFlagger
    private let userNotificationCenter: UNUserNotificationCenter
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let notificationServiceManager: NotificationServiceManaging
    
    // MARK: - Constants
    
    static let notificationIdentifier = "com.duckduckgo.inactivity.notification"
    static let defaultDaysInactive: Double = 7.0 // default to 7 days
    static let daysInactiveSettingKey: String = "daysInactive"
    private static let subfeature: any PrivacySubfeature = iOSBrowserConfigSubfeature.inactivityNotification
    
    init(featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger,
         userNotificationCenter: UNUserNotificationCenter = .current(),
         privacyConfigurationManager: PrivacyConfigurationManaging = ContentBlocking.shared.privacyConfigurationManager,
         notificationServiceManager: NotificationServiceManaging
    ) {
        self.featureFlagger = featureFlagger
        self.userNotificationCenter = userNotificationCenter
        self.privacyConfigurationManager = privacyConfigurationManager
        self.notificationServiceManager = notificationServiceManager
        
        userNotificationCenter.delegate = self.notificationServiceManager
    }
    
    // MARK: - Public
    
    func resume() {
        guard isFeatureEnabled() else {
            cancelPendingNotifications()
            return
        }
        Task {
            await schedule()
        }
    }
    
    private func isFeatureEnabled() -> Bool {
        return featureFlagger.isFeatureOn(.inactivityNotification)
    }
    
    private func cancelPendingNotifications() {
        userNotificationCenter.removePendingNotificationRequests(withIdentifiers: [Self.notificationIdentifier])
    }
    
    private func schedule() async {
        cancelPendingNotifications()
        await requestProvisionalAuthorizationIfNeeded()
        
        let status = await userNotificationCenter.notificationSettings().authorizationStatus
        guard status == .provisional else { return }
            
        let request = buildUNNotificationRequest()
        do {
            try await userNotificationCenter.add(request)
        } catch {
            Logger.pushNotification.error("Inactivity notification scheduling failed with \(error.localizedDescription, privacy: .public)")
        }
    }
    
    private func requestProvisionalAuthorizationIfNeeded() async {
        let currentStatus = await userNotificationCenter.notificationSettings().authorizationStatus
        
        switch currentStatus {
        case .notDetermined:
            do {
                _ = try await userNotificationCenter.requestAuthorization(options: [.provisional])
            } catch {
                Logger.pushNotification.error("Inactivity notification authorization request failed with \(error.localizedDescription, privacy: .public)")
            }
        default:
            break
        }
    }
    
    private func buildUNNotificationRequest() -> UNNotificationRequest {
        let daysInactive = makeDaysInactive()
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: daysInactive.toSeconds(), repeats: false)
        return UNNotificationRequest(
            identifier: Self.notificationIdentifier,
            content: makeUNNotificationContent(with: daysInactive),
            trigger: trigger
        )
    }
    
    func makeUNNotificationContent(with daysInactive: Double = defaultDaysInactive) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = UserText.inactivityNotificationTitle
        content.body = UserText.inactivityNotificationBody
        content.userInfo = [Self.daysInactiveSettingKey: daysInactive]
        return content
    }
    
    func makeDaysInactive() -> Double {
        guard let settings = privacyConfigurationManager.privacyConfig.settings(for: Self.subfeature),
              let jsonData = settings.data(using: .utf8) else { return Self.defaultDaysInactive }
        do {
            if let settingsDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: String],
               let daysInactiveStr = settingsDict[Self.daysInactiveSettingKey],
               let daysInactive = Double(daysInactiveStr) {
                return daysInactive
            }
        } catch {
            Logger.pushNotification.error("Inactivity notification daysInactiveSettingKey parsed failed with \(error.localizedDescription, privacy: .public)")
        }
        return Self.defaultDaysInactive
    }
}

private extension Double {
    func toSeconds() -> Double {
        return self * 60 * 60 * 24
    }
}

extension Logger {
    static var pushNotification = { Logger(subsystem: "Push Notification", category: "") }()
}
