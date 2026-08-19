//
//  OnboardingPersonalization+AppSettings.swift
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

import Foundation
import Onboarding
import WebExtensions

/// Store adapter backing the App-Settings toggles used across two onboarding steps.
///
/// - **Recently visited sites** (Search step): passthrough to `recentlyVisitedSites`:
///   - `true` → On (the app default, shown selected on first load)
///   - `false` → Off.
/// - **Cookie pop-up protection** + **Pop-ups without opt-outs** (Block Ads step): passthrough to `cookiePopupPreference` (`.off` / `.default` / `.max`)
///   turning protection off collapses the preference to `.off`, which makes pop-ups-without-opt-outs `false`.
///
/// - See: [Search: Setup step](https://app.asana.com/1/137249556945/task/1216445221863465?focus=true)
/// - See: [Block Ads: Setup step](https://app.asana.com/1/137249556945/task/1216445221863468?focus=true)
extension AppUserDefaults: OnboardingAppSettingsPersonalizationStore {

    public var recentlyVisitedSitesEnabled: Bool {
        get {
            recentlyVisitedSites
        }
        set {
            recentlyVisitedSites = newValue
        }
    }

    public var isCookiePopUpProtectionEnabled: Bool {
        get {
            cookiePopupPreference.isBlockingEnabled
        }
        set {
            // Disabling clears pop-ups-without-opt-outs
            cookiePopupPreference = .preference(
                autoManageEnabled: newValue,
                popUpsWithoutOptOutsEnabled: newValue ? cookiePopupPreference.isPopUpsWithoutOptOutsEnabled : false
            )
        }
    }

    public var isPopUpsWithoutOptOutsEnabled: Bool {
        get {
            cookiePopupPreference.isPopUpsWithoutOptOutsEnabled
        }
        set {
            // Only reachable while protection is on, so auto-manage stays enabled.
            cookiePopupPreference = .preference(autoManageEnabled: true, popUpsWithoutOptOutsEnabled: newValue)
        }
    }

}
