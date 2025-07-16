//
//  MockNewTabPageOmnibarActionsHandler.swift
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

import NewTabPage

final class MockNewTabPageOmnibarActionsHandler: NewTabPageOmnibarActionsHandling {

    var submitSearchHandler: ((String, NewTabPageDataModel.OpenTarget) -> Void)?
    var openSuggestionHandler: ((NewTabPageDataModel.Suggestion, NewTabPageDataModel.OpenTarget) -> Void)?
    var submitChatHandler: ((String, NewTabPageDataModel.OpenTarget) -> Void)?

    @MainActor
    func submitSearch(_ term: String, target: NewTabPageDataModel.OpenTarget) {
        submitSearchHandler?(term, target)
    }

    @MainActor
    func openSuggestion(_ suggestion: NewTabPageDataModel.Suggestion, target: NewTabPageDataModel.OpenTarget) {
        openSuggestionHandler?(suggestion, target)
    }

    @MainActor
    func submitChat(_ chat: String, target: NewTabPageDataModel.OpenTarget) {
        submitChatHandler?(chat, target)
    }
}
