//
//  DuckAIModelPickStore.swift
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

import AIChat
import Combine
import Foundation

/// A model and reasoning effort picked in one input. `nil` fields fall back to the new-chat default.
struct DuckAIModelPick: Equatable {
    var modelId: String?
    var modelShortName: String?
    var reasoningEffort: String?

    static let empty = DuckAIModelPick()
}

/// Where a Duck.ai input keeps the user's model and reasoning-effort pick.
protocol DuckAIModelPickStoring: AnyObject {
    var modelId: String? { get set }
    var modelShortName: String? { get set }
    /// Raw `AIChatReasoningEffort` value; may hold a value the app no longer knows.
    var reasoningEffort: String? { get set }
}

/// A pick store an input follows through publishers, as the New Tab Page does.
protocol DuckAIPublishingModelPickStoring: DuckAIModelPickStoring {
    var modelIdPublisher: AnyPublisher<String?, Never> { get }
    var reasoningEffortPublisher: AnyPublisher<String?, Never> { get }
}

/// One pick shared by every input and kept across launches.
final class PersistedModelPickStore: DuckAIPublishingModelPickStoring {

    private var preferences: AIChatPreferencesPersisting

    init(preferences: AIChatPreferencesPersisting) {
        self.preferences = preferences
    }

    var modelId: String? {
        get { preferences.selectedModelId }
        set { preferences.selectedModelId = newValue }
    }

    var modelShortName: String? {
        get { preferences.selectedModelShortName }
        set { preferences.selectedModelShortName = newValue }
    }

    var reasoningEffort: String? {
        get { preferences.selectedReasoningEffort }
        set { preferences.selectedReasoningEffort = newValue }
    }

    var modelIdPublisher: AnyPublisher<String?, Never> {
        preferences.selectedModelIdPublisher
    }

    var reasoningEffortPublisher: AnyPublisher<String?, Never> {
        preferences.selectedReasoningEffortPublisher
    }
}

/// For a page that keeps each tab's pick itself: native keeps none, so reads fall back to the new-chat default.
final class WebKeptModelPickStore: DuckAIPublishingModelPickStoring {

    var modelId: String? {
        get { nil }
        set {}
    }

    var modelShortName: String? {
        get { nil }
        set {}
    }

    var reasoningEffort: String? {
        get { nil }
        set {}
    }

    var modelIdPublisher: AnyPublisher<String?, Never> {
        Empty().eraseToAnyPublisher()
    }

    var reasoningEffortPublisher: AnyPublisher<String?, Never> {
        Empty().eraseToAnyPublisher()
    }
}

/// The pick lives on the draft currently in effect, so it stays on its tab (or Prompt Bar) and resets with the draft.
final class DraftModelPickStore: DuckAIModelPickStoring {

    private let currentDraftStore: () -> DuckAIPromptDraftStoring?

    init(currentDraftStore: @escaping () -> DuckAIPromptDraftStoring?) {
        self.currentDraftStore = currentDraftStore
    }

    var modelId: String? {
        get { currentDraftStore()?.aiChatModelPick.modelId }
        set { updatePick { $0.modelId = newValue } }
    }

    var modelShortName: String? {
        get { currentDraftStore()?.aiChatModelPick.modelShortName }
        set { updatePick { $0.modelShortName = newValue } }
    }

    var reasoningEffort: String? {
        get { currentDraftStore()?.aiChatModelPick.reasoningEffort }
        set { updatePick { $0.reasoningEffort = newValue } }
    }

    private func updatePick(_ change: (inout DuckAIModelPick) -> Void) {
        guard let draftStore = currentDraftStore() else { return }
        var pick = draftStore.aiChatModelPick
        change(&pick)
        draftStore.setAIChatModelPick(pick)
    }
}
