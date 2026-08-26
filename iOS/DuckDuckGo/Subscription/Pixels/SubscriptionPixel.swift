//
//  SubscriptionPixel.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import PixelKit
import Networking
import Subscription

enum SubscriptionPixel: PixelKit.Event {
    /// Frozen: these names ship without a platform marker.
    var platformSuffixPolicy: PixelKitPlatformSuffixPolicy { .legacyOmitted }

    // Subscription
    case subscriptionActive
    // Auth
    case subscriptionInvalidRefreshTokenDetected(SubscriptionPixelHandler.Source)
    case subscriptionInvalidRefreshTokenSignedOut
    case subscriptionInvalidRefreshTokenRecovered
    case subscriptionAuthV2GetTokensError(AuthTokensCachePolicy, SubscriptionPixelHandler.Source, Error)
    // Pending Transaction
    case subscriptionPurchaseSuccessAfterPendingTransaction(SubscriptionPixelHandler.Source)
    case subscriptionPendingTransactionApproved(SubscriptionPixelHandler.Source)
    // KeychainManager
    case subscriptionKeychainManagerDataAddedToTheBacklog(SubscriptionPixelHandler.Source)
    case subscriptionKeychainManagerDeallocatedWithBacklog(SubscriptionPixelHandler.Source)
    case subscriptionKeychainManagerDataWroteFromBacklog(SubscriptionPixelHandler.Source)
    case subscriptionKeychainManagerFailedToWriteDataFromBacklog(SubscriptionPixelHandler.Source)
    // VPN Subscription Funnel Entry Points
    case subscriptionVPNToolbarImpression(isSubscriptionActive: Bool?)
    case subscriptionVPNToolbarClick(isSubscriptionActive: Bool?)
    case subscriptionVPNAddressBarImpression(isSubscriptionActive: Bool?)
    case subscriptionVPNAddressBarClick(isSubscriptionActive: Bool?)
    case subscriptionVPNWidgetClick
    case subscriptionVPNShortcutClick
    case subscriptionVPNNotificationClick

    var name: String {
        switch self {
        case .subscriptionActive: return "m_privacy-pro_app_subscription_active"
            // Auth
        case .subscriptionInvalidRefreshTokenDetected: return "m_privacy-pro_auth_invalid_refresh_token_detected"
        case .subscriptionInvalidRefreshTokenSignedOut: return "m_privacy-pro_auth_invalid_refresh_token_signed_out"
        case .subscriptionInvalidRefreshTokenRecovered: return "m_privacy-pro_auth_invalid_refresh_token_recovered"
        case .subscriptionAuthV2GetTokensError: return "m_privacy-pro_auth_v2_get_tokens_error"
        case .subscriptionPurchaseSuccessAfterPendingTransaction: return "m_privacy-pro_purchase_success_after_pending_transaction"
        case .subscriptionPendingTransactionApproved: return "m_privacy-pro_app_subscription-purchase_pending_transaction_approved"
            // KeychainManager
        case .subscriptionKeychainManagerDataAddedToTheBacklog: return "m_privacy-pro_keychain_manager_data_added_to_backlog"
        case .subscriptionKeychainManagerDeallocatedWithBacklog: return "m_privacy-pro_keychain_manager_deallocated_with_backlog"
        case .subscriptionKeychainManagerDataWroteFromBacklog: return "m_privacy-pro_keychain_manager_data_wrote_from_backlog"
        case .subscriptionKeychainManagerFailedToWriteDataFromBacklog: return "m_privacy-pro_keychain_manager_failed_to_write_data_from_backlog"
            // VPN Subscription Funnel Entry Points
        case .subscriptionVPNToolbarImpression: return "subscription_vpn_toolbar_impression"
        case .subscriptionVPNToolbarClick: return "subscription_vpn_toolbar_click"
        case .subscriptionVPNAddressBarImpression: return "subscription_vpn_address-bar_impression"
        case .subscriptionVPNAddressBarClick: return "subscription_vpn_address-bar_click"
        case .subscriptionVPNWidgetClick: return "subscription_vpn_widget_click"
        case .subscriptionVPNShortcutClick: return "subscription_vpn_shortcut_click"
        case .subscriptionVPNNotificationClick: return "subscription_vpn_notification_click"
        }
    }

    private struct SubscriptionPixelsDefaults {
        static let policyCacheKey = "policycache"
        static let sourceKey = "source"
        static let platformKey = "platform"
        static let vpnSubscriptionActiveKey = "vpnSubscriptionActive"
    }

    private static func vpnSubscriptionActiveValue(_ isSubscriptionActive: Bool?) -> String {
        guard let isSubscriptionActive else {
            return "no_subscription"
        }
        return String(isSubscriptionActive)
    }

    var parameters: [String: String]? {
        switch self {
        case .subscriptionInvalidRefreshTokenDetected(let source),
                .subscriptionPurchaseSuccessAfterPendingTransaction(let source),
                .subscriptionPendingTransactionApproved(let source),
                .subscriptionKeychainManagerDataAddedToTheBacklog(let source),
                .subscriptionKeychainManagerDeallocatedWithBacklog(let source),
                .subscriptionKeychainManagerDataWroteFromBacklog(let source),
                .subscriptionKeychainManagerFailedToWriteDataFromBacklog(let source):
            return [SubscriptionPixelsDefaults.sourceKey: source.rawValue]
        case .subscriptionAuthV2GetTokensError(let policy, let source, _):
            return [SubscriptionPixelsDefaults.policyCacheKey: policy.description,
                    SubscriptionPixelsDefaults.sourceKey: source.rawValue]
        case .subscriptionVPNToolbarImpression(let isSubscriptionActive),
                .subscriptionVPNToolbarClick(let isSubscriptionActive),
                .subscriptionVPNAddressBarImpression(let isSubscriptionActive),
                .subscriptionVPNAddressBarClick(let isSubscriptionActive):
            return [SubscriptionPixelsDefaults.vpnSubscriptionActiveKey: Self.vpnSubscriptionActiveValue(isSubscriptionActive)]
        default:
            return nil
        }
    }

    var standardParameters: [PixelKitStandardParameter]? {
        switch self {
        case .subscriptionActive,
                .subscriptionInvalidRefreshTokenDetected,
                .subscriptionInvalidRefreshTokenSignedOut,
                .subscriptionInvalidRefreshTokenRecovered,
                .subscriptionAuthV2GetTokensError,
                .subscriptionPurchaseSuccessAfterPendingTransaction,
                .subscriptionPendingTransactionApproved,
                .subscriptionKeychainManagerDataAddedToTheBacklog,
                .subscriptionKeychainManagerDeallocatedWithBacklog,
                .subscriptionKeychainManagerDataWroteFromBacklog,
                .subscriptionKeychainManagerFailedToWriteDataFromBacklog,
                .subscriptionVPNToolbarImpression,
                .subscriptionVPNToolbarClick,
                .subscriptionVPNAddressBarImpression,
                .subscriptionVPNAddressBarClick,
                .subscriptionVPNWidgetClick,
                .subscriptionVPNShortcutClick,
                .subscriptionVPNNotificationClick:
            return [.pixelSource]
        }
    }
}

// A separate definition because it sends the platform and form-factor marker and the subscription
// pixels above do not, so the two need different `platformSuffixPolicy` values. New subscription
// pixels belong here, or in a type of their own on the default `.standard` policy, rather than in
// the marker-less enum above.
enum SubscriptionAutomaticSignOutPixel: PixelKit.Event {
    /// This pixel signature is non-standard and not aligned to the current PixelKit defaults. This policy freezes the signature to a legacy, and incorrect, suffix ordering.
    var platformSuffixPolicy: PixelKitPlatformSuffixPolicy { .legacyBeforeFrequencySuffix }

    case automaticSignOut(SubscriptionAutomaticSignOutPixelData, SubscriptionPixelHandler.Source, Error)

    private static let sourceKey = "source"

    var namePrefix: PixelKitNamePrefix { .none }

    var name: String {
        switch self {
        case .automaticSignOut: return "m_privacy-pro_auth_account_automatically_signed_out"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .automaticSignOut(let data, let source, _):
            var parameters = data.parameters
            parameters[Self.sourceKey] = source.rawValue
            return parameters
        }
    }

    var standardParameters: [PixelKitStandardParameter]? {
        switch self {
        case .automaticSignOut: return [.pixelSource]
        }
    }
}
