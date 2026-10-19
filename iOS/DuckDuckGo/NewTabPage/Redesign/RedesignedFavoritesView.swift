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
    /// Shows the Add Favorite tile and empty state when set.
    let onAddFavorite: (() -> Void)?

    var body: some View {
        RedesignedFavoritesSection(model: model, expansionState: model.expansionState, onAddFavorite: onAddFavorite)
    }
}

private struct RedesignedFavoritesSection: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ObservedObject var model: FavoritesViewModel
    @ObservedObject var expansionState: FavoritesExpansionState
    let onAddFavorite: (() -> Void)?
    @State private var isDraggingFavorite = false
    @State private var gridHeight: CGFloat = 0
    @State private var headerHeight: CGFloat = 0
    @State private var collapsedItemHeights: [Favorite.ID: CGFloat] = [:]
    private let haptics = UIImpactFeedbackGenerator()

    private var columns: [GridItem] {
        let count = horizontalSizeClass == .regular ? Metrics.regularColumnCount : Metrics.compactColumnCount
        return Array(repeating: GridItem(.flexible(), spacing: Metrics.columnSpacing, alignment: .top), count: count)
    }

    private var isExpanded: Bool { hasOverflow && expansionState.isExpanded }

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
        favoritesGridLayout {
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

    /// Lays out the favorites grid, eagerly where the platform allows it.
    @ViewBuilder
    private func favoritesGridLayout<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if #available(iOS 16.0, *) {
            // A lazy grid re-places and re-measures its tiles whenever the animated viewport
            // changes its visible rect, and every tile is realized during expansion regardless.
            FavoritesGridLayout(columnCount: columns.count, columnSpacing: Metrics.columnSpacing, rowSpacing: Metrics.rowSpacing) {
                content()
            }
        } else {
            LazyVGrid(columns: columns, alignment: .center, spacing: Metrics.rowSpacing) {
                content()
            }
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
                expansionState.isExpanded = false
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
        let expanded = isExpanded
        let isInRevealedRegion = { (favorite: Favorite) in expanded || !overflow || collapsedIDs.contains(favorite.id) }
        let modelID = ObjectIdentifier(model)
        let isEditable = model.canEditFavorites
        let expansionSlot = FavoriteTileContentKey.ExpansionSlot(expansionStateID: ObjectIdentifier(expansionState),
                                                                 isExpanded: expanded,
                                                                 isDragging: isDraggingFavorite,
                                                                 reduceMotion: reduceMotion)
        return ReorderableForEach(allFavorites, id: \.id, isReorderingEnabled: model.canEditFavorites,
                          onDragActivityChanged: { isDraggingFavorite = $0 },
                          itemContentKey: { favorite in
                              AnyHashable(FavoriteTileContentKey(modelID: modelID, favorite: favorite, isEditable: isEditable,
                                                                 isMeasured: measuredIDs.contains(favorite.id),
                                                                 expansionSlot: favorite.id == expandButtonID ? expansionSlot : nil))
                          },
                          isItemReorderingEnabled: isInRevealedRegion,
                          isItemInteractive: { isInRevealedRegion($0) || $0.id == expandButtonID },
                          previewPath: { UIBezierPath(ovalIn: $0) }) { favorite in
            let isFavoriteShown = expandButtonID != favorite.id || isExpanded
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
                .opacity(isFavoriteShown ? 1 : 0)
                .allowsHitTesting(isFavoriteShown)
                .accessibilityHidden(!isFavoriteShown)
                if expandButtonID == favorite.id {
                    // Both tiles participate in sizing so See All fits without a separate measurement.
                    expansionButton(expands: true)
                        .opacity(isExpanded ? 0 : 1)
                        .allowsHitTesting(!isExpanded)
                        .accessibilityHidden(isExpanded)
                }
            }
            // Animate the tile crossfade independently of the viewport.
            .animation(expansionAnimation, value: isFavoriteShown)
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
            // Match the context-menu preview while keeping the whole tile as the drag source.
            RedesignedFavoriteIconView(favorite: favorite, faviconLoading: model.faviconLoader)
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
            expansionState.isExpanded = expands
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

private struct FavoritesExpansionContainer<Header: View, Grid: View>: View {
    let progress: CGFloat
    let collapsedGridHeight: CGFloat
    let expandedGridHeight: CGFloat
    let headerHeight: CGFloat
    let header: Header
    let grid: Grid

    var body: some View {
        let fullGridHeight = max(expandedGridHeight, collapsedGridHeight)
        VStack(spacing: 0) {
            header
                .fixedSize(horizontal: false, vertical: true)
                .modifier(TopEdgeReveal(progress: progress, collapsedHeight: 0, expandedHeight: headerHeight))
                .opacity(progress)
            grid
                // Let native lift shadows extend above and beside the grid. Cancel the padding
                // outside the mask so tile positions and the bottom reveal edge stay unchanged.
                .padding(.horizontal, Metrics.liftPreviewPadding)
                .padding(.top, Metrics.liftPreviewPadding)
                // Keep the grid's layout proposal constant while only its viewport changes.
                .frame(height: fullGridHeight + Metrics.liftPreviewPadding, alignment: .top)
                .modifier(TopEdgeReveal(progress: progress,
                                        collapsedHeight: collapsedGridHeight + Metrics.liftPreviewPadding,
                                        expandedHeight: fullGridHeight + Metrics.liftPreviewPadding,
                                        edgeFadeHeight: Metrics.revealEdgeFadeHeight))
                .padding(.top, -Metrics.liftPreviewPadding)
                .padding(.horizontal, -Metrics.liftPreviewPadding)
        }
        .padding(Metrics.contentPadding)
        .background {
            RedesignedNewTabPageModuleBackground()
                .opacity(progress)
        }
    }
}

/// Clips content to a height interpolated between its collapsed and expanded values,
/// optionally fading the moving bottom edge while the reveal is in progress.
private struct TopEdgeReveal: ViewModifier, Animatable {
    var progress: CGFloat
    let collapsedHeight: CGFloat
    let expandedHeight: CGFloat
    var edgeFadeHeight: CGFloat = 0

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    private var revealedHeight: CGFloat {
        collapsedHeight + (expandedHeight - collapsedHeight) * progress
    }

    private var distanceFromNearestEnd: CGFloat {
        max(0, min(revealedHeight - collapsedHeight, expandedHeight - revealedHeight))
    }

    private var currentEdgeFadeHeight: CGFloat {
        min(edgeFadeHeight, distanceFromNearestEnd)
    }

    // Only this body runs on each animation frame. `content` is opaque here, so the
    // header and tiles are not re-evaluated while the height animates.
    func body(content: Content) -> some View {
        content
            // Intermediate heights are applied explicitly so UIKit resizing the outer host does not
            // move SwiftUI's grid to its final position before the reveal has finished.
            .frame(height: revealedHeight, alignment: .top)
            .mask(alignment: .top) {
                VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: currentEdgeFadeHeight)
                }
            }
            .clipped()
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

/// Inputs of a favorite tile's content.
private struct FavoriteTileContentKey: Hashable {
    /// Inputs read only by the tile that also hosts See All.
    struct ExpansionSlot: Hashable {
        let expansionStateID: ObjectIdentifier
        let isExpanded: Bool
        let isDragging: Bool
        let reduceMotion: Bool
    }

    let modelID: ObjectIdentifier
    let favorite: Favorite
    let isEditable: Bool
    let isMeasured: Bool
    let expansionSlot: ExpansionSlot?
}

/// Equal flexible columns with top-aligned tiles, matching `LazyVGrid` with `.flexible()` items.
@available(iOS 16.0, *)
private struct FavoritesGridLayout: Layout {
    let columnCount: Int
    let columnSpacing: CGFloat
    let rowSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.replacingUnspecifiedDimensions().width
        let rowHeights = rowHeights(for: subviews, columnWidth: columnWidth(for: width))
        let totalRowSpacing = rowSpacing * CGFloat(max(rowHeights.count - 1, 0))
        return CGSize(width: width, height: rowHeights.reduce(0, +) + totalRowSpacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columnWidth = columnWidth(for: bounds.width)
        let tileProposal = ProposedViewSize(width: columnWidth, height: nil)
        var rowMinY = bounds.minY
        for (row, rowHeight) in rowHeights(for: subviews, columnWidth: columnWidth).enumerated() {
            for column in 0..<columnCount {
                let index = row * columnCount + column
                guard index < subviews.count else { break }
                let tileMidX = bounds.minX + CGFloat(column) * (columnWidth + columnSpacing) + columnWidth / 2
                subviews[index].place(at: CGPoint(x: tileMidX, y: rowMinY), anchor: .top, proposal: tileProposal)
            }
            rowMinY += rowHeight + rowSpacing
        }
    }

    private func columnWidth(for width: CGFloat) -> CGFloat {
        max(0, (width - columnSpacing * CGFloat(columnCount - 1)) / CGFloat(columnCount))
    }

    private func rowHeights(for subviews: Subviews, columnWidth: CGFloat) -> [CGFloat] {
        let tileProposal = ProposedViewSize(width: columnWidth, height: nil)
        return stride(from: 0, to: subviews.count, by: columnCount).map { rowStart in
            subviews[rowStart..<min(rowStart + columnCount, subviews.count)]
                .map { $0.sizeThatFits(tileProposal).height }
                .max() ?? 0
        }
    }
}

private enum Metrics {
    static let expansionDuration: TimeInterval = 0.3
    static let contentPadding: CGFloat = 16
    static let liftPreviewPadding: CGFloat = 32
    static let revealEdgeFadeHeight: CGFloat = 56
    static let headerSpacing: CGFloat = 8
    static let headerToGridSpacing: CGFloat = 12
    static let headerIconSize: CGFloat = 16
    static let collapseIconSize: CGFloat = 12
    static let collapseIconBackgroundSize: CGFloat = 20
    static let compactColumnCount = 5
    static let regularColumnCount = 6
    static let columnSpacing: CGFloat = 8
    static let rowSpacing: CGFloat = 20
    static let tileSize: CGFloat = 48
    static let placeholderStrokeWidth: CGFloat = 1
    static let placeholderDashPattern: [CGFloat] = [4, 4]
}
