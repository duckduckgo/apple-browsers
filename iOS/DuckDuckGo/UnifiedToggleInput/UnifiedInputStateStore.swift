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
    private var trackedLastUsed: LastUsedInputDefaults
    private var modelSnapshots: [ObjectIdentifier: [Tab]] = [:]
    private var tabsCancellables = Set<AnyCancellable>()
    private var knownUIDs: Set<TabUID> = []

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
            selectedTool: nil
        )
    }

    var lastUsed: LastUsedInputDefaults { trackedLastUsed }

    func state(for uid: TabUID) -> TabInputState {
        if let existing = states[uid] {
            return existing
        }
        return seededState(toggleMode: trackedLastUsed.toggleMode)
    }

    func update(_ state: TabInputState, for uid: TabUID) {
        states[uid] = state
    }

    func recordUserChoice(_ state: TabInputState, for uid: TabUID) {
        states[uid] = state
        trackedLastUsed = LastUsedInputDefaults(
            toggleMode: state.toggleMode,
            selectedModelID: state.selectedModelID,
            selectedReasoningMode: state.selectedReasoningMode,
            selectedTool: state.selectedTool
        )
        toggleModeStorage.save(state.toggleMode)
        preferences.selectedModelId = state.selectedModelID
        preferences.selectedReasoningMode = state.selectedReasoningMode
    }

    func remove(for uid: TabUID) {
        states.removeValue(forKey: uid)
    }

    /// Observes one tabs model for eager seeding and eviction. Can be called multiple
    /// times to observe both normal- and fire-mode tabs models.
    ///
    /// `@Published` fires in `willSet`, so the publisher's closure parameter holds the
    /// post-mutation value while the source-of-truth accessor still returns the old
    /// value. We track each model's latest emission separately and reconcile from the
    /// union, avoiding the stale-read trap.
    func observeTabsModel(_ tabsModel: TabsModelManaging) {
        let modelID = ObjectIdentifier(tabsModel)
        tabsModel.tabsPublisher
            .sink { [weak self] tabs in
                guard let self else { return }
                self.modelSnapshots[modelID] = tabs
                self.reconcileFromSnapshots()
            }
            .store(in: &tabsCancellables)
    }

    private func reconcileFromSnapshots() {
        let allTabs = modelSnapshots.values.flatMap { $0 }
        let currentUIDs = Set(allTabs.map { $0.uid })
        for tab in allTabs where !knownUIDs.contains(tab.uid) {
            states[tab.uid] = seededState(toggleMode: tab.preferredTextEntryMode)
        }
        for uid in knownUIDs.subtracting(currentUIDs) {
            states.removeValue(forKey: uid)
        }
        knownUIDs = currentUIDs
    }

    private func seededState(toggleMode: TextEntryMode) -> TabInputState {
        TabInputState(
            text: "",
            toggleMode: toggleMode,
            attachments: [],
            selectedModelID: trackedLastUsed.selectedModelID,
            selectedReasoningMode: trackedLastUsed.selectedReasoningMode,
            selectedTool: trackedLastUsed.selectedTool
        )
    }
}
