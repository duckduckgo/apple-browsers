//
//  FavoritesView.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Bookmarks
import SwiftUI
import UniformTypeIdentifiers
import DuckUI
import DesignResourcesKit
import DesignResourcesKitIcons

struct FavoritesView<Model: FavoritesViewModel>: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    @ObservedObject var model: Model

    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let haptics = UIImpactFeedbackGenerator()

    var body: some View {
        VStack(alignment: .center, spacing: 24) {

            NewTabPageGridView {
                ReorderableForEach(model.allFavorites, id: \.id, isReorderingEnabled: model.canEditFavorites) { item in
                    viewFor(item)
                        .previewShape()
                        .transition(.opacity)
                } preview: { item in
                    previewFor(item)
                } onMove: { from, to in
                    haptics.impactOccurred()
                    withAnimation {
                        model.moveFavorites(from: from, to: to)
                    }
                }
            }
        }
        // Prevent the content to leak out of bounds while collapsing
        .clipShape(Rectangle())
        .padding(0)
    }

    @ViewBuilder
    private func previewFor(_ favorite: Favorite) -> some View {
        FavoriteIconView(favorite: favorite, faviconLoading: model.faviconLoader)
            .frame(width: NewTabPageGrid.Item.edgeSize)
            .previewShape()
            .transition(.opacity)
    }

    @ViewBuilder
    private func viewFor(_ favorite: Favorite) -> some View {
        Button(action: {
            model.favoriteSelected(favorite)
            selectionFeedback.selectionChanged()
        }, label: {
            FavoriteItemView(
                favorite: favorite,
                faviconLoading: model.faviconLoader,
                isEditable: model.canEditFavorites,
                onMenuAction: { action in
                    switch action {
                    case .delete: model.deleteFavorite(favorite)
                    case .edit: model.editFavorite(favorite)
                    }
                })
            .background(.clear)
            .frame(width: NewTabPageGrid.Item.edgeSize)
        })
        .buttonStyle(.plain)
    }
}

private extension View {
    func previewShape() -> some View {
        contentShape(.dragPreview, FavoriteIconView.itemShape())
    }
}

#Preview {
    PreviewWrapperView()
}

private struct PreviewWrapperView: View {
    @State var isAddingFavorite = false
    var body: some View {
        FavoritesView(model: FavoritesPreviewModel())
    }
}
