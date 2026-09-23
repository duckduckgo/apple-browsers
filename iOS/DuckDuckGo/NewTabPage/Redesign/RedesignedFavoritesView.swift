//
//  RedesignedFavoritesView.swift
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

import DesignResourcesKit
import DesignResourcesKitIcons
import SwiftUI

struct RedesignedFavoritesView: View {
    @ObservedObject var model: FavoritesViewModel
    @State private var isExpanded = false
    private let columns = Array(repeating: GridItem(.flexible(), spacing: Metrics.columnSpacing, alignment: .top), count: Metrics.columnCount)

    private var hasOverflow: Bool { model.allFavorites.count > Metrics.collapsedCount }

    private var visibleFavorites: [Favorite] {
        if isExpanded || !hasOverflow { return model.allFavorites }
        return Array(model.allFavorites.prefix(Metrics.collapsedCount - 1))
    }

    var body: some View {
        if !model.isEmpty {
            LazyVGrid(columns: columns, alignment: .center, spacing: Metrics.rowSpacing) {
                ReorderableForEach(visibleFavorites, id: \.id, isReorderingEnabled: model.canEditFavorites) { favorite in
                    Button {
                        model.favoriteSelected(favorite)
                    } label: {
                        RedesignedFavoriteItemView(favorite: favorite,
                                         faviconLoading: model.faviconLoader,
                                         isEditable: model.canEditFavorites,
                                         onMenuAction: { action in
                            switch action {
                            case .edit: model.editFavorite(favorite)
                            case .delete: model.deleteFavorite(favorite)
                            }
                        })
                    }
                    .buttonStyle(.plain)
                } preview: { favorite in
                    RedesignedFavoriteIconView(favorite: favorite, faviconLoading: model.faviconLoader)
                } onMove: { from, to in
                    withAnimation { model.moveFavorites(from: from, to: to) }
                } onMoveFinished: {
                    model.favoritesReordered()
                }
                if hasOverflow {
                    Button {
                        withAnimation { isExpanded.toggle() }
                    } label: {
                        VStack(spacing: Metrics.iconToTitleSpacing) {
                            Image(uiImage: DesignSystemImages.Glyphs.Size24.chevronDownSmall)
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                                .frame(width: Metrics.tileSize, height: Metrics.tileSize)
                                .background(Color(designSystemColor: .controlsFillPrimary))
                                .clipShape(Circle())
                            Text(isExpanded ? UserText.newTabPageFavoritesSeeLess : UserText.newTabPageFavoritesSeeAll)
                                .daxCaption1()
                        }
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                    }
                    .buttonStyle(.plain)
                }
            }

        }
    }
}

private enum Metrics {
    static let columnCount = 5
    static let collapsedCount = 10
    static let columnSpacing: CGFloat = 8
    static let rowSpacing: CGFloat = 20
    static let iconToTitleSpacing: CGFloat = 6
    static let tileSize: CGFloat = 48
}
