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
                    sourceObject: Any?)
    case vpnFeatureDisabled(isSubscriptionActive: Bool?,
                     isAuthV2Enabled: Bool,
                     sourceObject: Any?)
    case signedIn(isSubscriptionActive: Bool?,
                  isAuthV2Enabled: Bool,
                  sourceObject: Any?)
    case signedOut(isSubscriptionActive: Bool?,
                   isAuthV2Enabled: Bool,
                   sourceObject: Any?)

    public var namePrefix: String {
#if os(macOS)
        return "m_mac_vpn_subs_notification_"
#elseif os(iOS)
        return "m_vpn_subs_notification_"
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

    public var error: (any Error)? { nil }

    public var parameters: [String: String]? {
        switch self {
        case .signedIn(let isSubscriptionActive, let isAuthV2, let sourceObject),
                .signedOut(let isSubscriptionActive, let isAuthV2, let sourceObject),
                .vpnFeatureEnabled(let isSubscriptionActive, let isAuthV2, let sourceObject),
                .vpnFeatureDisabled(let isSubscriptionActive, let isAuthV2, let sourceObject):

            let isSubscriptionActiveString = {
                guard let isSubscriptionActive else {
                    return "no_subscription"
                }

                return String(isSubscriptionActive)
            }()

            return [
                "isSubscriptionActive": isSubscriptionActiveString,
                "authVersion": isAuthV2 ? "v2" : "v1",
                "notificationObjectClass": Self.sourceClass(from: sourceObject)
            ]
        }
    }

    static func sourceClass(from sourceObject: Any?) -> String {
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
