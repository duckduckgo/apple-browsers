//
//  RedesignedFavoriteTileView.swift
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
import SwiftUI

/// Keeps favorite, expansion and Add Favorite tiles aligned on the same grid.
struct RedesignedFavoriteTileView<Icon: View>: View {
    let title: String
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        VStack(spacing: RedesignedFavoriteTileMetrics.iconToTitleSpacing) {
            icon()
            Text(title)
                .daxCaption()
                .lineLimit(RedesignedFavoriteTileMetrics.titleLineLimit)
                .truncationMode(.tail)
                .multilineTextAlignment(.center)
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .frame(maxWidth: .infinity, alignment: .top)
        }
    }
}

/// Layout values of `RedesignedFavoriteTileView`, shared with the grid's row height estimate.
enum RedesignedFavoriteTileMetrics {
    static let iconToTitleSpacing: CGFloat = 8
    static let titleLineLimit = 2
}
