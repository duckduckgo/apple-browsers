//
//  FocusedSuggestionsView.swift
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

/// Presents the existing suggestions list in a focused layout. The owner supplies its shared
/// view model and resolved visibility; fetching and row actions remain with their existing owners.
struct FocusedSuggestionsView: View {
    let viewModel: SuggestionsListViewModel
    let isAddressBarAtBottom: Bool
    let isVisible: Bool
    let isFadingOut: Bool

    var body: some View {
        // Keep the list mounted while hidden to preserve its state and avoid a background flash
        // when returning from favorites or the empty state.
        SuggestionsListView(viewModel: viewModel, isAddressBarAtBottom: isAddressBarAtBottom)
            .opacity(isVisible ? 1 : 0)
            // Fade in on a mode change, but hide immediately so recents do not linger over favorites.
            .animation(isVisible ? .easeInOut(duration: 0.2) : nil, value: isVisible)
            .modifier(FocusedContentDismissFade(isFadingOut: isFadingOut))
            .allowsHitTesting(isVisible)
    }
}
