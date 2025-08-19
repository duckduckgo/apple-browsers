//
//  SettingsFeatureView.swift
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
    static let adaptiveMinColumnWidth: CGFloat = 150
}

/// Model representing a settings feature for display in feature boxes
struct SettingsFeature: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let iconName: String?
    let iconImage: UIImage?
    
    init(title: String, description: String, iconName: String? = nil, iconImage: UIImage? = nil) {
        self.title = title
        self.description = description
        self.iconName = iconName
        self.iconImage = iconImage ?? (iconName.flatMap { UIImage(named: $0) })
    }
}

/// Reusable component for displaying a single settings feature box
struct SettingsFeatureView: View {
    let feature: SettingsFeature
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
                    .daxFootnoteSemibold()
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(feature.description)
                    .daxFootnoteRegular()
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
            }
            
            if let minHeight = minHeight {
                Spacer(minLength: 0)
            }
        }
        .padding(LayoutConstants.cardPadding)
        .frame(minHeight: minHeight, maxHeight: minHeight != nil ? .infinity : nil)
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
                        Image(uiImage: iconImage)
                            .resizable()
                            .renderingMode(.template)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: LayoutConstants.iconSize, height: LayoutConstants.iconSize)
                            .foregroundColor(Color(designSystemColor: .textPrimary))
                    } else if let iconName = feature.iconName {
                        Image(iconName)
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


/// Masonry-style staggered grid layout for settings features
struct SettingsFeatureMasonryView: View {
    let features: [SettingsFeature]
    let columns: Int
    let spacing: CGFloat
    
    init(features: [SettingsFeature], columns: Int = LayoutConstants.defaultColumns, spacing: CGFloat = LayoutConstants.contentSpacing) {
        self.features = features
        self.columns = columns
        self.spacing = spacing
    }
    
    var body: some View {
        VStack(spacing: 0) {
            createMasonryLayout()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, LayoutConstants.contentSpacing)
    }
    
    @ViewBuilder
    private func createMasonryLayout() -> some View {
        // Split features into columns for masonry effect
        let columnArrays = distributeIntoColumns()
        
        HStack(alignment: .top, spacing: spacing) {
            ForEach(0..<columns, id: \.self) { columnIndex in
                VStack(alignment: .leading, spacing: spacing) {
                    ForEach(columnArrays[columnIndex].indices, id: \.self) { itemIndex in
                        SettingsFeatureView(
                            feature: columnArrays[columnIndex][itemIndex],
                            minHeight: nil
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    // Distribute features into columns trying to balance heights
    private func distributeIntoColumns() -> [[SettingsFeature]] {
        var columnArrays: [[SettingsFeature]] = Array(repeating: [], count: columns)

        // Simple round-robin distribution that creates a staggered effect
        for (index, feature) in features.enumerated() {
            let columnIndex = index % columns
            columnArrays[columnIndex].append(feature)
        }

        return columnArrays
    }
}
