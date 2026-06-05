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
        case .list:
            SuggestionsListView(viewModel: viewModel.listViewModel,
                                isAddressBarAtBottom: isAddressBarAtBottom,
                                header: header)
        case .favorites:
            if let controller = favoritesProvider() {
                SuggestionsFavoritesView(controller: controller)
            } else {
                Color.clear
            }
        case .logo:
            // Part 2c moves the logo into the view; for now DaxLogoManager keeps drawing it.
            Color.clear
        }
    }
}
