//
//  NewTabPageOmnibarActionsHandling.swift
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

public protocol NewTabPageOmnibarActionsHandling: AnyObject {

    @MainActor
    func submitSearch(_ term: String, target: NewTabPageDataModel.OpenTarget)

    @MainActor
    func openSuggestion(_ suggestion: NewTabPageDataModel.Suggestion, target: NewTabPageDataModel.OpenTarget)

    @MainActor
    func submitChat(_ chat: String,
                    target: NewTabPageDataModel.OpenTarget,
                    modelId: String?,
                    images: [NewTabPageDataModel.SubmitChatImage]?,
                    mode: String?,
                    toolChoice: [String]?,
                    reasoningEffort: String?,
                    pageContexts: [NewTabPageDataModel.OmnibarPageContext]?,
                    files: [NewTabPageDataModel.OmnibarPromptFile]?)

    @MainActor
    func openAiChat(_ chatId: String, isPinned: Bool, trigger: NewTabPageDataModel.OpenAiChatTrigger, target: NewTabPageDataModel.OpenTarget)

    @MainActor
    func viewAllAiChats(target: NewTabPageDataModel.OpenTarget)

    /// Opens the Duck.ai Customize Responses modal from the NTP omnibar Tools menu.
    @MainActor
    func openCustomizeResponses()

    /// Persists whether the stored response customization is applied (from the row's toggle).
    @MainActor
    func setCustomizeResponsesActive(_ active: Bool)

}
