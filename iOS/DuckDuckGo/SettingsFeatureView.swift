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
        VStack(alignment: .leading, spacing: 12) {
            // Icon at the top
            HStack {
                iconPlaceholder
                Spacer()
            }
            
            // Text content below the icon
            VStack(alignment: .leading, spacing: 6) {
                Text(feature.title)
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundColor(Color(designSystemColor: .textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(feature.description)
                    .font(.caption)
                    .foregroundColor(Color(designSystemColor: .textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
            }
            
            if let minHeight = minHeight {
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .frame(minHeight: minHeight, maxHeight: minHeight != nil ? .infinity : nil)
        .background(Color(designSystemColor: .surface))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(designSystemColor: .lines), lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private var iconPlaceholder: some View {
        // Circle with same background as box and custom or fallback icon
        Circle()
            .fill(Color(designSystemColor: .surface))
            .frame(width: 32, height: 32)
            .overlay(
                Circle()
                    .stroke(Color(designSystemColor: .lines), lineWidth: 1)
            )
            .overlay(
                Group {
                    if let iconImage = feature.iconImage {
                        Image(uiImage: iconImage)
                            .resizable()
                            .renderingMode(.template)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 16, height: 16)
                            .foregroundColor(Color(designSystemColor: .textPrimary))
                    } else if let iconName = feature.iconName {
                        Image(iconName)
                            .resizable()
                            .renderingMode(.template)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 16, height: 16)
                            .foregroundColor(Color(designSystemColor: .textPrimary))
                    }
                }
            )
    }
}

/// Collection view for displaying multiple settings features in a custom staggered layout
struct SettingsFeatureGridView: View {
    let features: [SettingsFeature]
    let columns: Int
    let cellMinHeight: CGFloat?
    
    init(features: [SettingsFeature], columns: Int = 2, cellMinHeight: CGFloat? = nil) {
        self.features = features
        self.columns = columns
        self.cellMinHeight = cellMinHeight
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Create rows of uneven columns to match the organic layout
            ForEach(Array(stride(from: 0, to: features.count, by: 2)), id: \.self) { rowIndex in
                HStack(alignment: .top, spacing: 12) {
                    // First item in row
                    if rowIndex < features.count {
                        SettingsFeatureView(feature: features[rowIndex], minHeight: cellMinHeight)
                            .frame(maxWidth: .infinity)
                    }
                    
                    // Second item in row (if exists)
                    if rowIndex + 1 < features.count {
                        SettingsFeatureView(feature: features[rowIndex + 1], minHeight: cellMinHeight)
                            .frame(maxWidth: .infinity)
                    } else {
                        // Empty spacer if odd number of items
                        Spacer()
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }
}

/// Masonry-style staggered grid layout for settings features
struct SettingsFeatureMasonryView: View {
    let features: [SettingsFeature]
    let columns: Int
    let spacing: CGFloat
    
    init(features: [SettingsFeature], columns: Int = 2, spacing: CGFloat = 12) {
        self.features = features
        self.columns = columns
        self.spacing = spacing
    }
    
    var body: some View {
        VStack(spacing: 0) {
            createMasonryLayout()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
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

/// Alternative masonry layout using SwiftUI's built-in LazyVGrid with adaptive columns
struct SettingsFeatureAdaptiveGridView: View {
    let features: [SettingsFeature]
    let minColumnWidth: CGFloat
    let spacing: CGFloat
    
    init(features: [SettingsFeature], minColumnWidth: CGFloat = 150, spacing: CGFloat = 12) {
        self.features = features
        self.minColumnWidth = minColumnWidth
        self.spacing = spacing
    }
    
    var body: some View {
        let columns = [
            GridItem(.adaptive(minimum: minColumnWidth), spacing: spacing, alignment: .top)
        ]
        
        LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
            ForEach(features) { feature in
                SettingsFeatureView(feature: feature, minHeight: nil)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }
}
