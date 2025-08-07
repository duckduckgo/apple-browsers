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

    /// User entered the funnel via the VPN upsell.
    case vpnUpsell = "funnel_toolbar_macos"
}
