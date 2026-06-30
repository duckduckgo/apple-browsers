//
//  CookiePopupProtectionOptInPixel.swift
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
import PixelKit
import WebExtensions

/// Telemetry for the Cookie Pop-up Protection opt-in dialog.
enum CookiePopupProtectionOptInPixel: PixelKitEvent {
    /// The dialog was shown on launch for the first time (once per install).
    case shownFirst
    /// The dialog was shown on launch again (any presentation after the first).
    case shownRepeat
    /// The user confirmed the dialog; `preference` is the resulting Cookie Pop-up Protection preference.
    case optionConfirmed(preference: CookiePopupPreference)

    var name: String {
        switch self {
        case .shownFirst: return "cookie_popup_opt_in_shown_first_macos"
        case .shownRepeat: return "cookie_popup_opt_in_shown_repeat_macos"
        case .optionConfirmed: return "cookie_popup_opt_in_option_confirmed_macos"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .optionConfirmed(let preference):
            return ["cookie_popup_preference": preference.rawValue]
        case .shownFirst, .shownRepeat:
            return nil
        }
    }
}
