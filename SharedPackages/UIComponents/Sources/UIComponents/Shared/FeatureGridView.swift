//
//  FeatureGridView.swift
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

import SwiftUI
import DesignResourcesKit

// MARK: - Layout Constants

public enum FeatureGridLayoutConstants {
    public static let contentSpacing: CGFloat = 12
    public static let textSpacing: CGFloat = 6
    public static let cardPadding: CGFloat = 12
    public static let cornerRadius: CGFloat = 8
    public static let borderWidth: CGFloat = 1

    public static let iconContainerSize: CGFloat = 32
    public static let iconSize: CGFloat = 16

    public static let defaultColumns: Int = 2
    public static let defaultCellMinHeight: CGFloat = 90
}

private typealias LayoutConstants = FeatureGridLayoutConstants

// MARK: - Feature Model

/// Model representing a feature for display in feature grid
public struct FeatureGridItem: Identifiable {
    public let id = UUID()
    public let title: String
    public let description: String
    public let iconName: String?

    #if os(iOS)
    public let iconImage: UIImage?

    public init(title: String, description: String, iconName: String? = nil, iconImage: UIImage? = nil) {
        self.title = title
        self.description = description
        self.iconName = iconName
        self.iconImage = iconImage ?? (iconName.flatMap { UIImage(named: $0) })
    }
    #elseif os(macOS)
    public let iconImage: NSImage?

    public init(title: String, description: String, iconName: String? = nil, iconImage: NSImage? = nil) {
        self.title = title
        self.description = description
        self.iconName = iconName
        self.iconImage = iconImage ?? (iconName.flatMap { NSImage(named: $0) })
    }
    #endif
}

// MARK: - Grid Layout Style

public enum FeatureGridLayoutStyle {
    case staggered  // Masonry-style layout with varying heights
    case fixed      // Fixed height grid layout
}

// MARK: - Main Component

/// A flexible grid view for displaying features in either staggered or fixed layout
public struct FeatureGridView: View {
    let features: [FeatureGridItem]
    let layoutStyle: FeatureGridLayoutStyle
    let columns: Int
    let spacing: CGFloat
    let cellMinHeight: CGFloat?
    let borderWidth: CGFloat

    public init(
        features: [FeatureGridItem],
        layoutStyle: FeatureGridLayoutStyle = .staggered,
        columns: Int = FeatureGridLayoutConstants.defaultColumns,
        spacing: CGFloat = FeatureGridLayoutConstants.contentSpacing,
        cellMinHeight: CGFloat? = nil,
        borderWidth: CGFloat = 0
    ) {
        self.features = features
        self.layoutStyle = layoutStyle
        self.columns = columns
        self.spacing = spacing
        self.cellMinHeight = cellMinHeight ?? (layoutStyle == .fixed ? LayoutConstants.defaultCellMinHeight : nil)
        self.borderWidth = borderWidth
    }

    public var body: some View {
        Group {
            switch layoutStyle {
            case .staggered:
                FeatureStaggeredGrid(
                    features: features,
                    columns: columns,
                    spacing: spacing,
                    borderWidth: borderWidth
                )
            case .fixed:
                FeatureFixedGrid(
                    features: features,
                    columns: columns,
                    spacing: spacing,
                    cellMinHeight: cellMinHeight ?? LayoutConstants.defaultCellMinHeight,
                    borderWidth: borderWidth
                )
            }
        }
    }
}

// MARK: - Individual Feature Card

struct FeatureCardView: View {
    let feature: FeatureGridItem
    let minHeight: CGFloat?
    let borderWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutConstants.contentSpacing) {
            // Icon at the top
            HStack {
                iconPlaceholder
                Spacer()
            }

            // Text content below the icon
            VStack(alignment: .leading, spacing: LayoutConstants.textSpacing) {
                Text(feature.title)
                    .font(titleFont)
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .fixedSize(horizontal: false, vertical: true)

                Text(feature.description)
                    .font(bodyFont)
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
            }

            if minHeight != nil {
                Spacer(minLength: 0)
            }
        }
        .padding(LayoutConstants.cardPadding)
        .frame(minHeight: minHeight, maxHeight: minHeight != nil ? .infinity : nil)
        .background(Color(designSystemColor: .surface))
        .cornerRadius(LayoutConstants.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: LayoutConstants.cornerRadius)
                .stroke(Color(designSystemColor: .lines), lineWidth: borderWidth)
        )
    }

    // Platform-specific font handling - matching original platform implementations
    private var titleFont: Font {
        #if os(iOS)
        return Font(UIFont.daxFootnoteSemibold())
        #else
        return .title3
        #endif
    }

    private var bodyFont: Font {
        #if os(iOS)
        return Font(UIFont.daxFootnoteRegular())
        #else
        return .body
        #endif
    }

    @ViewBuilder
    private var iconPlaceholder: some View {
        Circle()
            .fill(Color(designSystemColor: .surface))
            .frame(width: LayoutConstants.iconContainerSize, height: LayoutConstants.iconContainerSize)
            .overlay(
                Circle()
                    .stroke(Color(designSystemColor: .lines), lineWidth: borderWidth)
            )
            .overlay(iconImage)
    }

    @ViewBuilder
    private var iconImage: some View {
        #if os(iOS)
        if let iconImage = feature.iconImage {
            iconImageStyled(Image(uiImage: iconImage))
        } else if let iconName = feature.iconName {
            iconImageStyled(Image(iconName))
        }
        #elseif os(macOS)
        if let iconImage = feature.iconImage {
            iconImageStyled(Image(nsImage: iconImage))
        } else if let iconName = feature.iconName {
            iconImageStyled(Image(iconName))
        }
        #endif
    }

    private func iconImageStyled(_ image: Image) -> some View {
        image
            .resizable()
            .renderingMode(.template)
            .aspectRatio(contentMode: .fit)
            .frame(width: LayoutConstants.iconSize, height: LayoutConstants.iconSize)
            .foregroundColor(Color(designSystemColor: .textPrimary))
    }
}

// MARK: - Staggered Grid Layout

struct FeatureStaggeredGrid: View {
    let features: [FeatureGridItem]
    let columns: Int
    let spacing: CGFloat
    let borderWidth: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<columns, id: \.self) { columnIndex in
                VStack(alignment: .leading, spacing: spacing) {
                    ForEach(columnFeatures(for: columnIndex)) { feature in
                        FeatureCardView(feature: feature, minHeight: nil, borderWidth: borderWidth)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func columnFeatures(for columnIndex: Int) -> [FeatureGridItem] {
        var columnItems: [FeatureGridItem] = []
        for (index, feature) in features.enumerated() where index % columns == columnIndex {
            columnItems.append(feature)
        }
        return columnItems
    }
}

// MARK: - Fixed Grid Layout

struct FeatureFixedGrid: View {
    let features: [FeatureGridItem]
    let columns: Int
    let spacing: CGFloat
    let cellMinHeight: CGFloat
    let borderWidth: CGFloat

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 0, maximum: .infinity),
                                 spacing: spacing,
                                 alignment: .top),
              count: columns)
    }

    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: spacing) {
            ForEach(features) { feature in
                FeatureCardView(feature: feature, minHeight: cellMinHeight, borderWidth: borderWidth)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
