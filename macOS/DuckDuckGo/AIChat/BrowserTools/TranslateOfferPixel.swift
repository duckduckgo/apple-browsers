//
//  TranslateOfferPixel.swift
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

/// The offer to translate a foreign page. Parameters carry fixed values only: never languages, URLs or titles.
/// All fire daily and count.
enum TranslateOfferPixel: PixelKit.Event {

    /// Event Trigger: The offer showed for a page. Not fired again when the user returns to the tab.
    case shown

    /// Event Trigger: The user closed the offer. `dontAskAgain` is the checkbox, whatever the answer.
    case answered(TranslateOfferAnswer, dontAskAgain: Bool)

    /// Event Trigger: The Translate Pages mode changed in Settings, including a reset.
    case settingChanged(TranslatePagesMode, via: SettingChangeSource)

    /// Event Trigger: A prompt that has priority kept the offer from showing, or closed it. Once per page.
    case suppressed(by: TranslateOfferSuppressor)

    enum SettingChangeSource: String {
        case dropdown
        case reset
        case resetAll = "reset_all"
    }

    var name: String {
        switch self {
        case .shown: "aichat_translate_offer_shown"
        case .answered: "aichat_translate_offer_answered"
        case .settingChanged: "aichat_translate_pages_setting_changed"
        case .suppressed: "aichat_translate_offer_suppressed"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .shown:
            return nil
        case .answered(let answer, let dontAskAgain):
            return ["answer": answer.rawValue, "dont_ask_again": String(dontAskAgain)]
        case .settingChanged(let mode, let source):
            return ["value": mode == .neverAsk ? "never_ask" : "always_ask", "via": source.rawValue]
        case .suppressed(let suppressor):
            return ["by": suppressor.rawValue]
        }
    }

    var standardParameters: [PixelKitStandardParameter]? { nil }
}

enum TranslateOfferAnswer: String {
    case translate
    case noThanks = "no_thanks"
    case escape
    /// The Duck.ai button's close, on hover.
    case close
}
