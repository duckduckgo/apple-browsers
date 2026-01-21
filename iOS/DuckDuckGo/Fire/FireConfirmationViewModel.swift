//
//  FireConfirmationViewModel.swift
//  DuckDuckGo
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

import Foundation
import Combine
import Core
import Common
import History
import AIChat
import Persistence

@MainActor
class FireConfirmationViewModel: ObservableObject {
    
    // MARK: - Published Variables
    
    @Published var clearTabs: Bool = true
    @Published var clearData: Bool = true
    @Published var clearAIChats: Bool = false
    
    // MARK: - Public Variables
    
    let onConfirm: (FireRequest) -> Void
    let onCancel: () -> Void
    
    // MARK: - Private Variables
    private let tabsModel: TabsModelProtocol
    private let historyManager: HistoryManaging
    private let fireproofing: Fireproofing
    private let aiChatSettings: AIChatSettingsProvider
    private let settingsStore: FireConfirmationSettingsStoring
    
    // MARK: - Lazy Variables

    private lazy var sitesCount: Int = {
        return self.computeNonFireproofedDomainCount()
    }()
    
    private lazy var tabsCount: Int = {
        return tabsModel.count
    }()
    
    // MARK: - Computed Properties
    
    var isDeleteButtonDisabled: Bool {
        !clearTabs && !clearData && !clearAIChats
    }
    
    var isClearTabsDisabled: Bool {
        tabsCount == 0
    }
    
    var isClearDataDisabled: Bool {
        return historyManager.isEnabledByUser && sitesCount == 0
    }
    
    var showAIChatsOption: Bool {
        aiChatSettings.isAIChatEnabled
    }
    
    private var fireOptions: FireRequest.Options {
        var options: FireRequest.Options = []
        if clearTabs {
            options.insert(.tabs)
        }
        if clearData {
            options.insert(.data)
        }
        if clearAIChats {
            options.insert(.aiChats)
        }
        return options
    }
    
    // MARK: - Initializer
    
    init(tabsModel: TabsModelProtocol,
         historyManager: HistoryManaging,
         fireproofing: Fireproofing,
         aiChatSettings: AIChatSettingsProvider,
         keyValueFilesStore: ThrowingKeyValueStoring,
         onConfirm: @escaping (FireRequest) -> Void,
         onCancel: @escaping () -> Void) {
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self.tabsModel = tabsModel
        self.historyManager = historyManager
        self.fireproofing = fireproofing
        self.aiChatSettings = aiChatSettings
        self.settingsStore = FireConfirmationSettingsStore(keyValueFilesStore: keyValueFilesStore)
        loadPersistedValues()
    }
    
    // MARK: - Public Functions
    
    func confirm() {
        // Persist current toggle states
        if !isClearTabsDisabled {
            settingsStore.clearTabs = clearTabs
        }
        if !isClearDataDisabled {
            settingsStore.clearData = clearData
        }
        if showAIChatsOption {
            settingsStore.clearAIChats = clearAIChats
        }
        
        let request = FireRequest(options: fireOptions, trigger: .manualFire, scope: .all)
        onConfirm(request)
    }
    
    func cancel() {
        onCancel()
    }
    
    func clearTabsSubtitle() -> String {
        return UserText.fireConfirmationTabsSubtitle(withCount: tabsCount)
    }
    
    func clearDataSubtitle() -> String {
        guard historyManager.isEnabledByUser else {
            return UserText.fireConfirmationDataSubtitleHistoryDisabled
        }
        return UserText.fireConfirmationDataSubtitle(withCount: sitesCount)
    }
    
    // MARK: - Private Helpers
    
    private func computeNonFireproofedDomainCount() -> Int {
        guard let history = historyManager.historyCoordinator.history else {
            return 0
        }
        
        // Get all unique hosts from history
        let allHosts = Set(history.lazy.compactMap { $0.url.host })
        
        // Filter out fireproofed domains
        let nonFireproofed = allHosts.filter { host in
            return !fireproofing.isAllowed(fireproofDomain: host)
        }
        
        return nonFireproofed.count
    }
    
    private func loadPersistedValues() {
        self.clearTabs = isClearTabsDisabled ? false : settingsStore.clearTabs
        self.clearData = isClearDataDisabled ? false : settingsStore.clearData
        self.clearAIChats = showAIChatsOption ? settingsStore.clearAIChats : false
    }
}
