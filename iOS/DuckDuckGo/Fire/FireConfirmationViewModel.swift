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

@MainActor
class FireConfirmationViewModel: ObservableObject {
    
    // MARK: - Published Variables
    
    @Published var clearTabs: Bool = true
    @Published var clearData: Bool = true
    @Published var clearAIChats: Bool = false
    
    // MARK: - Public Variables
    
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    // MARK: - Private Variables
    private let tabsModel: TabsModeling
    private let historyManager: HistoryManaging
    private let tld: TLD
    private let fireproofing: Fireproofing
    private let aiChatSettings: AIChatSettingsProvider
    
    // MARK: - Lazy Variables

    private lazy var sitesCount: Int = {
        return self.computeNonFireproofedDomainCount()
    }()
    
    private lazy var tabsCount: Int = {
        guard tabsModel.hasActiveTabs else {
            return 0
        }
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
    
    // MARK: - Persistence Storage
    @UserDefaultsWrapper(key: .fireConfirmationClearTabs, defaultValue: true)
    private var storedClearTabs: Bool
    
    @UserDefaultsWrapper(key: .fireConfirmationClearData, defaultValue: true)
    private var storedClearData: Bool
    
    @UserDefaultsWrapper(key: .fireConfirmationClearAIChats, defaultValue: false)
    private var storedClearAIChats: Bool
    
    // MARK: - Initializer
    
    init(tabsModel: TabsModeling,
         historyManager: HistoryManaging,
         tld: TLD = AppDependencyProvider.shared.storageCache.tld,
         fireproofing: Fireproofing,
         aiChatSettings: AIChatSettingsProvider,
         onConfirm: @escaping () -> Void,
         onCancel: @escaping () -> Void) {
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self.tabsModel = tabsModel
        self.historyManager = historyManager
        self.tld = tld
        self.fireproofing = fireproofing
        self.aiChatSettings = aiChatSettings
        loadPersistedValues()
    }
    
    // MARK: - Public Functions
    
    func confirm() {
        // Persist current toggle states
        if !isClearTabsDisabled {
            storedClearTabs = clearTabs
        }
        if !isClearDataDisabled {
            storedClearData = clearData
        }
        if showAIChatsOption {
            storedClearAIChats = clearAIChats
        }
        
        onConfirm()
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
        
        // Get all domains from history
        let allDomains = history.lazy.compactMap { entry -> String? in
            entry.url.host
        }
        
        // Convert them to eTLD+1
        let eTLDPlus1Domains = allDomains.reduce(into: Set<String>()) { result, domain in
            let eTLDPlus1Domain = tld.eTLDplus1(domain) ?? domain
            result.insert(eTLDPlus1Domain)
        }
        
        // Filter out fireproofed domains
        let nonFireproofed = eTLDPlus1Domains.filter { domain in
            return !fireproofing.isAllowed(fireproofDomain: domain)
        }
        
        return nonFireproofed.count
    }
    
    private func loadPersistedValues() {
        self.clearTabs = isClearTabsDisabled ? false : storedClearTabs
        self.clearData = isClearDataDisabled ? false : storedClearData
        self.clearAIChats = showAIChatsOption ? storedClearAIChats : false
    }
}
