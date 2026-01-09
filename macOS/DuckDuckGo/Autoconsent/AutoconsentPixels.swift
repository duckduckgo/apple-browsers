//
//  AutoconsentPixels.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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

enum AutoconsentPixel: PixelKitEvent {

    case acInit
    case errorMultiplePopups
    case errorOptoutFailed
    case popupFound
    case done
    case doneCosmetic
    case doneHeuristic
    case animationShown
    case animationShownCosmetic
    case disabledForSite
    case detectedByPatterns
    case detectedByBoth
    case detectedOnlyRules
    case selfTestOk
    case selfTestFail
    case errorReloadLoop
    case popoverShown
    case popoverClosed
    case popoverClicked
    case popoverNewTabOpened
    case popoverAutoDismissed

    case summary(events: [String: Int])
    case usageStats(stats: [String: String])

    static var summaryPixels: [AutoconsentPixel] =  [
        .acInit,
        .errorMultiplePopups,
        .errorOptoutFailed,
        .popupFound,
        .done,
        .doneCosmetic,
        .doneHeuristic,
        .animationShown,
        .animationShownCosmetic,
        .disabledForSite,
        .detectedByPatterns,
        .detectedByBoth,
        .detectedOnlyRules,
        .selfTestOk,
        .selfTestFail,
        .errorReloadLoop,
        .popoverShown,
        .popoverClosed,
        .popoverClicked,
        .popoverNewTabOpened,
        .popoverAutoDismissed
    ]

    var name: String {
        switch self {
        case .acInit: "autoconsent_init"
        case .errorMultiplePopups: "autoconsent_error_multiple-popups"
        case .errorOptoutFailed: "autoconsent_error_optout"
        case .errorReloadLoop: "autoconsent_error_reload-loop"
        case .popupFound: "autoconsent_popup-found"
        case .done: "autoconsent_done"
        case .doneCosmetic: "autoconsent_done_cosmetic"
        case .doneHeuristic: "autoconsent_done_heuristic"
        case .animationShown: "autoconsent_animation-shown"
        case .animationShownCosmetic: "autoconsent_animation-shown_cosmetic"
        case .disabledForSite: "autoconsent_disabled-for-site"
        case .detectedByPatterns: "autoconsent_detected-by-patterns"
        case .detectedByBoth: "autoconsent_detected-by-both"
        case .detectedOnlyRules: "autoconsent_detected-only-rules"
        case .selfTestOk: "autoconsent_self-test-ok"
        case .selfTestFail: "autoconsent_self-test-fail"
        case .popoverShown: "autoconsent_popover-shown"
        case .popoverClosed: "autoconsent_popover-closed"
        case .popoverClicked: "autoconsent_popover-clicked"
        case .popoverNewTabOpened: "autoconsent_popover-new-tab-opened"
        case .popoverAutoDismissed: "autoconsent_popover-autodismissed"
        case .summary: "autoconsent_summary"
        case .usageStats: "autoconsent_usage-stats"
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
        case let .usageStats(stats): {
            var params = stats
            // Added as a requirement from the privacy triage
            // see: https://app.asana.com/1/137249556945/project/1209220182846570/task/1211062294407696?focus=true
            params["petal"] = "true"
            return params
        }()
        default: [:]
        }
    }

    var standardParameters: [PixelKitStandardParameter]? {
        switch self {
        case .acInit,
                .errorMultiplePopups,
                .errorOptoutFailed,
                .errorReloadLoop,
                .popupFound,
                .done,
                .doneCosmetic,
                .doneHeuristic,
                .animationShown,
                .animationShownCosmetic,
                .disabledForSite,
                .detectedByPatterns,
                .detectedByBoth,
                .detectedOnlyRules,
                .selfTestOk,
                .selfTestFail,
                .popoverShown,
                .popoverClosed,
                .popoverClicked,
                .popoverNewTabOpened,
                .popoverAutoDismissed,
                .summary,
                .usageStats:
            return [.pixelSource]
        }
    }

}
