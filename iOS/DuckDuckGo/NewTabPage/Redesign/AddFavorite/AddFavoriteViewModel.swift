//
//  AddFavoriteViewModel.swift
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

import Bookmarks
import Combine
import Core
import Foundation
import PixelKit

@MainActor
final class AddFavoriteViewModel: ObservableObject {
    @Published var name = ""
    @Published var urlText = ""
    var onSave: (() -> Void)?

    private var normalizedURLText: String? {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.isBookmarklet() {
            return BookmarkUtils.url(from: trimmed) == nil ? nil : trimmed
        }
        guard trimmed.contains("://") else {
            return Self.secureWebURL(fromSchemeLessText: trimmed)?.absoluteString
        }
        if let webURL = URL.webUrl(from: trimmed) {
            return webURL.absoluteString
        }
        // Explicit non-web schemes (e.g. ftp or app deep links) are kept as typed.
        return URL(string: trimmed) != nil ? trimmed : nil
    }

    /// Prefixes `https://` rather than relying on `URL.webUrl`, which reads `host:port` input as a URL scheme.
    private static func secureWebURL(fromSchemeLessText text: String) -> URL? {
        guard let url = URL.webUrl(from: "https://" + text),
              let host = url.host,
              host.contains(".") || host == "localhost" else { return nil }
        return url
    }
    private let bookmarks: MenuBookmarksInteracting
    private let pixelFiring: (any PixelKitFiring)?

    init(bookmarks: MenuBookmarksInteracting,
         pixelFiring: (any PixelKitFiring)? = PixelKit.shared) {
        self.bookmarks = bookmarks
        self.pixelFiring = pixelFiring
    }

    var canSave: Bool { normalizedURLText != nil }

    func save() -> Bool {
        guard let normalizedURLText else { return false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard bookmarks.saveFavorite(title: trimmedName.isEmpty ? nil : trimmedName, urlString: normalizedURLText) else { return false }
        pixelFiring?.fire(AddFavoritePixel.saved, frequency: .dailyAndCount)
        onSave?()
        return true
    }

    func reportOpening() {
        pixelFiring?.fire(AddFavoritePixel.opened, frequency: .dailyAndCount)
    }

}
