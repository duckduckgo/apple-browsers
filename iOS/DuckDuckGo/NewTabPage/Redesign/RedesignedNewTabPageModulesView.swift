//
//  RedesignedNewTabPageModulesView.swift
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

import SwiftUI

/// Shared module arrangement. Each presentation owns its scrolling and supplies existing models.
struct RedesignedNewTabPageModulesView: View {
    let favoritesModel: FavoritesViewModel?
    let onAddFavorite: (() -> Void)?
    private let customizationStore: NewTabPageCustomizationStore
    @State private var isFavoritesSectionVisible: Bool

    init(favoritesModel: FavoritesViewModel?,
         onAddFavorite: (() -> Void)? = nil,
         customizationStore: NewTabPageCustomizationStore = NewTabPageCustomizationStore()) {
        self.favoritesModel = favoritesModel
        self.onAddFavorite = onAddFavorite
        self.customizationStore = customizationStore
        _isFavoritesSectionVisible = State(initialValue: customizationStore.isFavoritesSectionVisible)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.moduleSpacing) {
            if isFavoritesSectionVisible, let favoritesModel {
                RedesignedFavoritesView(model: favoritesModel, onAddFavorite: onAddFavorite)
                    .padding(.horizontal, Metrics.horizontalPadding)
                    .padding(.bottom, Metrics.bottomPadding)
            }
        }
        // This is the input-to-modules gap, even when the first visible module is the escape hatch.
        .padding(.top, Metrics.topPadding)
        .onReceive(customizationStore.favoritesVisibilityPublisher.receive(on: DispatchQueue.main)) { isVisible in
            isFavoritesSectionVisible = isVisible
        }
    }
}

private enum Metrics {
    static let moduleSpacing: CGFloat = 28
    static let horizontalPadding: CGFloat = 16
    static let topPadding: CGFloat = 20
    static let bottomPadding: CGFloat = 16
}
