//
//  UserText+VPNNotifications.swift
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

final class UserText {

    // MARK: - Connection Failure

    static let vpnConnectionFailureNotificationTitle = NSLocalizedString("vpn.failure.notification.title", value: "DuckDuckGo VPN failed to connect", comment: "The title of the notification shown when DuckDuckGo VPN fails to reconnect")
    static let vpnConnectionFailureNotificationSubtitle = NSLocalizedString("vpn.failure.notification.subtitle", value: "Unable to connect at this time. Please try again later.", comment: "The subtitle of the notification shown when DuckDuckGo VPN fails to reconnect")

    // MARK: - Connection Interrupted

    static let vpnConnectionInterruptedNotificationSubtitle = NSLocalizedString("vpn.interrupted.notification.subtitle", value: "Attempting to reconnect now...", comment: "The subtitle of the notification shown when DuckDuckGo VPN's connection is interrupted")
    static let vpnConnectionInterruptedNotificationTitle = NSLocalizedString("vpn.interrupted.notification.title", value: "DuckDuckGo VPN was interrupted", comment: "The title of the notification shown when DuckDuckGo VPN's connection is interrupted")

    // MARK: - Connection Success

    static let vpnConnectionSuccessNotificationSubtitle = NSLocalizedString("vpn.success.notification.subtitle", value: "Your location and online activity are protected.", comment: "The subtitle of the notification shown when the VPN reconnects successfully")

    static func vpnConnectionSuccessNotificationSubtitle(serverLocation: String) -> String {
        let localized = NSLocalizedString(
            "vpn.success.notification.subtitle.including.serverLocation",
            value: "Routing device traffic through %@.",
            comment: "The body of the notification shown when DuckDuckGo VPN connects successfully with the city + state/country as formatted parameter"
        )
        return String(format: localized, serverLocation)
    }

    static let vpnConnectionSuccessNotificationTitle = NSLocalizedString("vpn.success.notification.title", value: "DuckDuckGo VPN is ON", comment: "The title of the notification shown when DuckDuckGo VPN connects successfully")

    // MARK: - Entitlement Expired

    static let vpnEntitlementExpiredNotificationTitle = NSLocalizedString("vpn.entitlement.expired.notification.title", value: "VPN disconnected", comment: "The title of the notification when Privacy Pro subscription expired")
    static let vpnEntitlementExpiredNotificationBody = NSLocalizedString("vpn.entitlement.expired.notification.body", value: "Subscribe to Privacy Pro to reconnect DuckDuckGo VPN.", comment: "The body of the notification when Privacy Pro subscription expired")

    // MARK: - Connection Superseded

    static let vpnSupersededReconnectActionTitle = NSLocalizedString("vpn.superseded.action.reconnect.title", value: "Reconnect", comment: "The title of the `Reconnect` notification action button shown when VPN connection is replaced by another app VPN connection taking over")
    static let vpnSupersededNotificationTitle = NSLocalizedString("vpn.superseded.notification.title", value: "DuckDuckGo VPN disconnected", comment: "The title of the notification shown when VPN connection is replaced by another app VPN connection taking over")
    static let vpnSupersededNotificationSubtitle = NSLocalizedString("vpn.superseded.notification.subtitle", value: "Another VPN app on your Mac may have disabled it.", comment: "The subtitle of the notification shown when VPN connection is replaced by another app VPN connection taking over")
}
