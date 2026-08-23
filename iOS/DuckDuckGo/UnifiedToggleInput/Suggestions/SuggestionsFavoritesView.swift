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

/// Search-only RMF messages. Favorites live in a separate list row so message changes don't move
/// the persistent Escape Hatch row.
struct FocusedNewTabPageMessagesView: View {

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @ObservedObject var messagesModel: NewTabPageMessagesModel

    var body: some View {
        VStack(spacing: Metrics.sectionSpacing) {
            ForEach(messagesModel.homeMessageViewModels, id: \.viewIdentity) { messageModel in
                HomeMessageView(viewModel: messageModel)
                    .frame(maxWidth: horizontalSizeClass == .regular ? Metrics.messageMaximumWidthPad : Metrics.messageMaximumWidth)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private enum Metrics {
        static let sectionSpacing: CGFloat = 26
        static let messageMaximumWidth: CGFloat = 380
        static let messageMaximumWidthPad: CGFloat = 455
    }
}
