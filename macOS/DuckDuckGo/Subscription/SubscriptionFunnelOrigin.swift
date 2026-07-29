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
    /// https://app.asana.com/1/137249556945/project/1207260194172075/task/1210468753388392
    case appSettings = "funnel_appsettings_macos"

    /// User entered the funnel via the App More Menu.
    /// https://app.asana.com/1/137249556945/project/1207260194172075/task/1210468753388401
    case appMenu = "funnel_appmenu_macos"

    /// User entered the funnel via the Free Scan feature.
    /// https://app.asana.com/1/137249556945/project/1207260194172075/task/1210468753388402
    case freeScan = "funnel_freescan_macos"

    // MARK: - Win-Back Offer Origins

    /// User entered via win-back offer launch prompt
    /// https://app.asana.com/1/137249556945/project/1207260194172075/task/1213998044482808
    case winBackLaunch = "funnel_applaunch_macos_winback"

    /// User entered via win-back offer in App More Menu
    /// https://app.asana.com/1/137249556945/project/1207260194172075/task/1213998044482808
    case winBackMenu = "funnel_appmenu_macos_winback"

    /// User entered via win-back offer in App Settings
    /// https://app.asana.com/1/137249556945/project/1207260194172075/task/1213998044482808
    case winBackSettings = "funnel_appsettings_macos_winback"

    /// User entered via win-back offer in New Tab Page
    /// https://app.asana.com/1/137249556945/project/1207260194172075/task/1213998044482808
    case winBackNewTabPage = "funnel_newtab_macos_winback"

    /// User entered the funnel via the New Tab Page next steps card.
    /// https://app.asana.com/1/137249556945/project/1207260194172075/task/1213994750860324
    case newTabPageNextStepsCard = "funnel_onboarding_macOS__nextstepscard"

    /// User entered the funnel via the subscription promo on the Fire Window home page.
    /// https://app.asana.com/1/137249556945/project/1207260194172075/task/1214355390442152
    case fireWindowPromo = "funnel_newtab_macos__firewindowvpn"

    /// User entered the funnel via the VPN toolbar button upsell popover.
    /// https://app.asana.com/1/137249556945/project/1207260194172075/task/1213994750860320
    case vpnToolbarUpsell = "funnel_toolbar_macos__subscriptionvpnupsell"

    /// User entered the funnel via the VPN toolbar button popover when their subscription was revoked.
    /// https://app.asana.com/1/137249556945/project/1207260194172075/task/1214811710571517
    case vpnToolbarRevoked = "funnel_toolbar_macos__subscriptionvpnrevoked"

    /// User entered the funnel via the VPN menu-bar status item popover when their subscription was revoked.
    /// https://app.asana.com/1/137249556945/project/1207260194172075/task/1214811710571517
    case vpnMenuBarRevoked = "funnel_menubar_macos__subscriptionvpnrevoked"

    // MARK: - Duck.ai Omnibar Origins

    /// User entered the funnel by tapping a gated model in the address bar's duck.ai model picker.
    /// https://app.asana.com/1/137249556945/project/1208671677432066/task/1215275657171787
    case addressBarModelPicker = "funnel_addressbar_macos__modelpicker"

    /// User entered the funnel by tapping a gated reasoning effort in the address bar's duck.ai omnibar.
    /// https://app.asana.com/1/137249556945/project/1208671677432066/task/1215275657171787
    case addressBarReasoningPicker = "funnel_addressbar_macos__reasoningpicker"

    /// User entered the funnel by tapping a gated model in duck.ai's own model picker.
    /// https://app.asana.com/1/137249556945/project/1208671677432066/task/1215275657171787
    case duckAIModelPicker = "funnel_duckai_macos__modelpicker"

    /// User entered the funnel by tapping a gated reasoning effort in duck.ai's own omnibar.
    /// https://app.asana.com/1/137249556945/project/1208671677432066/task/1215275657171787
    case duckAIReasoningPicker = "funnel_duckai_macos__reasoningpicker"

    /// User entered the funnel by tapping a gated model or reasoning effort in the New Tab Page's duck.ai omnibar.
    /// https://app.asana.com/1/137249556945/task/1216424447885172
    case newTabPageOmnibar = "funnel_newtab_macos__omnibar"
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
