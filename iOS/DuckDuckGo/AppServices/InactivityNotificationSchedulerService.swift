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
    
    // MARK: - Constants
    
    enum Constants {
        static let daysInactiveSettingKey: String = "daysInactive"
        static let defaultDaysInactive: Int = 7 // default to 7 days
        static let notificationIdentifier = "com.duckduckgo.inactivity.notification"
        static let subfeature: any PrivacySubfeature = iOSBrowserConfigSubfeature.inactivityNotification
    }
    
    // MARK: - Dependencies
    
    private let featureFlagger: FeatureFlagger
    private let notificationServiceManager: NotificationServiceManaging
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let userNotificationCenter: UNUserNotificationCenterRepresentable
    
    init(featureFlagger: FeatureFlagger,
         notificationServiceManager: NotificationServiceManaging,
         privacyConfigurationManager: PrivacyConfigurationManaging,
         userNotificationCenter: UNUserNotificationCenterRepresentable = UNUserNotificationCenter.current(),
    ) {
        self.featureFlagger = featureFlagger
        self.notificationServiceManager = notificationServiceManager
        self.privacyConfigurationManager = privacyConfigurationManager
        self.userNotificationCenter = userNotificationCenter
        
        self.userNotificationCenter.delegate = notificationServiceManager
    }
    
    // MARK: - Public
    
    @discardableResult
    func resume() -> Task<Void, Never> {
        guard isFeatureEnabled() else {
            cancelPendingNotifications()
            return Task {} // noop
        }
        return Task {
            await schedule()
        }
    }
    
    func schedule() async {
        cancelPendingNotifications()
        await requestProvisionalAuthorizationIfNeeded()
        
        let status = await userNotificationCenter.authorizationStatus()
        guard status == .provisional else { return }
            
        let request = buildUNNotificationRequest()
        do {
            try await userNotificationCenter.add(request)
        } catch {
            Logger.pushNotification.error("Inactivity notification scheduling failed with \(error.localizedDescription, privacy: .public)")
        }
    }
    
    func requestProvisionalAuthorizationIfNeeded() async {
        let currentStatus = await userNotificationCenter.authorizationStatus()
        
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
    
    func makeUNNotificationContent(with daysInactive: Int = Constants.defaultDaysInactive) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = UserText.inactivityNotificationTitle
        content.body = UserText.inactivityNotificationBody
        content.userInfo = [Constants.daysInactiveSettingKey: daysInactive]
        return content
    }
    
    func makeDaysInactive() -> Int {
        guard let settings = privacyConfigurationManager.privacyConfig.settings(for: Constants.subfeature),
              let jsonData = settings.data(using: .utf8) else { return Constants.defaultDaysInactive }
        
        do {
            if let settingsDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: String],
               let daysInactiveStr = settingsDict[Constants.daysInactiveSettingKey],
               let daysInactive = Int(daysInactiveStr), daysInactive >= 1 {
                return daysInactive
            }
        } catch {
            Logger.pushNotification.error("Inactivity notification daysInactiveSettingKey parsed failed with \(error.localizedDescription, privacy: .public)")
        }
        
        return Constants.defaultDaysInactive
    }
    
    // MARK: - Private
    
    private func isFeatureEnabled() -> Bool {
        return featureFlagger.isFeatureOn(.inactivityNotification)
    }
    
    private func cancelPendingNotifications() {
        userNotificationCenter.removePendingNotificationRequests(withIdentifiers: [Constants.notificationIdentifier])
    }
    
    private func buildUNNotificationRequest() -> UNNotificationRequest {
        let daysInactive = makeDaysInactive()
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: .days(daysInactive), repeats: false)
        return UNNotificationRequest(
            identifier: Constants.notificationIdentifier,
            content: makeUNNotificationContent(with: daysInactive),
            trigger: trigger
        )
    }
}

extension Logger {
    static var pushNotification = { Logger(subsystem: "Push Notification", category: "") }()
}
