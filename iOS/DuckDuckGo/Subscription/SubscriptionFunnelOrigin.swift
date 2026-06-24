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
    /// https://app.asana.com/1/137249556945/project/1207260194172075/task/1210468753388385
    case onboarding = "funnel_onboarding_ios"

    /// User entered the funnel via the skipped-onboarding promo modal.
    /// https://app.asana.com/1/137249556945/project/1207260194172075/task/1213994750860308
    case skippedOnboarding = "funnel_modal_ios__skippedonboardingupsell"

    /// User entered the funnel via the App Settings screen.
    /// https://app.asana.com/1/137249556945/project/1207260194172075/task/1210468753388392
    case appSettings = "funnel_appsettings_ios"

    /// User entered the funnel via the VPN menu item in the New Tab Page app menu.
    /// https://app.asana.com/1/137249556945/project/1207260194172075/task/1212891971534036
    case newTabMenu = "funnel_appmenu_ios"

    /// User entered the funnel by tapping a gated model in the Unified Toggle Input model picker from the address bar.
    /// https://app.asana.com/1/137249556945/project/1207260194172075/task/1213994750860310
    case addressBarModelPicker = "funnel_addressbar_ios__modelpicker"

    /// User entered the funnel by tapping a gated reasoning level in the Unified Toggle Input reasoning picker from the address bar.
    /// https://app.asana.com/1/137249556945/project/1207260194172075/task/1213994750860310
    case addressBarReasoningPicker = "funnel_addressbar_ios__reasoningpicker"

    /// User entered the funnel by tapping a gated model in the Unified Toggle Input model picker from the Duck.ai tab.
    /// https://app.asana.com/1/137249556945/project/1207260194172075/task/1213994750860310
    case duckAIModelPicker = "funnel_duckai_ios__modelpicker"

    /// User entered the funnel by tapping a gated reasoning level in the Unified Toggle Input reasoning picker from the Duck.ai tab.
    /// https://app.asana.com/1/137249556945/project/1207260194172075/task/1213994750860310
    case duckAIReasoningPicker = "funnel_duckai_ios__reasoningpicker"

    // MARK: - Win-Back Offer Origins
    
    /// User entered via win-back offer launch prompt
    /// https://app.asana.com/1/137249556945/project/1207260194172075/task/1213998044482808
    case winBackLaunch = "funnel_applaunch_ios_winback"
    
    /// User entered via win-back offer in App Settings
    /// https://app.asana.com/1/137249556945/project/1207260194172075/task/1213998044482808
    case winBackSettings = "funnel_appsettings_ios_winback"

    /// User entered the funnel via the VPN access-revoked alert when their subscription was revoked.
    /// https://app.asana.com/1/137249556945/project/1207260194172075/task/1214811710571517
    case vpnAccessRevokedAlert = "funnel_alert_ios__subscriptionvpnrevoked"

    // MARK: - VPN Entry Points (non-subscriber fallback)

    /// User entered the funnel by tapping the customizable toolbar VPN button without an active VPN entitlement.
    /// https://app.asana.com/1/137249556945/project/1207260194172075/task/1215296884609840
    case toolbarVPN = "funnel_toolbar_ios__subscriptionvpn"

    /// User entered the funnel by tapping the customizable address-bar VPN button without an active VPN entitlement.
    /// https://app.asana.com/1/137249556945/project/1207260194172075/task/1215296884609842
    case addressBarVPN = "funnel_addressbar_ios__subscriptionvpn"

    /// User entered the funnel via the VPN Control Center widget / App Intent deep link without an active VPN entitlement.
    /// https://app.asana.com/1/137249556945/project/1207260194172075/task/1215398999855855
    case widgetVPN = "funnel_widget_ios__subscriptionvpn"

    /// User entered the funnel via the home-screen app-icon VPN quick action without an active VPN entitlement.
    /// https://app.asana.com/1/137249556945/project/1207260194172075/task/1215398999855857
    case shortcutVPN = "funnel_integration_ios_shortcut_subscriptionvpn"

    /// User entered the funnel by tapping the VPN push notification without an active VPN entitlement.
    /// https://app.asana.com/1/137249556945/project/1207260194172075/task/1215398999855859
    case notificationVPN = "funnel_notification_ios__subscriptionvpn"
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

/// Represents the origin of a subscription plan change (not a subscription entry point) in the iOS app.
enum SubscriptionPlanChangeOrigin: String {
    /// User triggered a plan change by cancelling a pending downgrade.
    case cancelDowngrade = "funnel_canceldowngrade_ios"
}
