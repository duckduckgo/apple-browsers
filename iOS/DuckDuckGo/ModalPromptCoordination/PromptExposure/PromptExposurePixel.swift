//
//  PromptExposurePixel.swift
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
import PixelKit

enum PromptExposureID: String {
    case appRatingPrompt = "app_rating_prompt"
    case subscriptionWinBackOffer = "subscription_win_back_offer"
    case subscriptionPromoModal = "subscription_promo_modal"
    case newAddressBarPicker = "new_address_bar_picker"
    case reEngagementPrompt = "re_engagement_prompt"
    case additionalDefaultBrowserPrompts = "additional_default_browser_prompts"
    case remoteMessageModal = "remote_message_modal"
    case cookiePopupOptIn = "cookie_popup_opt_in"
    case remoteMessageCard = "remote_message_card"
    case importPasswordsGoogle = "import_passwords_google"
    case autofillExtensionPrompt = "autofill_extension_prompt"
    case addToDockReminder = "add_to_dock_reminder"
}

enum PromptExposurePromptType: String {
    case modal = "MODAL"
    case ntpCard = "NTP_CARD"
}

enum PromptExposurePixel: PixelKit.Event {
    case exposure(daysSinceInstall: String, nthInWeek: String)
    case shown(daysSinceInstall: String, promptID: PromptExposureID)
    case userWeek(daysSinceInstall: String)
    /// Reports the time since the previous coordinated prompt finished.
    case gap(daysSinceInstall: String, gapBucket: String, promptType: PromptExposurePromptType)
    case session(daysSinceInstall: String, promptShown: Bool)

    // Keep the wire names aligned with the Android prompt metrics.
    var namePrefix: PixelKitNamePrefix { .custom("m_") }
    var standardParameters: [PixelKitStandardParameter]? { nil }

    // Bump when parameter meanings or the session sampling rate change.
    private static let version = "1"

    var name: String {
        switch self {
        case .exposure: return "prompt_exposure"
        case .shown: return "prompt_shown"
        case .userWeek: return "prompt_user_week"
        case .gap: return "prompt_gap"
        case .session: return "prompt_session"
        }
    }

    var parameters: [String: String]? {
        var parameters = ["version": Self.version, "petal": "randomize"]
        switch self {
        case .exposure(let days, let nth):
            parameters["days_since_install"] = days
            parameters["nth_in_week"] = nth
        case .shown(let days, let promptID):
            parameters["days_since_install"] = days
            parameters["prompt_id"] = promptID.rawValue
        case .userWeek(let days):
            parameters["days_since_install"] = days
            parameters.removeValue(forKey: "petal")
        case .gap(let days, let gap, let promptType):
            parameters["days_since_install"] = days
            parameters["gap_bucket"] = gap
            parameters["prompt_type"] = promptType.rawValue
        case .session(let days, let promptShown):
            parameters["days_since_install"] = days
            parameters["prompt_shown"] = String(promptShown)
        }
        return parameters
    }
}

enum PromptExposureBuckets {
    static func daysSinceInstall(_ days: Int) -> String {
        switch days {
        case ..<7: return "d0_6"
        case ..<14: return "d7_13"
        case ..<21: return "d14_20"
        case ..<28: return "d21_27"
        default: return "d28_plus"
        }
    }

    static func nthInWeek(_ nth: Int) -> String {
        switch nth {
        case ...10: return String(nth)
        case ...15: return "11_15"
        case ...20: return "16_20"
        default: return "21_plus"
        }
    }

    static func gap(_ elapsed: TimeInterval?) -> String? {
        guard let elapsed else { return "first" }
        switch elapsed {
        case ..<0: return nil
        case ..<60: return "lt_1m"
        case ..<300: return "1_5m"
        case ..<600: return "5_10m"
        case ..<1800: return "10_30m"
        case ..<3600: return "30_60m"
        case ..<14400: return "1_4h"
        case ..<43200: return "4_12h"
        case ..<86400: return "12_24h"
        case ..<172800: return "24_48h"
        default: return "gt_48h"
        }
    }
}
