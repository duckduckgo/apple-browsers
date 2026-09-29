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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var model: FavoritesViewModel
    @State private var isDraggingFavorite = false
    @State private var gridHeight: CGFloat = 0
    @State private var headerHeight: CGFloat = 0
    @State private var collapsedItemHeights: [Favorite.ID: CGFloat] = [:]
    @State private var expandButtonHeight: CGFloat = 0
    private let columns = Array(repeating: GridItem(.flexible(), spacing: Metrics.columnSpacing, alignment: .top), count: Metrics.columnCount)
    private let haptics = UIImpactFeedbackGenerator()

    private var isExpanded: Bool { model.expansionState.isExpanded }

    private var collapsedCapacity: Int { columns.count * Metrics.collapsedRowCount }

    private var hasOverflow: Bool { model.allFavorites.count > collapsedCapacity }

    private var collapsedFavoriteIDs: Set<Favorite.ID> {
        Set(model.allFavorites.prefix(collapsedCapacity - 1).map(\.id))
    }

    private var collapsedHeight: CGFloat {
        let rowCount = Metrics.collapsedRowCount
        let estimatedRowHeight = Metrics.tileSize + Metrics.iconToTitleSpacing + UIFont.daxCaption1().lineHeight * 2
        return (0..<rowCount).reduce(CGFloat(0)) { height, row in
            let favorites = model.allFavorites.dropFirst(row * columns.count).prefix(columns.count)
            let itemHeight = favorites.compactMap { collapsedItemHeights[$0.id] }.max() ?? estimatedRowHeight
            let rowHeight = row == rowCount - 1 ? max(itemHeight, expandButtonHeight) : itemHeight
            return height + rowHeight
        } + CGFloat(rowCount - 1) * Metrics.rowSpacing
    }

    private var expansionAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: Metrics.expansionDuration)
    }

    var body: some View {
        if !model.isEmpty {
            FavoritesExpansionContainer(
                progress: isExpanded ? 1 : 0,
                collapsedGridHeight: hasOverflow ? collapsedHeight : gridHeight,
                expandedGridHeight: gridHeight,
                headerHeight: max(headerHeight, Metrics.collapseIconBackgroundSize) + Metrics.headerToGridSpacing,
                header: header
                    .padding(.bottom, Metrics.headerToGridSpacing)
                    .allowsHitTesting(isExpanded)
                    .accessibilityHidden(!isExpanded),
                grid: favoritesGrid
            )
            .animation(expansionAnimation, value: isExpanded)
        }
    }

    private var favoritesGrid: some View {
        LazyVGrid(columns: columns, alignment: .center, spacing: Metrics.rowSpacing) {
            favorites
            if hasOverflow {
                // Keep the final tile in the measured grid so expanding does not change
                // its geometry while the viewport is revealing the remaining rows.
                expansionButton(expands: false)
                    .opacity(isExpanded ? 1 : 0)
                    .animation(expansionAnimation, value: isExpanded)
                    .allowsHitTesting(isExpanded)
                    .accessibilityHidden(!isExpanded)
            }
        }
        // Measure the complete grid independently of the animated viewport. Cells retain
        // their row positions while the viewport reveals them from its top edge.
        .fixedSize(horizontal: false, vertical: true)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: FavoritesGridHeightKey.self, value: geometry.size.height)
            }
        }
        .onPreferenceChange(FavoritesGridHeightKey.self) { height in
            if gridHeight != height { gridHeight = height }
        }
    }

    private var header: some View {
        HStack(spacing: Metrics.headerSpacing) {
            Image(uiImage: DesignSystemImages.Glyphs.Size24.favorite)
                .resizable()
                .scaledToFit()
                .frame(width: Metrics.headerIconSize, height: Metrics.headerIconSize)
                .foregroundColor(Color(designSystemColor: .icons))
                .accessibilityHidden(true)
            Text(UserText.sectionTitleFavorites)
                .daxButton()
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                guard !isDraggingFavorite else { return }
                model.expansionState.isExpanded = false
            } label: {
                Image(uiImage: DesignSystemImages.Glyphs.Size12.chevronUp)
                    .frame(width: Metrics.collapseIconSize, height: Metrics.collapseIconSize)
                    .frame(width: Metrics.collapseIconBackgroundSize, height: Metrics.collapseIconBackgroundSize)
                    .background(Color(designSystemColor: .controlsFillPrimary))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(isDraggingFavorite)
            .accessibilityLabel(UserText.newTabPageFavoritesSeeLess)
        }
        .foregroundColor(Color(designSystemColor: .textPrimary))
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: FavoritesHeaderHeightKey.self, value: geometry.size.height)
            }
        }
        .onPreferenceChange(FavoritesHeaderHeightKey.self) { height in
            if headerHeight != height { headerHeight = height }
        }
    }

    private var favorites: some View {
        let allFavorites = model.allFavorites
        let collapsedIDs = collapsedFavoriteIDs
        let measuredIDs = Set(allFavorites.prefix(collapsedCapacity).map(\.id))
        let overflow = hasOverflow
        let expandButtonID = overflow ? allFavorites[collapsedCapacity - 1].id : nil
        return ReorderableForEach(allFavorites, id: \.id, isReorderingEnabled: model.canEditFavorites,
                          onDragActivityChanged: { isDraggingFavorite = $0 },
                          itemSizeCacheKey: { AnyHashable($0) },
                          isItemReorderingEnabled: { isExpanded || !overflow || collapsedIDs.contains($0.id) }) { favorite in
            let isVisible = isExpanded || !overflow || collapsedIDs.contains(favorite.id)
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
            .opacity(isVisible ? 1 : 0)
            // Animate within the tile's host without replacing its root view on every
            // viewport animation frame.
            .animation(expansionAnimation, value: isExpanded)
            .allowsHitTesting(isVisible)
            .accessibilityHidden(!isVisible)
            .overlay(alignment: .top) {
                if expandButtonID == favorite.id {
                    expandButton
                        .opacity(isExpanded ? 0 : 1)
                        .animation(expansionAnimation, value: isExpanded)
                        .allowsHitTesting(!isExpanded)
                        .accessibilityHidden(isExpanded)
                }
            }
            .background {
                if measuredIDs.contains(favorite.id) {
                    GeometryReader { geometry in
                        Color.clear.preference(key: FavoritesGridHeightKey.self, value: geometry.size.height)
                    }
                }
            }
            // The tile is hosted by the native drag source, so consume its measurement
            // here rather than expecting preferences to cross the hosting boundary.
            .onPreferenceChange(FavoritesGridHeightKey.self) { height in
                guard measuredIDs.contains(favorite.id), collapsedItemHeights[favorite.id] != height else { return }
                collapsedItemHeights[favorite.id] = height
            }
        } preview: { favorite in
            RedesignedFavoriteIconView(favorite: favorite, faviconLoading: model.faviconLoader)
        } onMove: { from, to in
            haptics.impactOccurred()
            withAnimation { model.moveFavorites(from: from, to: to) }
        } onMoveFinished: {
            model.favoritesReordered()
        }
    }

    private var expandButton: some View {
        expansionButton(expands: true)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: FavoritesGridHeightKey.self, value: geometry.size.height)
                }
            }
            .onPreferenceChange(FavoritesGridHeightKey.self) { height in
                if expandButtonHeight != height { expandButtonHeight = height }
            }
    }

    private func expansionButton(expands: Bool) -> some View {
        Button {
            guard !isDraggingFavorite else { return }
            model.expansionState.isExpanded = expands
        } label: {
            VStack(spacing: Metrics.iconToTitleSpacing) {
                Image(uiImage: expands ? DesignSystemImages.Glyphs.Size24.chevronDownSmall : DesignSystemImages.Glyphs.Size24.chevronUpSmall)
                    .frame(width: Metrics.tileSize, height: Metrics.tileSize)
                    .background(Color(designSystemColor: .controlsFillPrimary))
                    .clipShape(Circle())
                Text(expands ? UserText.newTabPageFavoritesSeeAll : UserText.newTabPageFavoritesSeeLess)
                    .daxCaption1()
            }
            .foregroundColor(Color(designSystemColor: .textPrimary))
        }
        .buttonStyle(.plain)
        .disabled(isDraggingFavorite)
    }
}

/// Interpolate the viewport explicitly. Animating the grid's layout transaction also animates
/// native hosting-view positions as UIKit resizes the block, moving the entire grid offscreen.
private struct FavoritesExpansionContainer<Header: View, Grid: View>: View, Animatable {
    var progress: CGFloat
    let collapsedGridHeight: CGFloat
    let expandedGridHeight: CGFloat
    let headerHeight: CGFloat
    let header: Header
    // Store the grid as a value: invoking a builder with progress rebuilds every
    // native drag host (and invalidates its intrinsic size) on each animation frame.
    let grid: Grid

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let revealedGridHeight = collapsedGridHeight + (max(expandedGridHeight, collapsedGridHeight) - collapsedGridHeight) * progress
        VStack(spacing: 0) {
            header
                .fixedSize(horizontal: false, vertical: true)
                .opacity(progress)
                .frame(height: headerHeight * progress, alignment: .top)
                .clipped()
            grid
                // Keep the grid's layout proposal constant while only its viewport changes.
                .frame(height: max(expandedGridHeight, collapsedGridHeight), alignment: .top)
                .frame(height: revealedGridHeight, alignment: .top)
                .clipped()
        }
        .padding(Metrics.contentPadding)
        .background {
            RedesignedNewTabPageModuleBackground()
                .opacity(progress)
        }
        .clipped()
        // Progress already supplies each intermediate layout. Child positions must be
        // applied immediately instead of starting another animation toward the final size.
        .animation(nil, value: progress)
    }
}

private struct FavoritesHeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct FavoritesGridHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private enum Metrics {
    static let expansionDuration: TimeInterval = 0.3
    static let contentPadding: CGFloat = 16
    static let headerSpacing: CGFloat = 8
    static let headerToGridSpacing: CGFloat = 12
    static let headerIconSize: CGFloat = 16
    static let collapseIconSize: CGFloat = 12
    static let collapseIconBackgroundSize: CGFloat = 20
    static let columnCount = 5
    static let collapsedRowCount = 1
    static let columnSpacing: CGFloat = 8
    static let rowSpacing: CGFloat = 20
    static let iconToTitleSpacing: CGFloat = 6
    static let tileSize: CGFloat = 48
}
