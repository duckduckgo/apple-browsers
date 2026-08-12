//
//  PIRAvailability.swift
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

import DataBrokerProtection_iOS

/// Shared by `SettingsViewModel` and `SubscriptionFlowViewModel`. Matches the DBP-destination routing used
/// throughout Settings and the purchase flow (`SubscriptionSettingsView.pirDestination`,
/// `SubscriptionFlowView.pirDestination`, etc.)
enum PIRAvailability {
    static func isAvailable(isPIREnabled: Bool, provider: DBPIOSInterface.DataBrokerProtectionViewControllerProvider?) -> Bool {
        guard isPIREnabled, provider != nil else { return false }
        return true
    }
}
