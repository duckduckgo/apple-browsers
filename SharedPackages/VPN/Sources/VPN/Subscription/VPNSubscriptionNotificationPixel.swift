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

public enum VPNSubscriptionNotificationPixel: PixelKitEventV2, PixelKitEventWithCustomPrefix {
    case vpnFeatureEnabled(isSubscriptionActive: Bool?,
                    isAuthV2Enabled: Bool,
                    source: Source)
    case vpnFeatureDisabled(isSubscriptionActive: Bool?,
                     isAuthV2Enabled: Bool,
                     source: Source)
    case signedIn(isSubscriptionActive: Bool?,
                  isAuthV2Enabled: Bool,
                  source: Source)
    case signedOut(isSubscriptionActive: Bool?,
                   isAuthV2Enabled: Bool,
                   source: Source)

    public enum Source {
        case clientCheck(sourceObject: Any?)
        case notification(sourceObject: Any?)
    }

    public var namePrefix: String {
#if os(macOS)
        "m_mac_vpn_subs_notification_"
#elseif os(iOS)
        "m_vpn_subs_notification_"
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
        case .signedIn(let isSubscriptionActive, let isAuthV2, let source),
                .signedOut(let isSubscriptionActive, let isAuthV2, let source),
                .vpnFeatureEnabled(let isSubscriptionActive, let isAuthV2, let source),
                .vpnFeatureDisabled(let isSubscriptionActive, let isAuthV2, let source):

            let isSubscriptionActiveString = {
                guard let isSubscriptionActive else {
                    return "no_subscription"
                }

                return String(isSubscriptionActive)
            }()

            return [
                "isSubscriptionActive": isSubscriptionActiveString,
                "authVersion": isAuthV2 ? "v2" : "v1",
                "trigger": Self.trigger(from: source),
                "notificationObjectClass": Self.sourceClass(from: source)
            ]
        }
    }

    public var error: (any Error)? {
        nil
    }

    static func trigger(from source: Source) -> String {
        switch source {
        case .clientCheck:
            return "clientCheck"
        case .notification:
            return "notification"
        }
    }

    static func sourceClass(from source: Source) -> String {
        switch source {
        case .clientCheck(let sourceObject),
                .notification(let sourceObject):
            guard let sourceObject else {
                return "nil"
            }

            return String(describing: sourceObject.self)
        }
    }
}
