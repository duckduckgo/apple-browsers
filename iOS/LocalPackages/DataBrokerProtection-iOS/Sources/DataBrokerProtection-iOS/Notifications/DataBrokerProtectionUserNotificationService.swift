//
//  DataBrokerProtectionUserNotificationService.swift
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

import Foundation
import UserNotifications
import Common
import os.log
import DataBrokerProtectionCore

public protocol DataBrokerProtectionUserNotificationService {
    func requestNotificationPermission()
    func sendFirstScanCompletedNotification()
    func sendFirstRemovedNotificationIfPossible()
    func sendAllInfoRemovedNotificationIfPossible()
    func scheduleCheckInNotificationIfPossible()
    func sendGoToMarketFirstScanNotificationIfPossible() async
    func resetFirstScanCompletedNotificationState()
    
    func resetAllNotificationStatesForDebug()
}

public class DefaultDataBrokerProtectionUserNotificationService: DataBrokerProtectionUserNotificationService {

    private let userDefaults: UserDefaults
    private let userNotificationCenter: UNUserNotificationCenter
    private let authenticationManager: DataBrokerProtectionAuthenticationManaging
    private let pixelHandler: EventMapping<DataBrokerProtectionNotificationPixel>

    public init(
        userDefaults: UserDefaults = .dbp,
        userNotificationCenter: UNUserNotificationCenter = .current(),
        authenticationManager: DataBrokerProtectionAuthenticationManaging,
        pixelHandler: EventMapping<DataBrokerProtectionNotificationPixel>
    ) {
        self.userDefaults = userDefaults
        self.userNotificationCenter = userNotificationCenter
        self.authenticationManager = authenticationManager
        self.pixelHandler = pixelHandler
    }

    // MARK: - Public Methods

    public func requestNotificationPermission() {
        requestProvisionalAuthorizationIfNeeded()
    }

    public func sendFirstScanCompletedNotification() {
        if userDefaults[.didSendFirstScanCompletedNotification] != true {
            Task {
                if await !authenticationManager.isUserAuthenticated {
                    sendNotification(.firstFreemiumScanComplete)
                    pixelHandler.fire(.notificationSentFirstFreemiumScanComplete)
                } else {
                    sendNotification(.firstScanComplete)
                    pixelHandler.fire(.notificationSentFirstScanComplete)
                }
                userDefaults[.didSendFirstScanCompletedNotification] = true
            }
        }
    }

    public func sendFirstRemovedNotificationIfPossible() {
        if userDefaults[.didSendFirstRemovedNotification] != true {
            sendNotification(.firstProfileRemoved)
            userDefaults[.didSendFirstRemovedNotification] = true
            pixelHandler.fire(.notificationSentFirstRemoval)
        }
    }

    public func sendAllInfoRemovedNotificationIfPossible() {
        if userDefaults[.didSendAllInfoRemovedNotification] != true {
            sendNotification(.allInfoRemoved)
            userDefaults[.didSendAllInfoRemovedNotification] = true
            pixelHandler.fire(.notificationSentAllRecordsRemoved)
        }
    }

    public func scheduleCheckInNotificationIfPossible() {
        if userDefaults[.didSendCheckedInNotification] != true {
            sendNotification(.oneWeekCheckIn, afterDays: 7)
            userDefaults[.didSendCheckedInNotification] = true
            pixelHandler.fire(.notificationScheduled1WeekCheckIn)
        }
    }

    public func resetFirstScanCompletedNotificationState() {
        userDefaults[.didSendFirstScanCompletedNotification] = false
    }

    public func resetAllNotificationStatesForDebug() {
        UserDefaults.Key.allCases.forEach { key in
            userDefaults.removeObject(forKey: key.rawValue)
        }
    }

    public func sendGoToMarketFirstScanNotificationIfPossible() async {
        if userDefaults[.didSendGoToMarketFirstScanNotification] != true {
            sendNotification(.goToMarketFirstScan)
            userDefaults[.didSendGoToMarketFirstScanNotification] = true
            pixelHandler.fire(.notificationSentGoToMarketFirstScan)
        }
    }

    // MARK: - Private Methods

    private func requestProvisionalAuthorizationIfNeeded() {
        userNotificationCenter.getNotificationSettings { [weak self] settings in
            if settings.authorizationStatus == .notDetermined {
                self?.userNotificationCenter.requestAuthorization(options: [.provisional]) { _, _ in }
            }
        }
    }

    private func sendNotification(_ notification: UserNotification, afterDays days: Int? = nil) {
        requestProvisionalAuthorizationIfNeeded()

        let notificationContent = UNMutableNotificationContent()
        notificationContent.title = notification.title
        notificationContent.body = notification.message

        let request: UNNotificationRequest

        if let days = days {
            let calendar = Calendar.current
            guard let date = calendar.date(byAdding: .day, value: days, to: Date()) else {
                Logger.dataBrokerProtection.error("PIR notification scheduled for an invalid date")
                return
            }
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            request = UNNotificationRequest(identifier: notification.identifier, content: notificationContent, trigger: trigger)
        } else {
            request = UNNotificationRequest(identifier: notification.identifier, content: notificationContent, trigger: nil)
        }

        userNotificationCenter.add(request) { error in
            if error == nil {
                if days != nil {
                    Logger.dataBrokerProtection.log("PIR user notification scheduled")
                } else {
                    Logger.dataBrokerProtection.log("PIR user notification sent")
                }
            }
        }
    }
}

// MARK: - UserDefaults Keys

private extension UserDefaults {
    enum Key: String, CaseIterable {
        case didSendFirstScanCompletedNotification
        case didSendFirstRemovedNotification
        case didSendAllInfoRemovedNotification
        case didSendCheckedInNotification
        case didSendGoToMarketFirstScanNotification
    }

    subscript<T>(key: Key) -> T? where T: Any {
        get {
            return value(forKey: key.rawValue) as? T
        }
        set {
            set(newValue, forKey: key.rawValue)
        }
    }
}

// MARK: - User Notification Content

private enum UserNotification {
    case firstFreemiumScanComplete
    case firstScanComplete
    case firstProfileRemoved
    case allInfoRemoved
    case oneWeekCheckIn
    case goToMarketFirstScan

    var title: String {
        switch self {
        case .firstFreemiumScanComplete:
            return "Free Personal Information Scan"
        case .firstScanComplete:
            return "Scan complete!"
        case .firstProfileRemoved:
            return "A record of your info was removed!"
        case .allInfoRemoved:
            return "Personal info removed!"
        case .oneWeekCheckIn:
            return "We're making progress!"
        case .goToMarketFirstScan:
            return "Personal Information Removal"
        }
    }

    var message: String {
        switch self {
        case .firstFreemiumScanComplete:
            return "Your free personal info scan is now complete. Check out the results..."
        case .firstScanComplete:
            return "DuckDuckGo has started the process to remove records matching your personal info online. See what we found..."
        case .firstProfileRemoved:
            return "That's one less creepy site storing and selling your personal info online. Check progress..."
        case .allInfoRemoved:
            return "See all the records matching your personal info that DuckDuckGo found and removed from the web..."
        case .oneWeekCheckIn:
            return "See the records matching your personal info that DuckDuckGo found and removed from the web so far..."
        case .goToMarketFirstScan:
            return "Personal Information Removal is now available on iOS! Start your first scan now."
        }
    }

    var identifier: String {
        switch self {
        case .firstFreemiumScanComplete:
            return DataBrokerProtectionNotificationIdentifier.firstFreemiumScanComplete.rawValue
        case .firstScanComplete:
            return DataBrokerProtectionNotificationIdentifier.firstScanComplete.rawValue
        case .firstProfileRemoved:
            return DataBrokerProtectionNotificationIdentifier.firstProfileRemoved.rawValue
        case .allInfoRemoved:
            return DataBrokerProtectionNotificationIdentifier.allInfoRemoved.rawValue
        case .oneWeekCheckIn:
            return DataBrokerProtectionNotificationIdentifier.oneWeekCheckIn.rawValue
        case .goToMarketFirstScan:
            return DataBrokerProtectionNotificationIdentifier.goToMarketFirstScan.rawValue
        }
    }
}
