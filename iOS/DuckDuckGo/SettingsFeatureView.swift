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
import UIComponents

// Legacy wrapper - redirects to shared component in UIComponents package
typealias SettingsFeature = FeatureGridItem
typealias SettingsFeatureMasonryView = FeatureStaggeredGridWrapper
typealias SettingsFeatureGridView = FeatureFixedGridWrapper

// Wrapper for staggered grid to maintain compatibility
struct FeatureStaggeredGridWrapper: View {
    let features: [FeatureGridItem]
    let columns: Int
    let spacing: CGFloat
    
    init(features: [FeatureGridItem], columns: Int = 2, spacing: CGFloat = 12) {
        self.features = features
        self.columns = columns
        self.spacing = spacing
    }
    
    var body: some View {
        FeatureGridView(
            features: features,
            layoutStyle: .staggered,
            columns: columns,
            spacing: spacing
            // iOS uses default borderWidth of 0 (no border)
        )
    }
}

// Wrapper for fixed grid to maintain compatibility
struct FeatureFixedGridWrapper: View {
    let features: [FeatureGridItem]
    let columns: Int
    let cellMinHeight: CGFloat
    let spacing: CGFloat
    
    init(features: [FeatureGridItem], columns: Int = 2, cellMinHeight: CGFloat = 90, spacing: CGFloat = 12) {
        self.features = features
        self.columns = columns
        self.cellMinHeight = cellMinHeight
        self.spacing = spacing
    }
    
    var body: some View {
        FeatureGridView(
            features: features,
            layoutStyle: .fixed,
            columns: columns,
            spacing: spacing,
            cellMinHeight: cellMinHeight
            // iOS uses default borderWidth of 0 (no border)
        )
    }
}
