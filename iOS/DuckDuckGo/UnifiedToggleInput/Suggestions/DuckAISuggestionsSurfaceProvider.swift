//
//  DuckAISuggestionsSurfaceProvider.swift
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

import Foundation
import Combine
import Core
import PrivacyConfig
import History
import Suggestions
import AIChat
import UIKit

@MainActor
protocol DuckAISuggestionsSurfaceProviderDelegate: AnyObject {
    func duckAISurfaceDidSelect(_ selection: DuckAISuggestionsSelection)
    /// The duck.ai fetchers' content/settle state changed (was `onFetchCompleted`); the owner
    /// refreshes dax visibility.
    func duckAISurfaceStateDidChange()
    /// A URL suggestion was deleted from the shared history store; the owner refreshes Search too.
    func duckAISurfaceDidDeleteURLSuggestion()
    /// Present the fire/delete confirmation for a recent-chat suggestion (the owner is the host VC).
    func duckAISurfaceRequestsChatDeletionConfirmation(for chat: AIChatSuggestion,
                                                       onConfirm: @escaping () -> Void,
                                                       onCancel: @escaping () -> Void)
}

/// Owns the lazily-attached duck.ai suggestions surface: its source, chat/url fetchers, the
/// content/settle state feed, and the URL-history delete action. Built once per attach and torn
/// down on detach (search persists; duck.ai is transient).
@MainActor
final class DuckAISuggestionsSurfaceProvider {

    weak var delegate: DuckAISuggestionsSurfaceProviderDelegate?

    /// The duck.ai facts feed for the merged-inputs publisher. nil while detached (the merger
    /// treats absent state as no recents / nothing pending).
    var statePublisher: AnyPublisher<UnifiedSuggestionsInputsMerger.DuckAIState?, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    var isAttached: Bool { hasContentReader != nil }
    func hasContent() -> Bool { hasContentReader?() ?? false }
    func hasSettled(forQuery query: String) -> Bool { hasSettledReader?(query) ?? false }
    func refreshRecents() { refreshRecentsAction?() }
    func refreshURLSuggestions() { refreshURLSuggestionsAction?() }
    /// Rebuilds the URL data source's session-scoped caches (bookmark snapshot) — see the Search side.
    func refreshCaches() { refreshCachesAction?() }
    /// Recent-chat count for the sync-promo gating; 0 while detached.
    var recentsCount: Int { recentsCountReader?() ?? 0 }

    private let switchBarHandler: SwitchBarHandling
    private let dependencies: SuggestionTrayDependencies
    private let aiChatSettings: AIChatSettingsProvider
    private let aiChatSyncCleaner: AIChatSyncCleaning?
    private let featureFlagger: FeatureFlagger
    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let duckAiNativeStorageHandler: DuckAiNativeStorageHandling?

    private let stateSubject = CurrentValueSubject<UnifiedSuggestionsInputsMerger.DuckAIState?, Never>(nil)
    /// "Has any recent chats" — a stable, query-independent fact (mirrors search's favorites existence),
    /// refreshed only from an unfiltered (empty-query) fetch so a just-cleared query never reads empty
    /// and flashes the logo before its recents reload.
    private let hasAnyRecentsSubject = CurrentValueSubject<Bool, Never>(false)
    private var cancellables = Set<AnyCancellable>()
    private var hasContentReader: (() -> Bool)?
    private var hasSettledReader: ((String) -> Bool)?
    private var refreshRecentsAction: (() -> Void)?
    private var refreshURLSuggestionsAction: (() -> Void)?
    private var refreshCachesAction: (() -> Void)?
    private var recentsCountReader: (() -> Int)?
    /// In-flight history-delete task; cancelled on detach so its post-delete refetch can't run
    /// against a torn-down source.
    private var deleteTask: Task<Void, Never>?
    /// Deletes a recent-chat suggestion via the attached chat manager; nil while detached.
    private var chatDeleteAction: ((AIChatSuggestion) -> Void)?

    init(switchBarHandler: SwitchBarHandling,
         dependencies: SuggestionTrayDependencies,
         aiChatSettings: AIChatSettingsProvider,
         aiChatSyncCleaner: AIChatSyncCleaning?,
         featureFlagger: FeatureFlagger,
         privacyConfigurationManager: PrivacyConfigurationManaging,
         duckAiNativeStorageHandler: DuckAiNativeStorageHandling?) {
        self.switchBarHandler = switchBarHandler
        self.dependencies = dependencies
        self.aiChatSettings = aiChatSettings
        self.aiChatSyncCleaner = aiChatSyncCleaner
        self.featureFlagger = featureFlagger
        self.privacyConfigurationManager = privacyConfigurationManager
        self.duckAiNativeStorageHandler = duckAiNativeStorageHandler
    }

    /// Builds the duck.ai source with its OWN runner/loaders, wires its state into `stateSubject`,
    /// and attaches it to the single host. No-op if already attached.
    func attach(to host: UnifiedSuggestionsHost, textPublisher: AnyPublisher<String, Never>) {
        guard hasContentReader == nil else { return }

        let (chatManager, chatViewModel) = AIChatHistoryManager.makeHistoryManager(
            isFireTab: switchBarHandler.isFireTab,
            isIPadExperience: false,
            featureFlagger: featureFlagger,
            privacyConfigurationManager: privacyConfigurationManager,
            chatSyncCleaner: aiChatSyncCleaner,
            chatSettings: aiChatSettings,
            nativeStorageHandler: duckAiNativeStorageHandler)

        let requestRunner = AutocompleteRequestRunner()
        let dataSource = AutocompleteSuggestionsDataSource(
            historyManager: dependencies.historyManager,
            bookmarksDatabase: dependencies.bookmarksDatabase,
            featureFlagger: dependencies.featureFlagger,
            tabsModel: dependencies.tabsModelProvider()
        ) { request, completion in
            requestRunner.run(request, completion: completion)
        }
        let urlLoader = DuckAIURLSuggestionsLoader(dataSource: dataSource)

        let source = DuckAISuggestionsSource(
            chatViewModel: chatViewModel,
            urlLoader: urlLoader,
            chatManager: chatManager,
            query: { [weak self] in self?.switchBarHandler.currentText ?? "" },
            deleteEnabled: { [featureFlagger] in featureFlagger.isFeatureOn(.removeChatHistory) },
            // The "View all chats" row opens the native history page — an iPhone-only experience gated on the same flag.
            viewAllChatsEnabled: { [featureFlagger] in
                featureFlagger.isFeatureOn(.aiChatNativeChatHistory) && UIDevice.current.userInterfaceIdiom != .pad
            },
            searchSuggestionsEnabled: { [weak self] in self?.dependencies.appSettings.autocomplete ?? true }
        )
        chatManager.onFetchCompleted = { [weak self] query, hasSuggestions in
            // Only an unfiltered (empty-query) fetch defines "has any recent chats". Filtered fetches
            // (while typing) leave it unchanged, so clearing the query keeps the stable `true`.
            if query.isEmpty { self?.hasAnyRecentsSubject.send(hasSuggestions) }
            self?.delegate?.duckAISurfaceStateDidChange()
        }

        // `filteredSuggestions` / `topURLs` are triggers only (they move `settled`); the recents fact
        // comes from the stable `hasAnyRecentsSubject`, not the query-filtered list.
        Publishers.CombineLatest3(
            hasAnyRecentsSubject,
            chatViewModel.$filteredSuggestions.map { _ in () },
            urlLoader.$topURLs.map { _ in () }.prepend(())
        )
        .map { [weak chatManager, weak urlLoader, weak self] hasRecents, _, _ -> UnifiedSuggestionsInputsMerger.DuckAIState in
            let query = self?.switchBarHandler.currentText ?? ""
            let settled = chatManager?.lastCompletedFetchQuery == query
                && urlLoader?.lastCompletedFetchQuery == query
            return .init(hasRecents: hasRecents, settled: settled)
        }
        .sink { [weak self] state in self?.stateSubject.send(state) }
        .store(in: &cancellables)

        let surface = UnifiedSuggestionsDuckAISurface(
            source: source,
            onSelectRow: { [weak self] id in self?.select(rowID: id, source: source) },
            onDeleteRow: { [weak self] id in self?.deleteHistory(rowID: id, source: source) },
            onTapAheadRow: { [weak self] id in self?.select(rowID: id, source: source) },
            onFireDeleteRow: { [weak self] id in self?.requestChatDeletion(rowID: id, source: source) }
        )

        chatDeleteAction = { [weak chatManager] chat in chatManager?.deleteChatSuggestion(suggestion: chat) }

        hasContentReader = { [weak chatViewModel, weak urlLoader, weak self] in
            !(chatViewModel?.filteredSuggestions.isEmpty ?? true)
                || !(urlLoader?.topURLs.isEmpty ?? true)
                || !(self?.switchBarHandler.currentText.isEmpty ?? true)
        }
        hasSettledReader = { [weak chatManager, weak urlLoader] query in
            chatManager?.lastCompletedFetchQuery == query
                && urlLoader?.lastCompletedFetchQuery == query
        }
        refreshRecentsAction = { [weak chatManager, weak self] in
            chatManager?.refreshSuggestions(query: self?.switchBarHandler.currentText ?? "")
        }
        refreshURLSuggestionsAction = { [weak self] in
            guard let self, self.dependencies.appSettings.autocomplete else { return }
            source.fetchURLSuggestions(query: self.switchBarHandler.currentText)
        }
        refreshCachesAction = { [weak dataSource] in dataSource?.refreshCaches() }
        recentsCountReader = { [weak chatViewModel] in chatViewModel?.filteredSuggestions.count ?? 0 }

        host.attachDuckAISurface(surface, textPublisher: textPublisher)
    }

    /// Tears down the source/VM and clears its state so the merger reverts to no-recents/nothing-pending.
    func detach(from host: UnifiedSuggestionsHost) {
        guard hasContentReader != nil else { return }
        deleteTask?.cancel()
        cancellables.removeAll()
        host.detachDuckAISurface()
        stateSubject.send(nil)
        hasContentReader = nil
        hasSettledReader = nil
        refreshRecentsAction = nil
        refreshURLSuggestionsAction = nil
        refreshCachesAction = nil
        recentsCountReader = nil
        chatDeleteAction = nil
    }

    private func select(rowID id: String, source: DuckAISuggestionsSource) {
        guard let selection = source.selection(forRowID: id) else { return }
        delegate?.duckAISurfaceDidSelect(selection)
    }

    private func deleteHistory(rowID id: String, source: DuckAISuggestionsSource) {
        guard case .url(let suggestion) = source.selection(forRowID: id),
              case .historyEntry(_, let url, _) = suggestion else { return }
        deleteTask = Task { [weak self] in
            guard let self else { return }
            await SuggestionHistoryDeletion.delete(url, using: self.dependencies.historyManager)
            guard !Task.isCancelled else { return }
            source.fetchURLSuggestions(query: self.switchBarHandler.currentText)
            self.delegate?.duckAISurfaceDidDeleteURLSuggestion()
        }
    }

    /// Recent-chat 🔥 delete: fires the tapped pixel, asks the host to present the confirmation, and
    /// on confirm deletes the chat + fires the confirmed/cancelled pixels (mirrors the legacy coordinator).
    private func requestChatDeletion(rowID id: String, source: DuckAISuggestionsSource) {
        guard case .chat(let chat) = source.selection(forRowID: id) else { return }
        DailyPixel.fireDailyAndCount(pixel: .aiChatRecentChatDeleteButtonTapped)
        delegate?.duckAISurfaceRequestsChatDeletionConfirmation(
            for: chat,
            onConfirm: { [weak self] in
                self?.chatDeleteAction?(chat)
                DailyPixel.fireDailyAndCount(pixel: .aiChatRecentChatDeleteConfirmed)
            },
            onCancel: {
                DailyPixel.fireDailyAndCount(pixel: .aiChatRecentChatDeleteCancelled)
            })
    }
}
