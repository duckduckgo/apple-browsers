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

protocol NotificationServiceManaging: UNUserNotificationCenterDelegate {}

final class NotificationServiceManager: NSObject, NotificationServiceManaging {
    
    private let mainCoordinator: MainCoordinator
    
    init(mainCoordinator: MainCoordinator) {
        self.mainCoordinator = mainCoordinator
        super.init()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(.banner)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        
        let id = response.notification.request.identifier
        switch id {
        case InactivityNotificationSchedulerService.notificationIdentifier:
            let daysInactive = response.notification.request.content.userInfo[InactivityNotificationSchedulerService.daysInactiveSettingKey] as? Double ?? InactivityNotificationSchedulerService.defaultDaysInactive
            Pixel.fire(pixel: .provisionalPushNotificationTapped, withAdditionalParameters: [InactivityNotificationSchedulerService.daysInactiveSettingKey: String(daysInactive)])
            completionHandler()
            return

        case let raw where NetworkProtectionNotificationIdentifier(rawValue: raw) != nil:
            Task { @MainActor [weak self] in
                self?.mainCoordinator.presentNetworkProtectionStatusSettingsModal()
                completionHandler()
            }
            return

        default:
            completionHandler()
        }
    }
    
}
