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
/// `autoconsentEnabled` is the feature state at the moment the dialog was shown.
enum CookiePopupProtectionOptInPixel: PixelKitEvent {
    /// The dialog was shown on launch for the first time (once per install).
    case shownFirst(autoconsentEnabled: Bool)
    /// The dialog was shown on launch again (any presentation after the first).
    case shownRepeat(autoconsentEnabled: Bool)
    /// The user confirmed the dialog; `preference` is the resulting Cookie Pop-up Protection preference,
    /// `timeSinceShown` the bucketed time from first shown to confirmation.
    case optionConfirmed(preference: CookiePopupPreference, autoconsentEnabled: Bool, timeSinceShown: String?)

    var name: String {
        switch self {
        case .shownFirst: return "cookie_popup_opt_in_shown_first_macos"
        case .shownRepeat: return "cookie_popup_opt_in_shown_repeat_macos"
        case .optionConfirmed: return "cookie_popup_opt_in_option_confirmed_macos"
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { [.pixelSource] }

    var parameters: [String: String]? {
        switch self {
        case .shownFirst(let autoconsentEnabled), .shownRepeat(let autoconsentEnabled):
            return ["autoconsent_enabled": autoconsentEnabled ? "true" : "false"]
        case .optionConfirmed(let preference, let autoconsentEnabled, let timeSinceShown):
            var parameters = [
                "cookie_popup_preference": preference.rawValue,
                "autoconsent_enabled": autoconsentEnabled ? "true" : "false"
            ]
            if let timeSinceShown {
                parameters["time_since_shown"] = timeSinceShown
            }
            return parameters
        }
    }
}
