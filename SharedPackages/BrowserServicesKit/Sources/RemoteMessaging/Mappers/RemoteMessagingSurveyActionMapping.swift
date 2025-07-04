//
//  RemoteMessagingSurveyActionMapping.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

public enum RemoteMessagingSurveyActionParameter: String, CaseIterable {
    case appVersion = "ddgv"
    case atb = "atb"
    case atbVariant = "var"
    case daysInstalled = "delta"
    case hardwareModel = "mo"
    case lastSearchState = "last_search_state"
    case locale = "locale"
    case osVersion = "osv"
    case privacyProStatus = "ppro_status"
    case privacyProPlatform = "ppro_platform"
    case privacyProBilling = "ppro_billing"
    case privacyProDaysSincePurchase = "ppro_days_since_purchase"
    case privacyProDaysUntilExpiry = "ppro_days_until_exp"
    case vpnFirstUsed = "vpn_first_used"
    case vpnLastUsed = "vpn_last_used"
}

public protocol RemoteMessagingSurveyActionMapping {

    func add(parameters: [RemoteMessagingSurveyActionParameter], to url: URL) -> URL

}
