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

enum SubscriptionPixel: PixelKitEvent {
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
        }
    }

    private struct SubscriptionPixelsDefaults {
        static let policyCacheKey = "policycache"
        static let sourceKey = "source"
        static let platformKey = "platform"
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
                .subscriptionKeychainManagerFailedToWriteDataFromBacklog:
            return [.pixelSource]
        }
    }
}
