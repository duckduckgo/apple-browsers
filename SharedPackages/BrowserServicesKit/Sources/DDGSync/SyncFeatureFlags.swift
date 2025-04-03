//
//  SyncFeatureFlags.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import Foundation

/**
 * This enum describes available Sync features.
 */
public struct SyncFeatureFlags: OptionSet {
    public let rawValue: Int
    public private(set) var unavailableReason: PrivacyConfigurationFeatureDisabledReason?

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    // MARK: - Individual Flags

    /// Sync UI is visible
    public static let userInterface = SyncFeatureFlags(rawValue: 1 << 0)

    /// Data syncing is available
    public static let dataSyncing = SyncFeatureFlags(rawValue: 1 << 1)

    /// Logging in to existing accounts is available (connect flows + account recovery)
    public static let accountLogin = SyncFeatureFlags(rawValue: 1 << 2)

    /// Creating new accounts is available
    public static let accountCreation = SyncFeatureFlags(rawValue: 1 << 4)

    // MARK: - Helper Flags

    public static let connectFlows = SyncFeatureFlags.accountLogin
    public static let accountRecovery = SyncFeatureFlags.accountLogin

    // MARK: - Support levels

    /// Used when all feature flags are disabled
    public static let unavailable: SyncFeatureFlags = []

    /// Level 0 feature flag as defined in Privacy Configuration
    public static let level0ShowSync: SyncFeatureFlags = [.userInterface]
    /// Level 1 feature flag as defined in Privacy Configuration
    public static let level1AllowDataSyncing: SyncFeatureFlags = [.userInterface, .dataSyncing]
    /// Level 2 feature flag as defined in Privacy Configuration
    public static let level2AllowSetupFlows: SyncFeatureFlags = [.userInterface, .dataSyncing, .accountLogin]
    /// Level 3 feature flag as defined in Privacy Configuration
    public static let level3AllowCreateAccount: SyncFeatureFlags = [.userInterface, .dataSyncing, .accountLogin, .accountCreation]

    /// Alias for the state when all features are available
    public static let all: SyncFeatureFlags = .level3AllowCreateAccount

    // MARK: -

    init(privacyConfig: PrivacyConfiguration) {
        var disabledSubfeature: SyncSubfeature?
        let syncState = privacyConfig.stateFor(featureKey: .sync)
        switch syncState {

        case .enabled:
            if !privacyConfig.isSubfeatureEnabled(SyncSubfeature.level0ShowSync) {
                disabledSubfeature = .level0ShowSync
                self = .unavailable
            } else if !privacyConfig.isSubfeatureEnabled(SyncSubfeature.level1AllowDataSyncing) {
                disabledSubfeature = .level1AllowDataSyncing
                self = .level0ShowSync
            } else if !privacyConfig.isSubfeatureEnabled(SyncSubfeature.level2AllowSetupFlows) {
                disabledSubfeature = .level2AllowSetupFlows
                self = .level1AllowDataSyncing
            } else if !privacyConfig.isSubfeatureEnabled(SyncSubfeature.level3AllowCreateAccount) {
                disabledSubfeature = SyncSubfeature.level3AllowCreateAccount
                self = .level2AllowSetupFlows
            } else {
                self = .level3AllowCreateAccount
            }
        case .disabled(let reason):
            unavailableReason = reason
            self = .unavailable
        }

        if let disabledSubfeature, case .disabled(let reason) = privacyConfig.stateFor(disabledSubfeature) {
            unavailableReason = reason
        }
    }
}
