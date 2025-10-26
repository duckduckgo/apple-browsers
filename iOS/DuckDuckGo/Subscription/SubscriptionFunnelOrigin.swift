//
//  SubscriptionFunnelOrigin.swift
//  DuckDuckGo
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

/// Represents the origin point from which the user enters the subscription funnel in the iOS app.
enum SubscriptionFunnelOrigin: String {
    /// User entered the funnel via the onboarding dialog screen.
    case onboarding = "funnel_onboarding_ios"

    /// User entered the funnel via the App Settings screen.
    case appSettings = "funnel_appsettings_ios"

    /// User entered the funnel via the VPN menu item in the New Tab Page app menu.
    case newTabMenu = "funnel_appmenu_ios"

    // MARK: - Win-Back Offer Origins
    
    /// User entered via win-back offer launch prompt
    case winBackLaunch = "funnel_applaunch_ios_winback"
    
    /// User entered via win-back offer in App Settings
    case winBackSettings = "funnel_appsettings_ios_winback"
}

/// Represents the origin point from which the user enters the subscription restore funnel in the iOS app.
enum SubscriptionRestoreFunnelOrigin: String {
    /// User entered the restore funnel via the App Settings screen.
    case appSettings = "funnel_appsettings_ios"

    /// User entered the restore funnel via the Purchase Offer web page.
    case purchaseOffer = "funnel_purchaseoffer_ios"

    /// User entered the restore funnel during the pre-purchase check.
    case prePurchaseCheck = "funnel_prepurchasecheck_ios"
}
