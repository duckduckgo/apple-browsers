//
//  AutoconsentPixels.swift
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

import PixelKit
import UIKit

enum AutoconsentPixel: PixelKitEventV2, PixelKitEventWithCustomPrefix {
    
    case acInit
    case missedPopup
    case errorMultiplePopups
    case errorOptoutFailed
    case popupFound
    case done
    case doneCosmetic
    case animationShown
    case animationShownCosmetic
    case disabledForSite
    case detectedByPatterns
    case detectedByBoth
    case detectedOnlyRules
    case selfTestOk
    case selfTestFail

    case summary(events: [String: Int])

    static var summaryPixels: [AutoconsentPixel] =  [
        .acInit,
        .missedPopup,
        .errorMultiplePopups,
        .errorOptoutFailed,
        .popupFound,
        .done,
        .doneCosmetic,
        .animationShown,
        .animationShownCosmetic,
        .disabledForSite,
        .detectedByPatterns,
        .detectedByBoth,
        .detectedOnlyRules,
        .selfTestOk,
        .selfTestFail
    ]

    var name: String {
        switch self {
        case .acInit: "autoconsent_init"
        case .missedPopup: "autoconsent_missed-popup"
        case .errorMultiplePopups: "autoconsent_error_multiple-popups"
        case .errorOptoutFailed: "autoconsent_error_optout"
        case .popupFound: "autoconsent_popup-found"
        case .done: "autoconsent_done"
        case .doneCosmetic: "autoconsent_done_cosmetic"
        case .animationShown: "autoconsent_animation-shown"
        case .animationShownCosmetic: "autoconsent_animation-shown_cosmetic"
        case .disabledForSite: "autoconsent_disabled-for-site"
        case .detectedByPatterns: "autoconsent_detected-by-patterns"
        case .detectedByBoth: "autoconsent_detected-by-both"
        case .detectedOnlyRules: "autoconsent_detected-only-rules"
        case .selfTestOk: "autoconsent_self-test-ok"
        case .selfTestFail: "autoconsent_self-test-fail"
        case .summary: "autoconsent_summary"
        }
    }

    var key: String {
        return name.dropping(prefix: "autoconsent_")
    }

    var parameters: [String: String]? {
        switch self {
        case let .summary(events):
            Dictionary(uniqueKeysWithValues: AutoconsentPixel.summaryPixels.map { pixel in
            (pixel.key, "\(events[pixel.key] ?? 0)")
            })
        default: [:]
        }
    }

    var error: (any Error)? {
        nil
    }
    
    var namePrefix: String {
#if os(macOS)
        return "m_mac"
#elseif os(iOS)
        return "m_"
#endif
    }
}
