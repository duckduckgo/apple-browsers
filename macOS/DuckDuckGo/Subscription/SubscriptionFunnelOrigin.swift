//
//  SubscriptionFunnelOrigin.swift
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

/// Represents the origin point from which the user enters the subscription funnel in the macOS app.
enum SubscriptionFunnelOrigin: String {
    /// User entered the funnel via the App Settings screen.
    case appSettings = "funnel_appsettings_macos"

    /// User entered the funnel via the App More Menu.
    case appMenu = "funnel_appmenu_macos"

    /// User entered the funnel via the Free Scan feature.
    case freeScan = "funnel_freescan_macos"

    // MARK: - Win-Back Offer Origins

    /// User entered via win-back offer launch prompt
    case winBackLaunch = "funnel_applaunch_macos_winback"

    /// User entered via win-back offer in App More Menu
    case winBackMenu = "funnel_appmenu_macos_winback"

    /// User entered via win-back offer in App Settings
    case winBackSettings = "funnel_appsettings_macos_winback"

    /// User entered via win-back offer in New Tab Page
    case winBackNewTabPage = "funnel_newtab_macos_winback"

    /// User entered the funnel via the New Tab Page next steps card.
    case newTabPageNextStepsCard = "funnel_onboarding_macOS__nextstepscard"

    /// User entered the funnel via the subscription promo on the Fire Window home page.
    case fireWindowPromo = "funnel_newtab_macos__firewindowvpn"

    /// User entered the funnel via the VPN toolbar button upsell popover.
    case vpnToolbarUpsell = "funnel_toolbar_macos__subscriptionvpnupsell"

    /// User entered the funnel via the VPN toolbar button popover when their subscription was revoked.
    case vpnToolbarRevoked = "funnel_toolbar_macos__subscriptionvpnrevoked"

    /// User entered the funnel via the VPN menu-bar status item popover when their subscription was revoked.
    case vpnMenuBarRevoked = "funnel_menu_bar_macos__subscriptionvpnrevoked"
}

/// Represents the origin point from which the user enters the subscription restore funnel in the macOS app.
enum SubscriptionRestoreFunnelOrigin: String {
    /// User entered the restore funnel via the App Settings screen.
    case appSettings = "funnel_appsettings_macos"

    /// User entered the restore funnel via the Purchase Offer web page.
    case purchaseOffer = "funnel_purchaseoffer_macos"

    /// User entered the restore funnel during the pre-purchase check.
    case prePurchaseCheck = "funnel_prepurchasecheck_macos"
}
