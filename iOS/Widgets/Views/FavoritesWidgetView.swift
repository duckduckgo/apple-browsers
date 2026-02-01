//
//  FavoritesWidgetView.swift
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
import WidgetKit
import DesignResourcesKit
import DesignResourcesKitIcons

struct FavoritesWidgetView: View {

    @Environment(\.widgetFamily) var widgetFamily

    var entry: Provider.Entry

    @ViewBuilder
    func addFavoritesPrompt() -> some View {
        VStack(spacing: 4) {
            Text(UserText.noFavoritesMessage)
                .daxSubheadRegular()
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(designSystemColor: .textSecondary))
                .padding(.horizontal)
                .accessibilityHidden(true)
                .makeAccentable()

            Text(UserText.noFavoritesCTA)
                .daxSubheadSemibold()
                .foregroundColor(Color(designSystemColor: .accent))
                .makeAccentable()
        }
    }

    var body: some View {
        DesignSystemWidgetContainerView {
            VStack(spacing: 0) {
                ResponsiveSearchFieldView(isAIChatEnabled: entry.isAIChatEnabled, showLogo: true, isRightIconEnabled: true)
                    .padding(.bottom, 16)

                if entry.favorites.isEmpty, !entry.isPreview {
                    // The whole thing needs to be a link because the user could click anywhere
                    VStack {
                        Link(destination: DeepLinks.addFavorite) {
                            addFavoritesPrompt()
                        }
                        .padding(0)
                        Spacer()
                    }
                    .padding(0)
                    .padding(.top, 8)
                    .frame(maxHeight: .infinity)
                } else {
                    FavoritesGridView(entry: entry)
                        .frame(maxHeight: .infinity)
                }
            }
            .padding(0)
        }
    }
}

struct FavoriteView: View {

    var favorite: Favorite?
    var isPreview: Bool

    private let cornerRadius: CGFloat = 16

    var body: some View {

        ZStack {
            if isPreview {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .renderAwareBackgroundFill(Color(designSystemColor: .surface))
            }

            if let favorite = favorite {

                Link(destination: DeepLinks.openFavorite(withId: favorite.id)) {
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .renderAwareBackgroundFill(favorite.needsColorBackground ? Color.forDomain(favorite.domain) : Color(designSystemColor: .surface))
                            .makeAccentable()
                            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)

                        if let image = favorite.favicon {
                            if image.size.width > 60 {
                                Image(uiImage: image)
                                    .resizable()
                                    .useFullColorRendering()
                                    .aspectRatio(contentMode: .fit)
                                    .cornerRadius(cornerRadius)
                            } else {
                                Image(uiImage: image)
                                    .useFullColorRendering()
                                    .cornerRadius(10)
                            }

                        } else if favorite.isDuckDuckGo {
                            Image(uiImage: UIImage(resource: .widgetDaxLogo))
                                .resizable()
                                .useFullColorRendering()
                                .frame(width: 46, height: 46, alignment: .center)
                                .isHidden(false)
                                .accessibilityHidden(true)

                        } else {
                            Text(favorite.domain.first?.uppercased() ?? "")
                                .foregroundColor(Color.white)
                                .font(.system(size: 42))

                        }
                    }
                }
                .accessibilityLabel(Text(favorite.title))
            }
        }
        .frame(width: 60, height: 60, alignment: .center)
    }
}

struct FavoritesRowView: View {
    var entry: Provider.Entry
    var start: Int
    var end: Int

    var body: some View {
        HStack {
            ForEach(start...end, id: \.self) {
                FavoriteView(favorite: entry.favoriteAt(index: $0), isPreview: entry.isPreview)

                if $0 < end {
                    Spacer()
                }

            }
        }
    }
}

struct FavoritesGridView: View {

    @Environment(\.widgetFamily) var widgetFamily

    var entry: Provider.Entry

    var body: some View {

        VStack(spacing: 24) {

            FavoritesRowView(entry: entry, start: 0, end: 3)

            if widgetFamily == .systemLarge {

                FavoritesRowView(entry: entry, start: 4, end: 7)

                FavoritesRowView(entry: entry, start: 8, end: 11)
            }

        }

    }

}
