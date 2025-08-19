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

private enum LayoutConstants {
    static let contentSpacing: CGFloat = 12
    static let textSpacing: CGFloat = 6
    static let cardPadding: CGFloat = 12
    static let cornerRadius: CGFloat = 8
    static let borderWidth: CGFloat = 1
    
    static let iconContainerSize: CGFloat = 32
    static let iconSize: CGFloat = 16
    
    static let defaultColumns: Int = 2
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
        VStack(alignment: .leading, spacing: LayoutConstants.contentSpacing) {
            // Icon at the top
            HStack {
                iconPlaceholder
                Spacer()
            }

            // Text content below the icon
            VStack(alignment: .leading, spacing: LayoutConstants.textSpacing) {
                Text(feature.title)
                    .daxTitle3()
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .fixedSize(horizontal: false, vertical: true)

                Text(feature.description)
                    .daxBody()
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(nil)
            }

            Spacer(minLength: 0)
        }
        .padding(LayoutConstants.cardPadding)
        .frame(minHeight: minHeight, maxHeight: .infinity)
        .background(Color(designSystemColor: .surface))
        .cornerRadius(LayoutConstants.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: LayoutConstants.cornerRadius)
                .stroke(Color(designSystemColor: .lines), lineWidth: LayoutConstants.borderWidth)
        )
    }

    @ViewBuilder
    private var iconPlaceholder: some View {
        // Circle with same background as box and custom or fallback icon
        Circle()
            .fill(Color(designSystemColor: .surface))
            .frame(width: LayoutConstants.iconContainerSize, height: LayoutConstants.iconContainerSize)
            .overlay(
                Circle()
                    .stroke(Color(designSystemColor: .lines), lineWidth: LayoutConstants.borderWidth)
            )
            .overlay(
                Group {
                    if let iconImage = feature.iconImage {
                        Image(nsImage: iconImage)
                            .resizable()
                            .renderingMode(.template)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: LayoutConstants.iconSize, height: LayoutConstants.iconSize)
                            .foregroundColor(Color(designSystemColor: .textPrimary))
                    } else if let iconName = feature.iconName {
                        Image(iconName, bundle: .main)
                            .resizable()
                            .renderingMode(.template)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: LayoutConstants.iconSize, height: LayoutConstants.iconSize)
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

    init(features: [PreferencesFeature], columns: Int = LayoutConstants.defaultColumns, cellMinHeight: CGFloat? = nil) {
        self.features = features
        self.columns = columns
        self.cellMinHeight = cellMinHeight
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: LayoutConstants.contentSpacing, alignment: .top), count: columns)
    }

    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: LayoutConstants.contentSpacing) {
            ForEach(features) { feature in
                PreferencesFeatureView(feature: feature, minHeight: cellMinHeight)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, LayoutConstants.contentSpacing)
    }
}
