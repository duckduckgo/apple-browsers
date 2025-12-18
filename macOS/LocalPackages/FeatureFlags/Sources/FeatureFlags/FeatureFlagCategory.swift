//
//  FeatureFlagCategory.swift
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
import BrowserServicesKit

public enum FeatureFlagCategory: String, CaseIterable, Comparable {
    case duckAI = "Duck.ai"
    case dbp = "Personal Information Removal"
    case osSupportWarnings = "OS Support Warnings"
    case other = "Other"
    case subscription = "Subscription"
    case popupBlocking = "Popup Blocking"
    case sync = "Sync"
    case updates = "Updates"
    case vpn = "VPN"
    case webNotifications = "Web Notifications"

    public static func < (lhs: FeatureFlagCategory, rhs: FeatureFlagCategory) -> Bool {
        guard lhs != rhs else {
            return false
        }
        if rhs == .other {
            return true
        }
        return lhs.rawValue.localizedCaseInsensitiveCompare(rhs.rawValue) == .orderedAscending
    }
}

public protocol FeatureFlagCategorization {
    var category: FeatureFlagCategory { get }
}

extension FeatureFlag: FeatureFlagCategorization {
    public var category: FeatureFlagCategory {
        switch self {
        case .aiChatSidebar,
                .aiChatPageContext,
                .duckAISearchParameter,
                .aiChatImprovements,
                .aiChatKeepSession,
                .aiChatDataClearing,
                .aiChatOmnibarToggle,
                .aiChatOmnibarCluster,
                .standaloneMigration:
            return .duckAI
        case .osSupportForceUnsupportedMessage,
                .osSupportForceWillSoonDropSupportMessage,
                .willSoonDropBigSurSupport:
            return .osSupportWarnings
        case .syncSeamlessAccountSwitching,
                .syncSetupBarcodeIsUrlBased,
                .canScanUrlBasedSyncSetupBarcodes,
                .exchangeKeysToSyncWithAnotherDevice:
            return .sync
        case .updatesWontAutomaticallyRestartApp,
                .autoUpdateInDEBUG,
                .appStoreUpdateFlow:
            return .updates
        case .networkProtectionAppStoreSysex,
                .networkProtectionAppStoreSysexMessage,
                .winBackOffer:
            return .vpn
        case .dbpEmailConfirmationDecoupling,
                .dbpRemoteBrokerDelivery:
            return .dbp
        case .paidAIChat,
                .supportsAlternateStripePaymentFlow,
                .vpnConnectionWidePixelMeasurement,
                .blackFridayCampaign,
                .tierMessagingEnabled,
                .allowProTierPurchase:
            return .subscription
        case .popupBlocking,
                .extendedUserInitiatedPopupTimeout,
                .suppressEmptyPopUpsOnApproval,
                .allowPopupsForCurrentPage,
                .popupPermissionButtonPersistence:
            return .popupBlocking
        case .webNotifications:
            return .webNotifications
        default:
            return .other
        }
    }
}
