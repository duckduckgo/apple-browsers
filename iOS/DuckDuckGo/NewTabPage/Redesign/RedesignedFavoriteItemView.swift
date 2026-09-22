//
//  RedesignedFavoriteItemView.swift
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
import UIComponents

struct RedesignedFavoriteItemView: View {
    let favorite: Favorite
    let faviconLoading: FavoritesFaviconLoading?
    let isEditable: Bool
    let onMenuAction: ((MenuAction) -> Void)?

    var body: some View {
        VStack(spacing: 6) {
            RedesignedFavoriteIconView(favorite: favorite, faviconLoading: faviconLoading)
                .if(isEditable) {
                    $0.contextMenu {
                        // This context menu can be moved up in the hierarchy to `FavoritesView` once support for iOS 15 is removed. contextMenu with preview modifier can be used then.
                        contextMenuItems()
                    }
                }

            Text(favorite.title)
                .font(Font.system(size: 12))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundColor(Color(designSystemColor: .textPrimary))
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(favorite.title). \(UserText.favorite)")
    }

    private func contextMenuItems() -> some View {
        Section(favorite.menuTitle) {
            Button {
                onMenuAction?(.edit)
            } label: {
                Label {
                    Text(UserText.favoriteMenuEdit)
                } icon: {
                    Image(uiImage: DesignSystemImages.Glyphs.Size24.edit)
                }
            }

            Button {
                onMenuAction?(.delete)
            } label: {
                Label {
                    Text(UserText.favoriteMenuRemove)
                } icon: {
                    Image(uiImage: DesignSystemImages.Glyphs.Size24.favoriteRemove)
                }
            }
        }
    }
}

extension RedesignedFavoriteItemView {
    enum MenuAction {
        case edit
        case delete
    }
}

/// Keeps the favicon inside a circular tile without cropping the site's artwork.
struct RedesignedFavoriteIconView: View {
    let favorite: Favorite
    let faviconLoading: FavoritesFaviconLoading?

    var body: some View {
        FavoriteIconView(favorite: favorite, faviconLoading: faviconLoading)
            .frame(width: 64, height: 64)
            .scaleEffect(0.5)
            .frame(width: 32, height: 32)
            .frame(width: 48, height: 48)
            .background(Circle().fill(Color(designSystemColor: .controlsFillPrimary)))
            .contentShape(Circle())
    }
}
