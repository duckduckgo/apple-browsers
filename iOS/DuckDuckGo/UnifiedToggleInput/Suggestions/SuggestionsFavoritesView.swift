//
//  SuggestionsFavoritesView.swift
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

/// The focused New Tab Page sections rendered inside the unified suggestions list. The list owns
/// scrolling and the Escape Hatch; this view contributes only RMF messages and Search favorites.
struct FocusedNewTabPageContentView: View {

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @ObservedObject var messagesModel: NewTabPageMessagesModel
    @ObservedObject var favoritesViewModel: FavoritesViewModel
    let showsFavorites: Bool

    var body: some View {
        VStack(spacing: Metrics.sectionSpacing) {
            ForEach(messagesModel.homeMessageViewModels, id: \.viewIdentity) { messageModel in
                HomeMessageView(viewModel: messageModel)
                    .frame(maxWidth: horizontalSizeClass == .regular ? Metrics.messageMaximumWidthPad : Metrics.messageMaximumWidth)
                    .transition(.scale.combined(with: .opacity))
            }

            if showsFavorites, !favoritesViewModel.allFavorites.isEmpty {
                FavoritesView(model: favoritesViewModel)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, Metrics.favoritesHorizontalInset)
            }
        }
    }

    private enum Metrics {
        static let sectionSpacing: CGFloat = 26
        /// The unified list starts at 16pt; favorites use the NTP's 24pt grid margin.
        static let favoritesHorizontalInset: CGFloat = 8
        static let messageMaximumWidth: CGFloat = 380
        static let messageMaximumWidthPad: CGFloat = 455
    }
}
