//
//  AutocompleteSuggestionsPixels.swift
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

import Core
import PixelKit
import Suggestions

/// Fires the `m_autocomplete_display_*` / `m_autocomplete_click_*` telemetry for the UTI search
/// suggestions, reusing the pixel names the legacy tray fired so the dashboard stays continuous.
struct AutocompleteSuggestionsPixels {

    private let pixelFiring: (any PixelKitFiring)?

    init(pixelFiring: (any PixelKitFiring)? = PixelKit.shared) {
        self.pixelFiring = pixelFiring
    }

    /// Fires one pixel per local suggestion category present. Call once when a suggestions session
    /// ends, over the results last shown to the user (matches legacy `viewWillDisappear` semantics).
    func fireDisplayPixels(for suggestions: [Suggestion]) {
        var bookmark = false
        var favorite = false
        var history = false
        var openTab = false

        for suggestion in suggestions {
            switch suggestion {
            case .bookmark(_, _, isFavorite: let isFavorite, _):
                if isFavorite { favorite = true } else { bookmark = true }
            case .historyEntry:
                history = true
            case .openTab:
                openTab = true
            default:
                break
            }
        }

        if bookmark { pixelFiring?.fire(Pixel.Event.autocompleteDisplayedLocalBookmark) }
        if favorite { pixelFiring?.fire(Pixel.Event.autocompleteDisplayedLocalFavorite) }
        if history { pixelFiring?.fire(Pixel.Event.autocompleteDisplayedLocalHistory) }
        if openTab { pixelFiring?.fire(Pixel.Event.autocompleteDisplayedOpenedTab) }
    }

    /// Fires the click pixel matching a tapped suggestion. `.askAIChat` is a daily pixel with
    /// feature-discovery params, so it's fired separately via `fireAskAIChatClickPixel`.
    func fireClickPixel(for suggestion: Suggestion) {
        switch suggestion {
        case .bookmark(_, _, let isFavorite, _):
            pixelFiring?.fire(isFavorite ? Pixel.Event.autocompleteClickFavorite : .autocompleteClickBookmark)
        case .historyEntry(_, let url, _):
            pixelFiring?.fire(url.isDuckDuckGoSearch ? Pixel.Event.autocompleteClickSearchHistory : .autocompleteClickSiteHistory)
        case .phrase:
            pixelFiring?.fire(Pixel.Event.autocompleteClickPhrase)
        case .website:
            pixelFiring?.fire(Pixel.Event.autocompleteClickWebsite)
        case .openTab:
            pixelFiring?.fire(Pixel.Event.autocompleteClickOpenTab)
        default:
            break
        }
    }

    /// The experimental/legacy split and feature-discovery params are resolved by the caller, which
    /// owns those dependencies.
    func fireAskAIChatClickPixel(isExperimentalExperience: Bool, additionalParameters params: [String: String]) {
        let pixel: Pixel.Event = isExperimentalExperience ? .autocompleteAskAIChatExperimentalExperience : .autocompleteAskAIChatLegacyExperience
        pixelFiring?.fire(pixel, frequency: .legacyDailyAndCount, options: .parameters(params))
    }
}
