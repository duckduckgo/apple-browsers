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

class FireConfirmationViewModel: ObservableObject {
    
    // MARK: - Published Variables
    
    @Published var clearTabs: Bool = true
    @Published var clearData: Bool = true
    @Published var clearAIChats: Bool = false
    
    // MARK: - Public Variables
    
    let onConfirm: () -> Void
    let onCancel: () -> Void
    let showAIChatsOption: Bool = true
    
    // MARK: - Private Variables
    private let tabsModel: TabsModeling?
    private let historyManager: HistoryManaging?
    private let tld: TLD
    private let fireproofing: Fireproofing?
    
    init(tabsModel: TabsModeling?,
         historyManager: HistoryManaging?,
         tld: TLD = AppDependencyProvider.shared.storageCache.tld,
         fireproofing: Fireproofing?,
         onConfirm: @escaping () -> Void,
         onCancel: @escaping () -> Void) {
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self.tabsModel = tabsModel
        self.historyManager = historyManager
        self.tld = tld
        self.fireproofing = fireproofing
    }
    
    func confirm() {
        onConfirm()
    }
    
    func cancel() {
        onCancel()
    }
    
    func clearTabsSubtitle() -> String {
        let tabsCount = tabsModel?.count ?? 0
        return UserText.fireConfirmationTabsSubtitle(withCount: tabsCount)
    }
    
    @MainActor
    func clearDataSubtitle() -> String {
        guard let historyManager = historyManager else {
            return UserText.fireConfirmationDataSubtitle(withCount: 0)
        }
        
        guard historyManager.isEnabledByUser else {
            return UserText.fireConfirmationDataSubtitleHistoryDisabled
        }
        
        let sitesCount = computeNonFireproofedDomainCount()
        return UserText.fireConfirmationDataSubtitle(withCount: sitesCount)
    }
    
    @MainActor
    private func computeNonFireproofedDomainCount() -> Int {
        guard let history = historyManager?.historyCoordinator.history else {
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
            guard let fireproofing else {
                assertionFailure("fireproofing should not be nil here")
                return true
            }
            return !fireproofing.isAllowed(fireproofDomain: domain)
        }
        
        return nonFireproofed.count
    }
}
