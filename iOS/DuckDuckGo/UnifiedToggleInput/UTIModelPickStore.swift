//
//  UTIModelPickStore.swift
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

import AIChat

/// Where an input keeps the user's model and reasoning-mode picks; chosen once, when the input is built.
@MainActor
protocol UTIModelPickStoring: AnyObject {
    /// The model new chats start on when their tab has none; `nil` leaves it to the new-chat default.
    var newChatModelId: String? { get }
    var newChatModelShortName: String? { get }
    func saveNewChatModel(id: String?, shortName: String?)

    var reasoningMode: AIChatReasoningMode? { get set }

    /// The part of a tab's pick that seeds new tabs and is restored after a relaunch.
    func pickKeptBeyondTab(_ pick: UTIModelSelection) -> UTIModelSelection
    /// What a tab keeps of a new chat's selection: its own pick, or everything it shows.
    func newChatSelectionKeptOnTab(ownPick: UTIModelSelection, shown: UTIModelSelection) -> UTIModelSelection
    /// The pick a different chat on the tab starts on; `nil` keeps the current one.
    func pickForNewChat(openedWithModelId modelId: String?) -> UTIModelSelection?
}

/// With new chats on the default, picks stay on their tab; otherwise one pick is persisted for every tab.
@MainActor
func makeModelPickStore(startsNewChatsOnDefault: Bool, preferences: AIChatPreferencesPersisting) -> UTIModelPickStoring {
    startsNewChatsOnDefault ? TabModelPickStore() : PersistedModelPickStore(preferences: preferences)
}

/// One pick shared by every tab and kept across launches; new chats start on it.
@MainActor
final class PersistedModelPickStore: UTIModelPickStoring {

    private var preferences: AIChatPreferencesPersisting

    init(preferences: AIChatPreferencesPersisting) {
        self.preferences = preferences
    }

    var newChatModelId: String? {
        preferences.selectedModelId
    }

    var newChatModelShortName: String? {
        preferences.selectedModelShortName
    }

    func saveNewChatModel(id: String?, shortName: String?) {
        preferences.selectedModelId = id
        preferences.selectedModelShortName = shortName
    }

    var reasoningMode: AIChatReasoningMode? {
        get { preferences.selectedReasoningMode }
        set { preferences.selectedReasoningMode = newValue }
    }

    func pickKeptBeyondTab(_ pick: UTIModelSelection) -> UTIModelSelection {
        pick
    }

    func newChatSelectionKeptOnTab(ownPick: UTIModelSelection, shown: UTIModelSelection) -> UTIModelSelection {
        shown
    }

    func pickForNewChat(openedWithModelId modelId: String?) -> UTIModelSelection? {
        nil
    }
}

/// A pick stays in memory on the tab that made it until its chat changes; new chats start on the new-chat default.
@MainActor
final class TabModelPickStore: UTIModelPickStoring {

    var newChatModelId: String? { nil }
    var newChatModelShortName: String? { nil }
    func saveNewChatModel(id: String?, shortName: String?) {}

    var reasoningMode: AIChatReasoningMode?

    func pickKeptBeyondTab(_ pick: UTIModelSelection) -> UTIModelSelection {
        UTIModelSelection()
    }

    func newChatSelectionKeptOnTab(ownPick: UTIModelSelection, shown: UTIModelSelection) -> UTIModelSelection {
        ownPick
    }

    func pickForNewChat(openedWithModelId modelId: String?) -> UTIModelSelection? {
        UTIModelSelection(modelID: modelId)
    }
}
