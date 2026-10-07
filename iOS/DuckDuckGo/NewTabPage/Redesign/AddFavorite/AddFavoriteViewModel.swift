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
import Common
import Foundation
import FoundationExtensions

@MainActor
final class AddFavoriteViewModel: ObservableObject {
    @Published var name = ""
    @Published var urlText = "" {
        didSet { validatedURL = validateURL(urlText) }
    }
    var onSave: (() -> Void)?

    private var validatedURL: URL?
    private let bookmarks: MenuBookmarksInteracting
    private let useUnifiedURLLogic: Bool

    init(bookmarks: MenuBookmarksInteracting, useUnifiedURLLogic: Bool) {
        self.bookmarks = bookmarks
        self.useUnifiedURLLogic = useUnifiedURLLogic
    }

    var canSave: Bool { validatedURL != nil }

    func save() -> Bool {
        guard let url = validatedURL else { return false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard bookmarks.saveFavorite(title: trimmedName.isEmpty ? nil : trimmedName, url: url) else { return false }
        onSave?()
        return true
    }

    private func validateURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Preserve explicit schemes, including the omnibar's single-slash normalization.
        // A domain followed by a port is not an explicit scheme.
        let hasScheme = trimmed.range(of: "^[a-zA-Z][a-zA-Z0-9+.-]*:/", options: .regularExpression) != nil
        // Validate the typed input before applying our HTTPS default. Adding a scheme first
        // would make bare words look like explicitly entered local hostnames.
        guard let url = URL(trimmedAddressBarString: trimmed, useUnifiedLogic: useUnifiedURLLogic),
              url.isValid(usingUnifiedLogic: useUnifiedURLLogic),
              URL.NavigationalScheme.hypertextSchemes.contains(.init(rawValue: url.scheme?.lowercased() ?? "")),
              let host = url.host,
              host.isValidHost,
              host.split(separator: ".").allSatisfy({ !$0.hasPrefix("-") && !$0.hasSuffix("-") }) else { return nil }
        return hasScheme ? url : url.replacing(scheme: URL.NavigationalScheme.https.rawValue)
    }
}
