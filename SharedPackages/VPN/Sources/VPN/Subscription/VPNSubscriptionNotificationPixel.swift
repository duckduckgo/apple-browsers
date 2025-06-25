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

public enum VPNSubscriptionNotificationPixel: PixelKitEventV3 {
    case vpnEnabled(isSubscriptionActive: Bool?,
                    isAuthV2Enabled: Bool,
                    sourceObject: Any?)
    case vpnDisabled(isSubscriptionActive: Bool?,
                     isAuthV2Enabled: Bool,
                     sourceObject: Any?)
    case signedIn(isSubscriptionActive: Bool?,
                  isAuthV2Enabled: Bool,
                  sourceObject: Any?)
    case signedOut(isSubscriptionActive: Bool?,
                   isAuthV2Enabled: Bool,
                   sourceObject: Any?)

    public var namePrefix: String {
        "m_vpn_subs_notification_"
    }

    public var name: String {
        switch self {
        case .signedIn:
            return "signed_in"
        case .signedOut:
            return "signed_out"
        case .vpnEnabled:
            return "vpn_enabled"
        case .vpnDisabled:
            return "vpn_disabled"
        }
    }

    public var parameters: [String: String]? {
        switch self {
        case .signedIn(let isSubscriptionActive, let isAuthV2, let sourceObject),
                .signedOut(let isSubscriptionActive, let isAuthV2, let sourceObject),
                .vpnEnabled(let isSubscriptionActive, let isAuthV2, let sourceObject),
                .vpnDisabled(let isSubscriptionActive, let isAuthV2, let sourceObject):
            return [
                "isSubscriptionActive": "\(isSubscriptionActive.map { String($0) } ?? "unknown")",
                "authVersion": isAuthV2 ? "v2" : "v1",
                "notificationObjectClass": Self.sourceClass(from: sourceObject)
            ]
        }
    }

    public var error: (any Error)? {
        nil
    }

    static func sourceClass(from sourceObject: Any?) -> String {
        guard let sourceObject else {
            return "missing"
        }

        switch sourceObject {
        case is DefaultAccountManager:
            return "DefaultAccountManager"
        case is SubscriptionEndpointServiceV2:
            return "SubscriptionEndpointServiceV2"
        case is DefaultSubscriptionManagerV2:
            return "DefaultSubscriptionManagerV2"
        case is SubscriptionAuthV1toV2Bridge:
            return "SubscriptionAuthV1toV2Bridge"
        default:
            return "Unknown - add class!"
        }
    }
}
