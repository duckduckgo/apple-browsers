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
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return .banner
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        
        let id = response.notification.request.identifier
        switch id {
        case InactivityNotificationSchedulerService.Constants.notificationIdentifier:
            handleInactivityNotification(for: response)
        case let raw where NetworkProtectionNotificationIdentifier(rawValue: raw) != nil:
            await handleVPNNotification()
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
    func handleVPNNotification() {
        mainCoordinator.presentNetworkProtectionStatusSettingsModal()
    }
}
