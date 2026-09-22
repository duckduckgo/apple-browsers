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
    @State private var availableWidth: CGFloat = 0
    @ScaledMetric(relativeTo: .caption) private var minimumTileWidth: CGFloat = 64

    private var columnCount: Int {
        RedesignedNewTabPageLayout.favoriteColumnCount(width: availableWidth, minimumTileWidth: minimumTileWidth)
    }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: columnCount)
    }
    private var collapsedCount: Int { columnCount * 2 }

    private var hasOverflow: Bool { model.allFavorites.count > collapsedCount }

    private var visibleFavorites: [Favorite] {
        if isExpanded || !hasOverflow { return model.allFavorites }
        return Array(model.allFavorites.prefix(collapsedCount - 1))
    }

    var body: some View {
        if !model.isEmpty {
            LazyVGrid(columns: columns, alignment: .center, spacing: 20) {
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
                        VStack(spacing: 6) {
                            Image(uiImage: DesignSystemImages.Glyphs.Size24.chevronDownSmall)
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                                .frame(width: 48, height: 48)
                                .background(Color(designSystemColor: .controlsFillPrimary))
                                .clipShape(Circle())
                            Text(isExpanded ? "See Less" : "See All")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(Color(designSystemColor: .textPrimary))
                    }
                    .buttonStyle(.plain)
                }
            }
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: FavoritesWidthPreferenceKey.self, value: geometry.size.width)
                }
            }
            .onPreferenceChange(FavoritesWidthPreferenceKey.self) { availableWidth = $0 }
        }
    }
}

private struct FavoritesWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
