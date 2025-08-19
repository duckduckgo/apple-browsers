//
//  PreferencesFeatureView.swift
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

private enum Layout {
    enum Spacing {
        static let vertical: CGFloat = 12
        static let textVertical: CGFloat = 6
        static let gridCell: CGFloat = 12
    }

    enum Padding {
        static let featureBox: CGFloat = 12
        static let gridTop: CGFloat = 12
    }

    enum Size {
        static let iconCircle: CGFloat = 32
        static let iconImage: CGFloat = 16
    }

    enum BorderStyle {
        static let cornerRadius: CGFloat = 8
        static let lineWidth: CGFloat = 1
    }

    enum Grid {
        static let defaultColumns: Int = 2
        static let defaultCellMinHeight: CGFloat = 90
    }
}

/// Model representing a settings feature for display in feature boxes
struct PreferencesFeature: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let iconName: String?
    let iconImage: NSImage?

    init(title: String, description: String, iconName: String? = nil, iconImage: NSImage? = nil) {
        self.title = title
        self.description = description
        self.iconName = iconName
        self.iconImage = iconImage ?? (iconName.flatMap { NSImage(named: $0) })
    }
}

/// Reusable component for displaying a single settings feature box
struct PreferencesFeatureView: View {
    let feature: PreferencesFeature
    let minHeight: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.Spacing.vertical) {
            // Icon at the top
            HStack {
                iconPlaceholder
                Spacer()
            }

            // Text content below the icon
            VStack(alignment: .leading, spacing: Layout.Spacing.textVertical) {
                Text(feature.title)
                    .font(.title3)
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .fixedSize(horizontal: false, vertical: true)

                Text(feature.description)
                    .font(.body)
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(nil)
            }

            Spacer(minLength: 0)
        }
        .padding(Layout.Padding.featureBox)
        .frame(minHeight: minHeight, maxHeight: .infinity)
        .background(Color(designSystemColor: .surface))
        .cornerRadius(Layout.BorderStyle.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: Layout.BorderStyle.cornerRadius)
                .stroke(Color(designSystemColor: .lines), lineWidth: Layout.BorderStyle.lineWidth)
        )
    }

    @ViewBuilder
    private var iconPlaceholder: some View {
        // Circle with same background as box and custom or fallback icon
        Circle()
            .fill(Color(designSystemColor: .surface))
            .frame(width: Layout.Size.iconCircle, height: Layout.Size.iconCircle)
            .overlay(
                Circle()
                    .stroke(Color(designSystemColor: .lines), lineWidth: Layout.BorderStyle.lineWidth)
            )
            .overlay(
                Group {
                    if let iconImage = feature.iconImage {
                        Image(nsImage: iconImage)
                            .resizable()
                            .renderingMode(.template)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: Layout.Size.iconImage, height: Layout.Size.iconImage)
                            .foregroundColor(Color(designSystemColor: .textPrimary))
                    } else if let iconName = feature.iconName {
                        Image(iconName, bundle: .main)
                            .resizable()
                            .renderingMode(.template)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: Layout.Size.iconImage, height: Layout.Size.iconImage)
                            .foregroundColor(Color(designSystemColor: .textPrimary))
                    }
                }
            )
    }
}

/// Collection view for displaying multiple settings features in a grid layout
struct PreferencesFeatureGridView: View {
    let features: [PreferencesFeature]
    let columns: Int
    let cellMinHeight: CGFloat?

    init(features: [PreferencesFeature], columns: Int = Layout.Grid.defaultColumns, cellMinHeight: CGFloat? = nil) {
        self.features = features
        self.columns = columns
        self.cellMinHeight = cellMinHeight
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: Layout.Spacing.gridCell, alignment: .top), count: columns)
    }

    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: Layout.Spacing.gridCell) {
            ForEach(features) { feature in
                PreferencesFeatureView(feature: feature, minHeight: cellMinHeight)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Layout.Padding.gridTop)
    }
}
