//
//  NewTabPageSearchClient.swift
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

import Combine
import Common
import os.log
import UserScriptActionsManager
import WebKit

public final class NewTabPageSearchClient: NewTabPageUserScriptClient {

    private let model: NewTabPageSearchModel
    private var cancellables: Set<AnyCancellable> = []

    enum MessageName: String, CaseIterable {
        case getSuggestions = "search_getSuggestions"
        case openSuggestion = "search_openSuggestion"
        case submit = "search_submit"
        case submitChat = "search_submitChat"
    }

    public init(model: NewTabPageSearchModel) {
        self.model = model
        super.init()
    }

    public override func registerMessageHandlers(for userScript: NewTabPageUserScript) {
        userScript.registerMessageHandlers([
            MessageName.getSuggestions.rawValue: { [weak self] in try await self?.getSuggestions(params: $0, original: $1) },
            MessageName.openSuggestion.rawValue: { [weak self] in try await self?.openSuggestion(params: $0, original: $1) },
            MessageName.submit.rawValue: { [weak self] in try await self?.submit(params: $0, original: $1) },
            MessageName.submitChat.rawValue: { [weak self] in try await self?.submitChat(params: $0, original: $1) }
        ])
    }

    @MainActor
    private func getSuggestions(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let request: NewTabPageDataModel.SearchGetSuggestionsRequest = DecodableHelper.decode(from: params) else {
            return nil
        }
        return NewTabPageDataModel.SuggestionsData(suggestions: await model.searchSuggestionsProvider.suggestions(for: request.term))
    }

    @MainActor
    private func openSuggestion(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let action: NewTabPageDataModel.SearchOpenSuggestion = DecodableHelper.decode(from: params) else {
            return nil
        }
        try await model.open(action.suggestion)
        return nil
    }

    @MainActor
    private func submit(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let action: NewTabPageDataModel.SearchSubmitParams = DecodableHelper.decode(from: params) else {
            return nil
        }
        try await model.open(.phrase(phrase: action.term))
        return nil
    }

    @MainActor
    private func submitChat(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let action: NewTabPageDataModel.AIChatSubmitParams = DecodableHelper.decode(from: params) else {
            return nil
        }
        try await model.open(action.chat)
        return nil
    }
}
