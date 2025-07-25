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
    case osSupportWarnings = "OS Support Warnings"
    case other = "Other"
    case sync = "Sync"
    case updates = "Updates"
    case vpn = "VPN"

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
        case .aiChatGlobalSwitch,
                .aiChatSidebar,
                .aiChatTextSummarization:
            return .duckAI
        case .osSupportForceUnsupportedMessage,
                .osSupportForceWillSoonDropSupportMessage:
            return .osSupportWarnings
        case .syncSeamlessAccountSwitching,
                .syncSetupBarcodeIsUrlBased,
                .canScanUrlBasedSyncSetupBarcodes,
                .exchangeKeysToSyncWithAnotherDevice:
            return .sync
        case .updatesWontAutomaticallyRestartApp,
                .autoUpdateInDEBUG:
            return .updates
        case .networkProtectionAppStoreSysex,
                .networkProtectionAppStoreSysexMessage,
                .networkProtectionRiskyDomainsProtection:
            return .vpn
        default:
            return .other
        }
    }
}
