//
//  VPNSubscriptionNotificationPixel.swift
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

import PixelKit
import Subscription

public enum VPNSubscriptionNotificationPixel: PixelKitEventV2 {
    case vpnEnabled(subscriptionStatus: String, isAuthV2Enabled: Bool, notificationObjectClass: Any?)
    case vpnDisabled(subscriptionStatus: String, isAuthV2Enabled: Bool, notificationObjectClass: Any?)
    case signedIn(subscriptionStatus: String, isAuthV2Enabled: Bool, notificationObjectClass: Any?)
    case signedOut(subscriptionStatus: String, isAuthV2Enabled: Bool, notificationObjectClass: Any?)

    public var name: String {
        switch self {
        case .signedIn:
            return "subs_notification_signed_in"
        case .signedOut:
            return "subs_notification_signed_out"
        case .vpnEnabled:
            return "subs_notification_vpn_enabled"
        case .vpnDisabled:
            return "subs_notification_vpn_disabled"
        }
    }

    public var parameters: [String: String]? {
        switch self {
        case .signedIn(let subscriptionStatus, let isAuthV2, let notificationObjectClass),
                .signedOut(let subscriptionStatus, let isAuthV2, let notificationObjectClass),
                .vpnEnabled(let subscriptionStatus, let isAuthV2, let notificationObjectClass),
                .vpnDisabled(let subscriptionStatus, let isAuthV2, let notificationObjectClass):
            return [
                "status": subscriptionStatus,
                "version": isAuthV2 ? "v2" : "v1",
                "notificationObjectClass": String(describing: type(of: notificationObjectClass))
            ]
        }
    }

    public var error: (any Error)? {
        nil
    }
}
