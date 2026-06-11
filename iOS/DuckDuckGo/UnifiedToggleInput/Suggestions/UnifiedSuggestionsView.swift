//
//  UnifiedSuggestionsView.swift
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

import SwiftUI

/// The single unified suggestions surface for both Search and Duck.ai. Switches on the
/// resolver's content state: list rows / favorites / logo. One view, model decides the rest.
struct UnifiedSuggestionsView: View {

    @ObservedObject var viewModel: UnifiedSuggestionsViewModel
    let isAddressBarAtBottom: Bool
    let header: AnyView?
    /// Duck.ai sync-promo card; shown below the hatch in non-typing states. nil when hidden.
    let syncPromo: AnyView?
    /// Built lazily by the host for the `.favorites` state; nil when favorites aren't supported (Duck.ai).
    let favoritesProvider: () -> NewTabPageViewController?

    var body: some View {
        // The escape hatch is one persistent element above the content — NOT duplicated inside the
        // recents List header and the favorites/logo overlay. Re-creating it across those subtrees
        // on a mode switch made it jump instead of gliding with the input; a single instance rides
        // the inset animation in both directions.
        VStack(spacing: 0) {
            if showsHatch, let header {
                header
                    .padding(.horizontal, Metrics.contentHorizontalMargin)
                    .padding(.top, hatchTopInset)
                    .padding(.bottom, Metrics.hatchBottomInset)
            }
            if isNonTypingState, viewModel.showsSyncPromo, let syncPromo {
                syncPromo
                    .padding(.horizontal, Metrics.contentHorizontalMargin)
                    .padding(.top, showsHatch ? Metrics.syncPromoInterCardSpacing : hatchTopInset)
                    .padding(.bottom, Metrics.hatchBottomInset)
            }
            contentArea
        }
    }

    /// The non-typing states (favorites / logo / recents), mirroring legacy `isQueryActive`; the
    /// search / duck.ai suggestion lists are the typing states.
    private var isNonTypingState: Bool {
        switch viewModel.content {
        case .favorites, .logo: return true
        case .list(let kind): return kind == .recents
        }
    }

    /// The hatch additionally requires a header model.
    private var showsHatch: Bool {
        header != nil && isNonTypingState
    }

    /// Top bar: the hatch sits 6pt below the input's bottom margin (Figma). Bottom bar: it keeps the
    /// larger inset that lines it up with the NTP escape hatch.
    private var hatchTopInset: CGFloat {
        isAddressBarAtBottom ? Metrics.hatchTopInsetBottomBar : Metrics.hatchTopInsetTopBar
    }

    private var contentArea: some View {
        // The list stays mounted in every state so SwiftUI never recreates it (a fresh `List`
        // flashes its default background before `.scrollContentBackground(.hidden)` applies).
        // Favorites renders on top; the list is hidden + non-interactive beneath it.
        ZStack {
            listLayer
            overlayLayer
        }
    }

    private var isShowingList: Bool {
        if case .list = viewModel.content { return true }
        return false
    }

    /// The kind the mounted list is currently bound to; defaults to `.search` when idle so the
    /// list holds a stable (empty) view-model rather than being torn down.
    private var activeListKind: SuggestionsListSourceKind {
        if case .list(let kind) = viewModel.content { return kind }
        return .search
    }

    private var listLayer: some View {
        SuggestionsListView(viewModel: viewModel.listViewModel(for: activeListKind),
                            isAddressBarAtBottom: isAddressBarAtBottom)
            .opacity(isShowingList ? 1 : 0)
            .allowsHitTesting(isShowingList)
    }

    private var isShowingFavorites: Bool {
        if case .favorites = viewModel.content { return true }
        return false
    }

    /// Favorites stays mounted like the list and toggles a plain `.opacity` — NOT an insert/remove
    /// `.transition` (which snaps when interrupted by rapid Search↔Duck.ai toggling). Its opacity is
    /// instant (`.animation(nil)`): the incoming list fades in, but favorites must not linger visibly
    /// over Duck.ai while the crossfade runs. Logo is still drawn by DaxLogoManager.
    @ViewBuilder
    private var overlayLayer: some View {
        if let controller = favoritesProvider() {
            SuggestionsFavoritesView(controller: controller)
                .opacity(isShowingFavorites ? 1 : 0)
                .animation(nil, value: isShowingFavorites)
                .allowsHitTesting(isShowingFavorites)
        }
    }

    private enum Metrics {
        /// Matches the NTP's `sectionsViewHorizontalPadding` (regularPadding) so the hatch and the
        /// suggestion list share the favorites grid's side margins.
        static let contentHorizontalMargin: CGFloat = 24
        /// Top bar: 6pt below the input (Figma). Bottom bar: lines the hatch up with the NTP hatch.
        static let hatchTopInsetTopBar: CGFloat = 6
        static let hatchTopInsetBottomBar: CGFloat = 16
        static let hatchBottomInset: CGFloat = 16
        /// Gap between the escape hatch and the sync-promo card (mirrors legacy 20pt inter-card spacing).
        static let syncPromoInterCardSpacing: CGFloat = 20
    }
}
