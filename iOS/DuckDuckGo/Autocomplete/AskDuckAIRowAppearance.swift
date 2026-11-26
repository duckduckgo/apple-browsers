//
//  AskDuckAIRowAppearance.swift
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

import DesignResourcesKitIcons
import Suggestions
import SwiftUI

/// How the Ask Duck.ai row at the bottom of the address bar suggestions looks.
/// Both suggestion surfaces (legacy autocomplete and unified input) derive it the same way.
enum AskDuckAIRowAppearance: Equatable {
    /// Today's row: the query as title, "Ask anything privately" under it, chat bubble glyph.
    case legacy
    /// Redesigned row with the one-colour Duck.ai logo: plenty of search suggestions above it.
    case oneColour
    /// Redesigned row with the full-colour Duck.ai logo: few search suggestions left.
    case fullColour

    /// The row is highlighted when this many search suggestions or fewer are shown: design asked for full colour
    /// once fewer than 5 remain.
    static let highlightThreshold = 4

    /// Cross-fade between the one-colour and full-colour logo (ease-out). Design's value, to be tuned on device.
    static let iconFadeDuration: TimeInterval = 0.4

    /// Counts the search suggestions in the raw result, so the fallback row that repeats the query when the
    /// result is empty never counts. Sites, bookmarks, history and open tabs don't count either.
    static func make(isRedesignEnabled: Bool, result: SuggestionResult) -> Self {
        guard isRedesignEnabled else { return .legacy }
        let shown = result.topHits + result.duckduckgoSuggestions + result.localSuggestions
        let searchSuggestionCount = shown.filter {
            if case .phrase = $0 { return true }
            return false
        }.count
        return searchSuggestionCount <= highlightThreshold ? .fullColour : .oneColour
    }

    /// VoiceOver label for the redesigned row: "Ask Duck.ai, <query>".
    static func accessibilityLabel(query: String) -> String {
        "\(UserText.autocompleteAskDuckAITitle), \(query)"
    }

    /// The typed query as the redesigned row shows it.
    static func subtitle(for query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The Duck.ai logo on the redesigned Ask Duck.ai row. The one-colour logo follows `tint`;
/// the full-colour logo keeps its own colours. Only the icon animates when the highlight changes.
/// A keyboard- or pointer-selected row uses the standard selected look, so it shows the one-colour logo, switching
/// at once like the row's background does.
struct AskDuckAIRowIcon: View {

    let isHighlighted: Bool
    let isSelected: Bool
    let tint: Color

    private var showsFullColour: Bool { isHighlighted && !isSelected }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let size: CGFloat = 24

    var body: some View {
        ZStack {
            Image(uiImage: DesignSystemImages.Glyphs.Size24.duckAi)
                .resizable()
                .frame(width: Self.size, height: Self.size)
                .tintIfAvailable(tint)
                .opacity(showsFullColour ? 0 : 1)

            Image(uiImage: DesignSystemImages.Color.Size24.duckAI)
                .renderingMode(.original)
                .resizable()
                .frame(width: Self.size, height: Self.size)
                .opacity(showsFullColour ? 1 : 0)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: AskDuckAIRowAppearance.iconFadeDuration), value: isHighlighted)
    }
}
