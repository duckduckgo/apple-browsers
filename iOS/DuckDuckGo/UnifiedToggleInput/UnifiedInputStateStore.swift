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

import AIChat
import Combine

@MainActor
final class UnifiedInputStateStore: UnifiedInputStateStoring {

    private var states: [TabUID: TabInputState] = [:]
    private var preferences: AIChatPreferencesPersisting
    private let toggleModeStorage: ToggleModeStoring
    private var lastUsedTool: AIChatRAGTool?
    private var tabsCancellable: AnyCancellable?
    private var knownUIDs: Set<TabUID> = []

    init(
        preferences: AIChatPreferencesPersisting,
        toggleModeStorage: ToggleModeStoring
    ) {
        self.preferences = preferences
        self.toggleModeStorage = toggleModeStorage
    }

    var lastUsed: LastUsedInputDefaults {
        LastUsedInputDefaults(
            toggleMode: toggleModeStorage.restore() ?? .search,
            selectedModelID: preferences.selectedModelId,
            selectedReasoningMode: preferences.selectedReasoningMode,
            selectedTool: lastUsedTool
        )
    }

    func state(for uid: TabUID) -> TabInputState {
        if let existing = states[uid] {
            return existing
        }
        return seededState()
    }

    func update(_ state: TabInputState, for uid: TabUID) {
        states[uid] = state
        toggleModeStorage.save(state.toggleMode)
        preferences.selectedModelId = state.selectedModelID
        preferences.selectedReasoningMode = state.selectedReasoningMode
        lastUsedTool = state.selectedTool
    }

    func remove(for uid: TabUID) {
        states.removeValue(forKey: uid)
    }

    func observeTabsModel(_ tabsModel: TabsModelManaging) {
        tabsCancellable = tabsModel.tabsPublisher
            .sink { [weak self] tabs in
                self?.reconcile(with: tabs)
            }
    }

    private func reconcile(with tabs: [Tab]) {
        let currentUIDs = Set(tabs.map { $0.uid })
        for tab in tabs where !knownUIDs.contains(tab.uid) {
            states[tab.uid] = seededState(forTab: tab)
        }
        for uid in knownUIDs.subtracting(currentUIDs) {
            states.removeValue(forKey: uid)
        }
        knownUIDs = currentUIDs
    }

    private func seededState(forTab tab: Tab) -> TabInputState {
        let defaults = lastUsed
        return TabInputState(
            text: "",
            toggleMode: tab.preferredTextEntryMode,
            attachments: [],
            selectedModelID: defaults.selectedModelID,
            selectedReasoningMode: defaults.selectedReasoningMode,
            selectedTool: defaults.selectedTool
        )
    }

    private func seededState() -> TabInputState {
        let defaults = lastUsed
        return TabInputState(
            text: "",
            toggleMode: defaults.toggleMode,
            attachments: [],
            selectedModelID: defaults.selectedModelID,
            selectedReasoningMode: defaults.selectedReasoningMode,
            selectedTool: defaults.selectedTool
        )
    }
}
