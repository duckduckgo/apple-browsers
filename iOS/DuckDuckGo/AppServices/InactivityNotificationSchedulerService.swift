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
import FoundationExtensions
import Core
import PrivacyConfig
import FeatureFlags_iOS

final class InactivityNotificationSchedulerService {
    
    // MARK: - Constants
    
    enum Constants {
        static let notificationIdentifier = "com.duckduckgo.inactivity.notification"
        static let subfeature: any PrivacySubfeature = iOSBrowserConfigSubfeature.inactivityNotification

        static let notificationCategory = UNNotificationCategory(identifier: notificationIdentifier,
                                                                 actions: [],
                                                                 intentIdentifiers: [],
                                                                 options: [.customDismissAction])
    }

    enum Settings: String {
        case daysInactive
        case maxInteractions

        var defaultValue: Int {
            switch self {
            case .daysInactive: return 7 // default to 7 days
            case .maxInteractions: return 4 // default to 4 interactions
            }
        }

        func value(from settings: [String: Any]?) -> Int {
            guard let value = settings?[rawValue] as? Int, value >= 1 else {
                return defaultValue
            }
            return value
        }
    }

    // MARK: - Dependencies

    private let featureFlagger: FeatureFlagger
    private let notificationServiceManager: NotificationServiceManaging
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let stateStore: InactivityNotificationStateStoring
    private let userNotificationCenter: UNUserNotificationCenterRepresentable

    init(featureFlagger: FeatureFlagger,
         notificationServiceManager: NotificationServiceManaging,
         privacyConfigurationManager: PrivacyConfigurationManaging,
         stateStore: InactivityNotificationStateStoring,
         userNotificationCenter: UNUserNotificationCenterRepresentable = UNUserNotificationCenter.current(),
    ) {
        self.featureFlagger = featureFlagger
        self.notificationServiceManager = notificationServiceManager
        self.privacyConfigurationManager = privacyConfigurationManager
        self.stateStore = stateStore
        self.userNotificationCenter = userNotificationCenter

        self.userNotificationCenter.delegate = notificationServiceManager
    }
    
    // MARK: - Public
    
    @discardableResult
    func resume() -> Task<Void, Never> {
        guard isFeatureEnabled(),
              stateStore.interactionCount < maxInteractions else {
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
        guard status == .provisional || status == .authorized,
              stateStore.interactionCount < maxInteractions else {
            return
        }

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
    
    static func makeUNNotificationContent(with daysInactive: Int = Settings.daysInactive.defaultValue) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = UserText.inactivityNotificationTitle
        content.body = UserText.inactivityNotificationBody
        content.userInfo = [Settings.daysInactive.rawValue: daysInactive]
        content.categoryIdentifier = Constants.notificationIdentifier
        return content
    }

    var daysInactive: Int {
        Settings.daysInactive.value(from: subfeatureSettings)
    }

    var maxInteractions: Int {
        Settings.maxInteractions.value(from: subfeatureSettings)
    }

    // MARK: - Private

    private var subfeatureSettings: [String: Any]? {
        guard let settings = privacyConfigurationManager.privacyConfig.settings(for: Constants.subfeature),
              let jsonData = settings.data(using: .utf8) else { return nil }

        do {
            return try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        } catch {
            Logger.pushNotification.error("Inactivity notification subfeature settings parsing failed with \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func isFeatureEnabled() -> Bool {
        return featureFlagger.isFeatureOn(.inactivityNotification)
    }
    
    private func cancelPendingNotifications() {
        userNotificationCenter.removePendingNotificationRequests(withIdentifiers: [Constants.notificationIdentifier])
    }
    
    private func buildUNNotificationRequest() -> UNNotificationRequest {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: .days(daysInactive), repeats: false)
        return UNNotificationRequest(
            identifier: Constants.notificationIdentifier,
            content: Self.makeUNNotificationContent(with: daysInactive),
            trigger: trigger
        )
    }
}

extension Logger {
    static var pushNotification = { Logger(subsystem: "Push Notification", category: "") }()
}
