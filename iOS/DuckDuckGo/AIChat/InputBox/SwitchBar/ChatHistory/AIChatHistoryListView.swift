//
//  AIChatHistoryListView.swift
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

import AIChat
import DesignResourcesKit
import DesignResourcesKitIcons
import SwiftUI

/// A view displaying the list of pinned and recent AI chats
struct AIChatHistoryListView: View {
    private enum Constants {
        static let iconSize: CGFloat = 16
        static let iconTextSpacing: CGFloat = 12
    }

    @ObservedObject var viewModel: AIChatSuggestionsViewModel
    let onChatSelected: (AIChatSuggestion) -> Void

    var body: some View {
        List {
            if !pinnedChats.isEmpty {
                Section {
                    ForEach(pinnedChats) { chat in
                        chatRow(chat: chat, isPinned: true)
                    }
                }
            }

            if !recentChats.isEmpty {
                Section {
                    ForEach(recentChats) { chat in
                        chatRow(chat: chat, isPinned: false)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .applyBackground()
    }

    // MARK: - Private Computed Properties

    private var pinnedChats: [AIChatSuggestion] {
        viewModel.filteredSuggestions.filter { $0.isPinned }
    }

    private var recentChats: [AIChatSuggestion] {
        viewModel.filteredSuggestions.filter { !$0.isPinned }
    }

    // MARK: - Private Views

    @ViewBuilder
    private func chatRow(chat: AIChatSuggestion, isPinned: Bool) -> some View {
        Button {
            onChatSelected(chat)
        } label: {
            HStack(spacing: Constants.iconTextSpacing) {
                icon(isPinned: isPinned)
                    .frame(width: Constants.iconSize, height: Constants.iconSize)
                    .foregroundColor(Color(designSystemColor: .icons))

                Text(chat.title)
                    .daxBodyRegular()
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func icon(isPinned: Bool) -> some View {
        if isPinned {
            Image(uiImage: DesignSystemImages.Glyphs.Size16.pin)
                .resizable()
                .renderingMode(.template)
        } else {
            Image(uiImage: DesignSystemImages.Glyphs.Size16.history)
                .resizable()
                .renderingMode(.template)
        }
    }
}

// MARK: - Preview

#if DEBUG
import SwiftUI

#Preview("AI Chat History List") {
    let viewModel = AIChatSuggestionsViewModel()
    viewModel.setChats(pinned: [], recent: AIChatSuggestion.mockRecentChats)

    return AIChatHistoryListView(
        viewModel: viewModel,
        onChatSelected: { chat in
            print("Selected chat: \(chat.title)")
        }
    )
}
#endif
