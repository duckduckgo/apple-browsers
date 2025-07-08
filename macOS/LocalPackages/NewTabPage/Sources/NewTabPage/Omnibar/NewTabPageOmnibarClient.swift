//
//  NewTabPageOmnibarClient.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import WebKit
import Common

public final class NewTabPageOmnibarClient: NewTabPageUserScriptClient {

    enum MessageName: String, CaseIterable {
        case getConfig = "omnibar_getConfig"
        case getSuggestions = "omnibar_getSuggestions"
    }

    private let model: NewTabPageOmnibarModel

    public init(model: NewTabPageOmnibarModel) {
        self.model = model
        super.init()
    }

    public override func registerMessageHandlers(for userScript: NewTabPageUserScript) {
        userScript.registerMessageHandlers([
            MessageName.getConfig.rawValue: { [weak self] in try await self?.getConfig(params: $0, original: $1) },
            MessageName.getSuggestions.rawValue: { [weak self] in try await self?.getSuggestions(params: $0, original: $1) }
        ])
    }

    private func getConfig(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        // In future, the mode will be stored locally and provided in initial configuration below
        let mode = NewTabPageDataModel.OmnibarMode.search
        return NewTabPageDataModel.OmnibarConfig(mode: mode)
    }

    private func getSuggestions(params: Any, original: WKScriptMessage) async throws -> Encodable? {
        guard let request: NewTabPageDataModel.OmnibarGetSuggestionsRequest = DecodableHelper.decode(from: params) else {
            return nil
        }
        return NewTabPageDataModel.SuggestionsData(suggestions: NewTabPageDataModel.Suggestions(topHits: [], duckduckgoSuggestions: [], localSuggestions: []))// await model.searchSuggestionsProvider.suggestions(for: request.term))
    }
}
