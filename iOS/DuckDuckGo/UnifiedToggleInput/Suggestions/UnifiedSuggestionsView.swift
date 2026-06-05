//
//  UnifiedSuggestionsView.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//  Licensed under the Apache License, Version 2.0.
//

import SwiftUI

/// The single unified suggestions surface for both Search and Duck.ai. Switches on the
/// resolver's content state: list rows / favorites / logo. One view, model decides the rest.
struct UnifiedSuggestionsView: View {

    @ObservedObject var viewModel: UnifiedSuggestionsViewModel
    let isAddressBarAtBottom: Bool
    let header: AnyView?
    /// Built lazily by the host for the `.favorites` state; nil when favorites aren't supported (Duck.ai).
    let favoritesProvider: () -> NewTabPageViewController?

    var body: some View {
        switch viewModel.content {
        case .list(let kind):
            // The escape hatch is hidden while typing (search / duck.ai suggestion lists);
            // it only shows in the non-typing recents list (mirrors legacy `isQueryActive`).
            SuggestionsListView(viewModel: viewModel.listViewModel,
                                isAddressBarAtBottom: isAddressBarAtBottom,
                                header: kind == .recents ? header : nil)
        case .favorites:
            if let controller = favoritesProvider() {
                // The escape hatch is the unified view's chrome (same as logo/recents/duck.ai),
                // not the NTP's own — so it renders identically across every UTI state.
                VStack(spacing: 0) {
                    if let header {
                        header
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                    }
                    SuggestionsFavoritesView(controller: controller)
                }
            } else {
                Color.clear
            }
        case .logo:
            // The logo itself stays drawn by DaxLogoManager (moved into the view in Part 2c).
            // The escape hatch is chrome and must still show in the empty state, pinned at the top.
            if let header {
                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                    Spacer(minLength: 0)
                }
            } else {
                Color.clear
            }
        }
    }
}
