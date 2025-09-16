//
//  VPNSubscriptionClientCheckPixel.swift
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

public enum VPNSubscriptionClientCheckPixel: PixelKitEvent, PixelKitEventWithCustomPrefix {
    case vpnFeatureEnabled(isSubscriptionActive: Bool?,
                    isAuthV2Enabled: Bool,
                    trigger: Trigger)
    case vpnFeatureDisabled(isSubscriptionActive: Bool?,
                     isAuthV2Enabled: Bool,
                     trigger: Trigger)
    case failed(isSubscriptionActive: Bool?,
                isAuthV2Enabled: Bool,
                trigger: Trigger,
                error: Error)

    public enum Trigger {
        case appStartup
#if os(macOS)
        case deviceWake
#elseif os(iOS)
        case appForegrounded
#endif
    }

    public var namePrefix: String {
        let trigger: Trigger = {
            switch self {
            case .vpnFeatureEnabled(_, _, let trigger),
                    .vpnFeatureDisabled(_, _, let trigger),
                    .failed(_, _, let trigger, _):
                return trigger
            }
        }()

#if os(macOS)
        switch trigger {
        case .appStartup:
            return "m_mac_vpn_subs_client_check_"
        case .deviceWake:
            return "m_mac_vpn_subs_client_check_on_wake_"
        }
#elseif os(iOS)
        switch trigger {
        case .appStartup:
            return "m_vpn_subs_client_check_"
        case .appForegrounded:
            return "m_vpn_subs_client_check_on_foreground_"
        }
#endif
    }

    public var name: String {
        switch self {
        case .vpnFeatureEnabled:
            return "vpn_feature_enabled"
        case .vpnFeatureDisabled:
            return "vpn_feature_disabled"
        case .failed:
            return "failed"
        }
    }

    public var parameters: [String: String]? {
        switch self {
        case .vpnFeatureEnabled(let isSubscriptionActive, let isAuthV2, _),
                .vpnFeatureDisabled(let isSubscriptionActive, let isAuthV2, _),
                .failed(let isSubscriptionActive, let isAuthV2, _, _):

            let isSubscriptionActiveString = {
                guard let isSubscriptionActive else {
                    return "no_subscription"
                }

                return String(isSubscriptionActive)
            }()

            return [
                "isSubscriptionActive": isSubscriptionActiveString,
                "authVersion": isAuthV2 ? "v2" : "v1"
            ]
        }
    }

}
