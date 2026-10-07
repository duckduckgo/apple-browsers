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
    /// Shows the Add Favorite tile and empty state when set.
    let onAddFavorite: (() -> Void)?
    @State private var isDraggingFavorite = false
    @State private var gridHeight: CGFloat = 0
    @State private var headerHeight: CGFloat = 0
    @State private var collapsedItemHeights: [Favorite.ID: CGFloat] = [:]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: Metrics.columnSpacing, alignment: .top), count: Metrics.columnCount)
    private let haptics = UIImpactFeedbackGenerator()

    private var isExpanded: Bool { hasOverflow && model.expansionState.isExpanded }

    private var collapsedCapacity: Int { columns.count }

    // Reserve a control column in both presentations so expansion state stays shared.
    private var hasOverflow: Bool { model.allFavorites.count >= collapsedCapacity }

    private var collapsedFavoriteIDs: Set<Favorite.ID> {
        Set(model.allFavorites.prefix(collapsedCapacity - 1).map(\.id))
    }

    private var collapsedHeight: CGFloat {
        let estimatedRowHeight = Metrics.tileSize + RedesignedFavoriteTileMetrics.iconToTitleSpacing
            + UIFont.daxCaption().lineHeight * CGFloat(RedesignedFavoriteTileMetrics.titleLineLimit)
        return model.allFavorites.prefix(columns.count)
            .compactMap { collapsedItemHeights[$0.id] }
            .max() ?? estimatedRowHeight
    }

    private var expansionAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: Metrics.expansionDuration)
    }

    var body: some View {
        if model.isEmpty {
            if onAddFavorite != nil {
                emptyState
                    .padding(Metrics.contentPadding)
            }
        } else {
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

    private var emptyState: some View {
        LazyVGrid(columns: columns, alignment: .center, spacing: Metrics.rowSpacing) {
            addFavoriteButton

            ForEach(1..<columns.count, id: \.self) { _ in
                Circle()
                    .strokeBorder(Color(designSystemColor: .textSecondary),
                                  style: StrokeStyle(lineWidth: Metrics.placeholderStrokeWidth, dash: Metrics.placeholderDashPattern))
                    .frame(width: Metrics.tileSize, height: Metrics.tileSize)
                    .accessibilityHidden(true)
            }
        }
    }

    private var addFavoriteButton: some View {
        Button {
            onAddFavorite?()
        } label: {
            RedesignedFavoriteTileView(title: UserText.addFavoriteScreenTitle) {
                Image(uiImage: DesignSystemImages.Glyphs.Size24.add)
                    .foregroundColor(Color(designSystemColor: .icons))
                    .frame(width: Metrics.tileSize, height: Metrics.tileSize)
                    .background(Color(designSystemColor: .controlsFillPrimary))
                    .clipShape(Circle())
            }
        }
        .buttonStyle(.plain)
        .disabled(isDraggingFavorite)
        .accessibilityLabel(UserText.addFavoriteScreenTitle)
    }

    private var favoritesGrid: some View {
        LazyVGrid(columns: columns, alignment: .center, spacing: Metrics.rowSpacing) {
            favorites
            if onAddFavorite != nil {
                addFavoriteButton
                    .revealed(!hasOverflow || isExpanded, animation: expansionAnimation, value: isExpanded)
            }
            if hasOverflow {
                expansionButton(expands: false)
                    .revealed(isExpanded, animation: expansionAnimation, value: isExpanded)
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
                          isItemReorderingEnabled: { isExpanded || !overflow || collapsedIDs.contains($0.id) },
                          previewPath: { UIBezierPath(rect: $0) }) { favorite in
            let isVisible = isExpanded || !overflow || collapsedIDs.contains(favorite.id)
            ZStack(alignment: .top) {
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
                .allowsHitTesting(isVisible)
                .accessibilityHidden(!isVisible)
                if expandButtonID == favorite.id {
                    // Both tiles participate in sizing so See All fits without a separate measurement.
                    expansionButton(expands: true)
                        .opacity(isExpanded ? 0 : 1)
                        .allowsHitTesting(!isExpanded)
                        .accessibilityHidden(isExpanded)
                }
            }
            // Animate the tile crossfade independently of the viewport.
            .animation(expansionAnimation, value: isExpanded)
            .background {
                if measuredIDs.contains(favorite.id) {
                    GeometryReader { geometry in
                        Color.clear.preference(key: FavoritesGridHeightKey.self, value: geometry.size.height)
                    }
                }
            }
            .onPreferenceChange(FavoritesGridHeightKey.self) { height in
                guard measuredIDs.contains(favorite.id), collapsedItemHeights[favorite.id] != height else { return }
                collapsedItemHeights[favorite.id] = height
            }
        } preview: { favorite in
            // The native drag source owns the whole tile, including presses on its title.
            RedesignedFavoriteTileView(title: favorite.title) {
                RedesignedFavoriteIconView(favorite: favorite, faviconLoading: model.faviconLoader)
            }
        } onMove: { from, to in
            haptics.impactOccurred()
            withAnimation { model.moveFavorites(from: from, to: to) }
        } onMoveFinished: {
            model.favoritesReordered()
        }
    }

    private func expansionButton(expands: Bool) -> some View {
        Button {
            guard !isDraggingFavorite else { return }
            model.expansionState.isExpanded = expands
        } label: {
            RedesignedFavoriteTileView(title: expands ? UserText.newTabPageFavoritesSeeAll : UserText.newTabPageFavoritesSeeLess) {
                Image(uiImage: expands ? DesignSystemImages.Glyphs.Size24.chevronDownSmall : DesignSystemImages.Glyphs.Size24.chevronUpSmall)
                    .foregroundColor(Color(designSystemColor: .icons))
                    .frame(width: Metrics.tileSize, height: Metrics.tileSize)
                    .background(Color(designSystemColor: .controlsFillPrimary))
                    .clipShape(Circle())
            }
        }
        .buttonStyle(.plain)
        .disabled(isDraggingFavorite)
    }
}

/// Apply intermediate heights explicitly so UIKit resizing the outer host does not
/// move SwiftUI's grid to its final position before the reveal has finished.
private struct FavoritesExpansionContainer<Header: View, Grid: View>: View, Animatable {
    var progress: CGFloat
    let collapsedGridHeight: CGFloat
    let expandedGridHeight: CGFloat
    let headerHeight: CGFloat
    let header: Header
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
                // Let native lift shadows extend above and beside the grid. Cancel the padding
                // outside the mask so tile positions and the bottom reveal edge stay unchanged.
                .padding(.horizontal, Metrics.liftPreviewPadding)
                .padding(.top, Metrics.liftPreviewPadding)
                // Keep the grid's layout proposal constant while only its viewport changes.
                .frame(height: max(expandedGridHeight, collapsedGridHeight) + Metrics.liftPreviewPadding, alignment: .top)
                .frame(height: revealedGridHeight + Metrics.liftPreviewPadding, alignment: .top)
                .clipped()
                .padding(.top, -Metrics.liftPreviewPadding)
                .padding(.horizontal, -Metrics.liftPreviewPadding)
        }
        .padding(Metrics.contentPadding)
        .background {
            RedesignedNewTabPageModuleBackground()
                .opacity(progress)
        }
        .animation(nil, value: progress)
    }
}

private extension View {
    /// Fades the view in or out while keeping its layout slot, and hides it from touches and accessibility.
    func revealed(_ isVisible: Bool, animation: Animation?, value: Bool) -> some View {
        opacity(isVisible ? 1 : 0)
            .animation(animation, value: value)
            .allowsHitTesting(isVisible)
            .accessibilityHidden(!isVisible)
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
    static let liftPreviewPadding: CGFloat = 32
    static let headerSpacing: CGFloat = 8
    static let headerToGridSpacing: CGFloat = 12
    static let headerIconSize: CGFloat = 16
    static let collapseIconSize: CGFloat = 12
    static let collapseIconBackgroundSize: CGFloat = 20
    static let columnCount = 5
    static let columnSpacing: CGFloat = 8
    static let rowSpacing: CGFloat = 20
    static let tileSize: CGFloat = 48
    static let placeholderStrokeWidth: CGFloat = 1
    static let placeholderDashPattern: [CGFloat] = [4, 4]
}
