//
//  VPNSubscriptionStatusPixel.swift
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

public enum VPNSubscriptionStatusPixel: PixelKitEventV2, PixelKitEventWithCustomPrefix {
    case vpnFeatureEnabled(isSubscriptionActive: Bool?,
                    isAuthV2Enabled: Bool,
                    trigger: Trigger)
    case vpnFeatureDisabled(isSubscriptionActive: Bool?,
                     isAuthV2Enabled: Bool,
                     trigger: Trigger)
    case signedIn(isSubscriptionActive: Bool?,
                  isAuthV2Enabled: Bool,
                  trigger: Trigger)
    case signedOut(isSubscriptionActive: Bool?,
                   isAuthV2Enabled: Bool,
                   trigger: Trigger)

    public enum Trigger {
        case clientCheck
#if os(macOS)
        case clientCheckOnWake
#elseif os(iOS)
        case clientForegrounded
#endif
        case notification(sourceObject: Any?)
    }

    public var namePrefix: String {
        let trigger: Trigger = {
            switch self {
            case .vpnFeatureEnabled(_, _, let trigger),
                    .vpnFeatureDisabled(_, _, let trigger),
                    .signedIn(_, _, let trigger),
                    .signedOut(_, _, let trigger):
                return trigger
            }
        }()

#if os(macOS)
        switch trigger {
        case .clientCheck:
            return "m_mac_vpn_subs_client_check_"
        case .clientCheckOnWake:
            return "m_mac_vpn_subs_client_check_on_wake_"
        case .notification:
            return "m_mac_vpn_subs_notification_"
        }
#elseif os(iOS)
        switch trigger {
        case .clientCheck:
            return "m_vpn_subs_client_check_"
        case .clientForegrounded:
            return "m_vpn_subs_client_check_on_foreground_"
        case .notification:
            return "m_vpn_subs_notification_"
        }
#endif
    }

    public var name: String {
        switch self {
        case .signedIn:
            return "signed_in"
        case .signedOut:
            return "signed_out"
        case .vpnFeatureEnabled:
            return "vpn_feature_enabled"
        case .vpnFeatureDisabled:
            return "vpn_feature_disabled"
        }
    }

    public var parameters: [String: String]? {
        switch self {
        case .signedIn(let isSubscriptionActive, let isAuthV2, let trigger),
                .signedOut(let isSubscriptionActive, let isAuthV2, let trigger),
                .vpnFeatureEnabled(let isSubscriptionActive, let isAuthV2, let trigger),
                .vpnFeatureDisabled(let isSubscriptionActive, let isAuthV2, let trigger):

            let isSubscriptionActiveString = {
                guard let isSubscriptionActive else {
                    return "no_subscription"
                }

                return String(isSubscriptionActive)
            }()

            return [
                "isSubscriptionActive": isSubscriptionActiveString,
                "authVersion": isAuthV2 ? "v2" : "v1",
                "notificationObjectClass": Self.sourceClass(from: trigger)
            ]
        }
    }

    public var error: (any Error)? {
        nil
    }

    static func sourceClass(from trigger: Trigger) -> String {
        switch trigger {
        case .clientCheck:
            return "none"
#if os(macOS)
        case .clientCheckOnWake:
            return "none"
#elseif os(iOS)
        case .clientForegrounded:
            return "none"
#endif
        case .notification(let sourceObject):
            guard let sourceObject else {
                return "nil"
            }

            // This is odd, but for `DefaultSubscriptionEndpointServiceV2` we can't get the class name
            // and it's not very clear why, so we're setting it manually.
            switch sourceObject {
            case is DefaultSubscriptionEndpointServiceV2:
                return "DefaultSubscriptionEndpointServiceV2"
            default:
                return String(describing: type(of: sourceObject))
            }
        }
    }
}
