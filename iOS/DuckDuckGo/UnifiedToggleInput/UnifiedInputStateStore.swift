//
//  UnifiedInputStateStore.swift
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
import Combine
import os.log

@MainActor
final class UnifiedInputStateStore: UnifiedInputStateStoring {

    private var states: [TabUID: TabInputState] = [:]
    private var preferences: AIChatPreferencesPersisting
    private let toggleModeStorage: ToggleModeStoring
    private var trackedLastUsed: LastUsedInputDefaults
    private var modelSnapshots: [ObjectIdentifier: [Tab]] = [:]
    private var tabsCancellables = Set<AnyCancellable>()
    private var knownUIDs: Set<TabUID> = []
    private var tabsByUID: [TabUID: any UnifiedInputTabStateProviding] = [:]

    init(
        preferences: AIChatPreferencesPersisting,
        toggleModeStorage: ToggleModeStoring
    ) {
        self.preferences = preferences
        self.toggleModeStorage = toggleModeStorage
        self.trackedLastUsed = LastUsedInputDefaults(
            toggleMode: toggleModeStorage.restore() ?? .search,
            selectedModelID: preferences.selectedModelId,
            selectedReasoningMode: preferences.selectedReasoningMode,
            selectedTool: preferences.selectedTool
        )
    }

    var lastUsed: LastUsedInputDefaults { trackedLastUsed }

    func state(for uid: TabUID) -> TabInputState {
        if let existing = states[uid] {
            Logger.unifiedInputState.debug("state(for:) hit for tab [\(uid)]: \(existing.summary)")
            return existing
        }
        let seeded = seededState()
        Logger.unifiedInputState.debug("state(for:) miss for tab [\(uid)] — returning fresh seed: \(seeded.summary)")
        return seeded
    }

    func update(_ state: TabInputState, for uid: TabUID) {
        states[uid] = state
        Logger.unifiedInputState.debug("update flush for tab [\(uid)]: \(state.summary)")
    }

    func recordUserChoice(_ state: TabInputState, for uid: TabUID, isNewChatContext: Bool) {
        states[uid] = state
        trackedLastUsed = LastUsedInputDefaults(
            toggleMode: state.toggleMode,
            selectedModelID: isNewChatContext ? state.selectedModelID : trackedLastUsed.selectedModelID,
            selectedReasoningMode: state.selectedReasoningMode,
            selectedTool: state.selectedTool
        )
        toggleModeStorage.save(state.toggleMode)
        preferences.selectedReasoningMode = state.selectedReasoningMode
        preferences.selectedTool = state.selectedTool

        if let tab = tabsByUID[uid] {
            var inputState = tab.unifiedInputState
            inputState.selectedModelID = state.selectedModelID
            inputState.selectedReasoningMode = state.selectedReasoningMode
            inputState.selectedTool = state.selectedTool
            tab.unifiedInputState = inputState
        }
        Logger.unifiedInputState.debug("recordUserChoice for tab [\(uid)] (newChat=\(isNewChatContext)): \(state.summary)")
    }

    func remove(for uid: TabUID) {
        guard states.removeValue(forKey: uid) != nil else { return }
        Logger.unifiedInputState.debug("remove for tab [\(uid)]")
    }

    func observeTabsModel(_ tabsModel: TabsModelManaging) {
        let modelID = ObjectIdentifier(tabsModel)
        tabsModel.tabsPublisher
            .sink { [weak self] tabs in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.modelSnapshots[modelID] = tabs
                    self.reconcileFromSnapshots()
                }
            }
            .store(in: &tabsCancellables)
    }

    private func reconcileFromSnapshots() {
        let allTabs = modelSnapshots.values.flatMap { $0 }
        let currentUIDs = Set(allTabs.map { $0.uid })
        tabsByUID = Dictionary(
            allTabs.map { ($0.uid, $0 as any UnifiedInputTabStateProviding) },
            uniquingKeysWith: { _, last in last }
        )
        for tab in allTabs where !knownUIDs.contains(tab.uid) {
            let seeded = seededState(from: tab.unifiedInputState)
            states[tab.uid] = seeded
            Logger.unifiedInputState.debug("seeded new tab [\(tab.uid)] from TabsModel insert: \(seeded.summary)")
        }
        for uid in knownUIDs.subtracting(currentUIDs) {
            states.removeValue(forKey: uid)
            Logger.unifiedInputState.debug("evicted tab [\(uid)] on TabsModel removal")
        }
        knownUIDs = currentUIDs
    }

    private func seededState(from inputState: UnifiedInputTabState) -> TabInputState {
        TabInputState(
            text: "",
            toggleMode: trackedLastUsed.toggleMode,
            attachments: [],
            selectedModelID: inputState.selectedModelID ?? trackedLastUsed.selectedModelID,
            selectedReasoningMode: inputState.selectedReasoningMode ?? trackedLastUsed.selectedReasoningMode,
            selectedTool: inputState.selectedTool ?? trackedLastUsed.selectedTool
        )
    }

    private func seededState() -> TabInputState {
        TabInputState(
            text: "",
            toggleMode: trackedLastUsed.toggleMode,
            attachments: [],
            selectedModelID: trackedLastUsed.selectedModelID,
            selectedReasoningMode: trackedLastUsed.selectedReasoningMode,
            selectedTool: trackedLastUsed.selectedTool
        )
    }
}
