//
//  NewTabPageSearchModel.swift
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

import AppKit
import Combine
import Common
import Foundation
import os.log
import Persistence
import PrivacyStats

public protocol NewTabPageSearchSuggestionsProviding: AnyObject {
    @MainActor
    func suggestions(for term: String) async -> NewTabPageDataModel.Suggestions
}

public protocol NewTabPageSearchActionsHandling: AnyObject {
    @MainActor
    func open(_ suggestion: NewTabPageDataModel.Suggestion) async throws

    @MainActor
    func open(_ prompt: String) async throws
}

public final class NewTabPageSearchModel {

    let searchSuggestionsProvider: NewTabPageSearchSuggestionsProviding
    private let actionsHandler: NewTabPageSearchActionsHandling

    public init(searchSuggestionsProvider: NewTabPageSearchSuggestionsProviding,
                actionsHandler: NewTabPageSearchActionsHandling) {
        self.searchSuggestionsProvider = searchSuggestionsProvider
        self.actionsHandler = actionsHandler
    }

    // MARK: - Actions

    @MainActor
    public func open(_ suggestion: NewTabPageDataModel.Suggestion) async throws {
        try await actionsHandler.open(suggestion)
    }

    @MainActor
    public func open(_ prompt: String) async throws {
        try await actionsHandler.open(prompt)
    }
}

