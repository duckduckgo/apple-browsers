//
//  ScopedFireConfirmationViewModel.swift
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
import Core
import Persistence

@MainActor
final class ScopedFireConfirmationViewModel: ObservableObject {
    
    // MARK: - Constants
    
    private enum Keys {
        static let signOutWarningShowCount = "com.duckduckgo.fire.signOutWarningShowCount"
        static let aiTabDescriptionShowCount = "com.duckduckgo.fire.aiTabDescriptionShowCount"
    }
    
    private static let maxSubtitleShowCount = 2
        
    // MARK: - Published Properties
    
    /// The subtitle text to display. Computed once during initialization.
    @Published private(set) var subtitle: String?
    
    // MARK: - Private Variables
    
    private let onConfirm: (FireRequest) -> Void
    private let onCancel: () -> Void
    private let tabViewModel: TabViewModel?
    private let downloadManager: DownloadManaging
    private let keyValueStore: KeyValueStoring
    private let appSettings: AppSettings
    private let daxDialogsManager: DaxDialogsManaging
    private let source: FireRequest.Source
    
    // MARK: - Initializer
    
    init(tabViewModel: TabViewModel?,
         source: FireRequest.Source,
         downloadManager: DownloadManaging = AppDependencyProvider.shared.downloadManager,
         keyValueStore: KeyValueStoring = UserDefaults.standard,
         appSettings: AppSettings = AppDependencyProvider.shared.appSettings,
         daxDialogsManager: DaxDialogsManaging,
         onConfirm: @escaping (FireRequest) -> Void,
         onCancel: @escaping () -> Void) {
        self.tabViewModel = tabViewModel
        self.source = source
        self.downloadManager = downloadManager
        self.keyValueStore = keyValueStore
        self.appSettings = appSettings
        self.daxDialogsManager = daxDialogsManager
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self.subtitle = computeSubtitle()
    }
    
    // MARK: - Computed Variables
    
    /// Indicates whether the single tab burn option should be shown.
    /// Returns `true` when a tab view model is available.
    var canBurnSingleTab: Bool {
        guard let tab = tabViewModel?.tab, tab.supportsTabHistory else {
            return false
        }
        return true
    }
    
    var headerTitle: String {
        let shouldIncludeAIChat = appSettings.autoClearAIChatHistory
        return shouldIncludeAIChat ? UserText.scopedFireConfirmationAlertTitleWithAIChat : UserText.scopedFireConfirmationAlertTitle
    }
    
    // MARK: - Public Functions
    
    func burnAllTabs() {
        let request = FireRequest(options: .all, trigger: .manualFire, scope: .all, source: source)
        onConfirm(request)
    }
    
    func burnThisTab() {
        guard let tabViewModel else {
            return
        }
        let request = FireRequest(options: .all, trigger: .manualFire, scope: .tab(viewModel: tabViewModel), source: source)
        onConfirm(request)
    }
    
    func cancel() {
        onCancel()
    }
    
    // MARK: - Private Functions
    
    /// Computes the subtitle text for the confirmation dialog.
    ///
    /// The logic follows this priority:
    /// 1. If showing Dax fire dialog (onboarding) → return nil (skip all subtitles)
    /// 2. If there are ongoing downloads → show downloads warning
    /// 3. If no tab view model → return nil (tab switcher/settings)
    /// 4. If tab doesn't support tab history → show new tabs info
    /// 5. For AI tabs → show AI-specific description (up to 2 times)
    /// 6. For normal web tabs → show sign out warning (up to 2 times)
    /// 7. Otherwise → return nil
    private func computeSubtitle() -> String? {
        // Skip all subtitles if in onboarding
        if daxDialogsManager.isShowingFireDialog {
            return nil
        }
        
        // Check for ongoing downloads first
        if hasOngoingDownloads() {
            return UserText.scopedFireConfirmationDownloadsWarning
        }
        
        // No subtitle for tab switcher and settings
        guard let tabViewModel else {
            return nil
        }
        
        // If tab doesn't support burning, show new tabs info
        guard tabViewModel.tab.supportsTabHistory else {
            return UserText.scopedFireConfirmationNewTabsInfo
        }
        
        // Check tab type and show count
        if tabViewModel.tab.isAITab {
            return aiTabSubtitle()
        } else {
            return webTabSubtitle()
        }
    }
    
    private func hasOngoingDownloads() -> Bool {
        let ongoingDownloads = downloadManager.downloadList.filter { $0.isRunning && !$0.temporary }
        return !ongoingDownloads.isEmpty
    }
    
    private func webTabSubtitle() -> String? {
        let showCount = keyValueStore.object(forKey: Keys.signOutWarningShowCount) as? Int ?? 0
        
        guard showCount < Self.maxSubtitleShowCount else {
            return nil
        }
        
        keyValueStore.set(showCount + 1, forKey: Keys.signOutWarningShowCount)
        return UserText.scopedFireConfirmationSignOutWarning
    }
    
    private func aiTabSubtitle() -> String? {
        let showCount = keyValueStore.object(forKey: Keys.aiTabDescriptionShowCount) as? Int ?? 0
        
        guard showCount < Self.maxSubtitleShowCount else {
            return nil
        }
        
        keyValueStore.set(showCount + 1, forKey: Keys.aiTabDescriptionShowCount)
        return UserText.scopedFireConfirmationDeleteThisTabDescription
    }
}
