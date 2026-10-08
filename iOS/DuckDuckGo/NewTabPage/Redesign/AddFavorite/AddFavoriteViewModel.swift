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
import Foundation

@MainActor
final class AddFavoriteViewModel: ObservableObject {
    @Published var name = ""
    @Published var urlText = ""
    var onSave: (() -> Void)?

    private var validatedURL: URL? {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : BookmarkUtils.url(from: trimmed)
    }
    private let bookmarks: MenuBookmarksInteracting

    init(bookmarks: MenuBookmarksInteracting) {
        self.bookmarks = bookmarks
    }

    var canSave: Bool { validatedURL != nil }

    func save() -> Bool {
        guard canSave else { return false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard bookmarks.saveFavorite(title: trimmedName.isEmpty ? nil : trimmedName, urlString: trimmedURL) else { return false }
        onSave?()
        return true
    }

}
