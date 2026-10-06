//
//  FireDialogResult.swift
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

import History

// Result returned by FireDialogView when using onConfirm callback
struct FireDialogResult {
    let clearingOption: FireDialogViewModel.ClearingOption
    let includeHistory: Bool
    let includeTabsAndWindows: Bool
    let includeCookiesAndSiteData: Bool
    let includeChatHistory: Bool
    /// Optional selection of cookie domains (eTLD+1). When provided, cookie/site data clearing is limited to this set.
    var selectedCookieDomains: Set<String>?
    /// Optional explicit visits selection for history flows
    var selectedVisits: [Visit]?
    /// Burn all windows in case we are burning visits for today (respecting closeWindows flag)
    var isToday: Bool = false
}
