//
//  WidgetPreviews.swift
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

struct WidgetViews_Previews: PreviewProvider {

    static let mockFavorites: [Favorite] = {
        let duckDuckGoFavorite = Favorite(url: URL(string: "https://duckduckgo.com/")!,
                                          domain: "duckduckgo.com",
                                          title: "title",
                                          favicon: nil)

        let favorites = "abcdefghijk".map {
            Favorite(url: URL(string: "https://\($0).com/")!, domain: "\($0).com", title: "title", favicon: nil)
        }

        return [duckDuckGoFavorite] + favorites
    }()

    static let withFavorites = FavoritesEntry(date: Date(), favorites: mockFavorites, isPreview: false, isAiChatEnabled: true)
    static let previewWithFavorites = FavoritesEntry(date: Date(), favorites: mockFavorites, isPreview: true, isAiChatEnabled: true)
    static let emptyState = FavoritesEntry(date: Date(), favorites: [], isPreview: false, isAiChatEnabled: true)
    static let previewEmptyState = FavoritesEntry(date: Date(), favorites: [], isPreview: true, isAiChatEnabled: true)

    static var previews: some View {
        SearchWidgetView(entry: emptyState)
            .previewContext(WidgetPreviewContext(family: .systemSmall))
            .environment(\.colorScheme, .light)

        SearchWidgetView(entry: emptyState)
            .previewContext(WidgetPreviewContext(family: .systemSmall))
            .environment(\.colorScheme, .dark)

        PasswordsWidgetView(entry: emptyState)
            .previewContext(WidgetPreviewContext(family: .systemSmall))
            .environment(\.colorScheme, .light)

        PasswordsWidgetView(entry: emptyState)
            .previewContext(WidgetPreviewContext(family: .systemSmall))
            .environment(\.colorScheme, .dark)

        // Medium size:

        FavoritesWidgetView(entry: previewWithFavorites)
            .previewContext(WidgetPreviewContext(family: .systemMedium))
            .environment(\.colorScheme, .light)

        FavoritesWidgetView(entry: withFavorites)
            .previewContext(WidgetPreviewContext(family: .systemMedium))
            .environment(\.colorScheme, .light)

        FavoritesWidgetView(entry: previewEmptyState)
            .previewContext(WidgetPreviewContext(family: .systemMedium))
            .environment(\.colorScheme, .dark)

        FavoritesWidgetView(entry: emptyState)
            .previewContext(WidgetPreviewContext(family: .systemMedium))
            .environment(\.colorScheme, .dark)

        // Large size:

        FavoritesWidgetView(entry: previewWithFavorites)
            .previewContext(WidgetPreviewContext(family: .systemLarge))
            .environment(\.colorScheme, .light)

        FavoritesWidgetView(entry: withFavorites)
            .previewContext(WidgetPreviewContext(family: .systemLarge))
            .environment(\.colorScheme, .light)

        FavoritesWidgetView(entry: previewEmptyState)
            .previewContext(WidgetPreviewContext(family: .systemLarge))
            .environment(\.colorScheme, .dark)

        FavoritesWidgetView(entry: emptyState)
            .previewContext(WidgetPreviewContext(family: .systemLarge))
            .environment(\.colorScheme, .dark)
    }
}
