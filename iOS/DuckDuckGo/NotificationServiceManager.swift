//
//  NotificationServiceManager.swift
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

import VPN
import Subscription
import UIKit
import NotificationCenter
import Core
import DataBrokerProtection_iOS

protocol NotificationServiceManaging: UNUserNotificationCenterDelegate {}

final class NotificationServiceManager: NSObject, NotificationServiceManaging {

    private let mainCoordinator: MainCoordinator

    static let notificationCategories: Set<UNNotificationCategory> = [
        DefaultSubscriptionExpirationReminderScheduler.notificationCategory
    ]

    init(mainCoordinator: MainCoordinator,
         notificationCenter: UNUserNotificationCenterRepresentable = UNUserNotificationCenter.current()) {
        self.mainCoordinator = mainCoordinator
        super.init()
        Self.registerNotificationCategories(on: notificationCenter)
    }

    static func registerNotificationCategories(on notificationCenter: UNUserNotificationCenterRepresentable) {
        notificationCenter.setNotificationCategories(notificationCategories)
    }

    /// https://stackoverflow.com/questions/73750724/how-can-usernotificationcenter-didreceive-cause-a-crash-even-with-nothing-in
    /// TL;DR: The async UNUserNotificationCenterDelegate methods (`willPresent`, `didReceive`) can be invoked off the main thread, leading to occasional crashes during app activation.
    /// Marking this delegate @MainActor ensures they always run on the main thread. This appears to be an iOS bug.
    @MainActor
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .list]
    }

    @MainActor
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {

        let id = response.notification.request.identifier

        if id == DefaultSubscriptionExpirationReminderScheduler.notificationIdentifier {
            handleSubscriptionExpirationReminder(actionIdentifier: response.actionIdentifier)
            return
        }

        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }

        switch id {
        case InactivityNotificationSchedulerService.Constants.notificationIdentifier:
            handleInactivityNotification(for: response)
        case let raw where NetworkProtectionNotificationIdentifier(rawValue: raw) != nil:
            if let identifier = NetworkProtectionNotificationIdentifier(rawValue: raw) {
                handleVPNNotification(identifier: identifier)
            }
        case let raw where DataBrokerProtectionNotificationIdentifier(rawValue: raw) != nil:
            if let identifier = DataBrokerProtectionNotificationIdentifier(rawValue: raw) {
                handleDataBrokerProtectionNotification(identifier: identifier)
            }
        default:
            break
        }
    }
}


// MARK: - Helpers

private extension NotificationServiceManager {
    
    func handleInactivityNotification(for response: UNNotificationResponse) {
        let daysInactiveKey = InactivityNotificationSchedulerService.Constants.daysInactiveSettingKey
        let daysInactive = response.notification.request.content.userInfo[daysInactiveKey] as? Int ?? InactivityNotificationSchedulerService.Constants.defaultDaysInactive
        Pixel.fire(pixel: .inactiveUserProvisionalPushNotificationTapped, withAdditionalParameters: [daysInactiveKey: String(daysInactive)])
    }
    
    @MainActor
    func handleVPNNotification(identifier: NetworkProtectionNotificationIdentifier) {
        let scrollToStrictRouting = identifier == .strictRoutingReminder
        mainCoordinator.presentNetworkProtectionStatusSettingsModal(entryPoint: .notification,
                                                                    scrollToStrictRouting: scrollToStrictRouting)
    }

    @MainActor
    func handleSubscriptionExpirationReminder(actionIdentifier: String) {
        switch actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            Pixel.fire(pixel: .subscriptionExpirationReminderNotificationTapped)
            mainCoordinator.segueToSubscriptionWelcome()
        case UNNotificationDismissActionIdentifier:
            Pixel.fire(pixel: .subscriptionExpirationReminderNotificationDismissed)
        default:
            break
        }
    }

    @MainActor
    func handleDataBrokerProtectionNotification(identifier: DataBrokerProtectionNotificationIdentifier) {
        let pixel: Pixel.Event
        switch identifier {
        case .firstScanComplete:
            pixel = .dbpNotificationOpenedFirstScanComplete
        case .firstFreemiumScanComplete:
            pixel = .dbpNotificationOpenedFirstFreemiumScanComplete
        case .firstProfileRemoved:
            pixel = .dbpNotificationOpenedFirstRemoval
        case .allInfoRemoved:
            pixel = .dbpNotificationOpenedAllRecordsRemoved
        case .oneWeekCheckIn:
            pixel = .dbpNotificationOpened1WeekCheckIn
        case .goToMarketFirstScan:
            pixel = .dbpNotificationOpenedGoToMarketFirstScan
        }
        Pixel.fire(pixel: pixel)

        mainCoordinator.presentDataBrokerProtectionDashboard()
    }
}
