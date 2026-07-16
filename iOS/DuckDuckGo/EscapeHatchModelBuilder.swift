//
//  EscapeHatchModelBuilder.swift
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
import PrivacyConfig

/// Builds the after-idle `EscapeHatchModel`, keeping the construction logic out of `MainViewController`.
/// The owning view controller passes itself as the `EscapeHatchActionRouter`.
struct EscapeHatchModelBuilder {

    let tabManager: TabManager
    let lastActiveTabStore: LastActiveTabStoring
    let idleReturnEligibilityManager: IdleReturnEligibilityManaging
    let afterInactivityOptionAdapter: AfterInactivityOptionAdapter
    let lastTabShortcutAdapter: LastTabShortcutAdapter
    let instrumentation: NTPAfterIdleInstrumentation

    /// The hatch to show on an after-idle New Tab Page, or `nil` when none applies.
    func makeAfterIdleHatch(router: EscapeHatchActionRouter) -> EscapeHatchModel? {
        guard idleReturnEligibilityManager.isEligibleForNTPAfterIdle() else { return nil }

        let currentTab = tabManager.currentTabsModel.currentTab
        if currentTab?.fireTab == true {
            // Avoid showing a hatch on fire tabs.
            return nil
        }

        // Prefer the full model whenever there's a distinct tab to return to; the card shows/hides reactively with the setting.
        if let lastUID = lastActiveTabStore.lastActiveNonEmptyTabUID,
           let targetTab = tabManager.allTabsModel.tabs.first(where: { $0.uid == lastUID }),
           targetTab !== currentTab,
           let model = makeCardModel(targetTab: targetTab, router: router) {
            return model
        }

        // No tab to return to. When the shortcut is hidden, still show the expanded pill (even with one tab).
        if !lastTabShortcutAdapter.isEnabled, let currentTab {
            return makeTabSwitcherOnly(targetTab: currentTab, router: router)
        }

        return nil
    }

    /// Tab-switcher-only hatch (no Return-to-tab card) for when the shortcut is hidden and there's no
    /// distinct tab to return to.
    func makeTabSwitcherOnly(targetTab: Tab, router: EscapeHatchActionRouter) -> EscapeHatchModel {
        EscapeHatchModel(
            tabSwitcherOnlyTargetTab: targetTab,
            tabsSource: tabManager,
            router: router,
            afterInactivityOptionAdapter: afterInactivityOptionAdapter,
            lastTabShortcutAdapter: lastTabShortcutAdapter
        )
    }

    private func makeCardModel(targetTab: Tab, router: EscapeHatchActionRouter) -> EscapeHatchModel? {
        if targetTab.fireTab {
            guard targetTab.link != nil || targetTab.isAITab else { return nil }
            return makeModel(title: UserText.escapeHatchFireTabTitle, subtitle: "", tabType: .fire, domain: nil, targetTab: targetTab, router: router)
        }
        if targetTab.isAITab {
            return makeModel(
                title: targetTab.aiChatConversationTitle ?? UserText.omnibarFullAIChatModeDisplayTitle,
                subtitle: UserText.omnibarFullAIChatModeDisplayTitle,
                tabType: .aiChat,
                domain: nil,
                targetTab: targetTab,
                router: router
            )
        }
        if let link = targetTab.link {
            let subtitle = link.url.host?.droppingWwwPrefix() ?? link.url.absoluteString
            return makeModel(title: link.displayTitle, subtitle: subtitle, tabType: .regular, domain: link.url.host, targetTab: targetTab, router: router)
        }
        return nil
    }

    private func makeModel(title: String,
                           subtitle: String,
                           tabType: EscapeHatchModel.TabType,
                           domain: String?,
                           targetTab: Tab,
                           router: EscapeHatchActionRouter) -> EscapeHatchModel {
        EscapeHatchModel(
            title: title,
            subtitle: subtitle,
            tabType: tabType,
            domain: domain,
            targetTab: targetTab,
            tabsSource: tabManager,
            router: router,
            afterInactivityOptionAdapter: afterInactivityOptionAdapter,
            lastTabShortcutAdapter: lastTabShortcutAdapter,
            onShortcutHidden: { [instrumentation] in instrumentation.escapeHatchHiddenFromMenu() },
            instrumentation: instrumentation
        )
    }
}
