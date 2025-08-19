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
        VStack(alignment: .leading, spacing: 12) {
            // Icon at the top
            HStack {
                iconPlaceholder
                Spacer()
            }

            // Text content below the icon
            VStack(alignment: .leading, spacing: 6) {
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
        .padding(12)
        .frame(minHeight: minHeight, maxHeight: .infinity)
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
                        Image(nsImage: iconImage)
                            .resizable()
                            .renderingMode(.template)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 16, height: 16)
                            .foregroundColor(Color(designSystemColor: .textPrimary))
                    } else if let iconName = feature.iconName {
                        Image(iconName, bundle: .main)
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

/// Collection view for displaying multiple settings features in a grid layout
struct PreferencesFeatureGridView: View {
    let features: [PreferencesFeature]
    let columns: Int
    let cellMinHeight: CGFloat?

    init(features: [PreferencesFeature], columns: Int = 2, cellMinHeight: CGFloat? = nil) {
        self.features = features
        self.columns = columns
        self.cellMinHeight = cellMinHeight
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 12, alignment: .top), count: columns)
    }

    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: 12) {
            ForEach(features) { feature in
                PreferencesFeatureView(feature: feature, minHeight: cellMinHeight)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }
}
