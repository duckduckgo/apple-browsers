//
//  MainViewController+DuckAISession.swift
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
import Foundation

/// Call sites for the Duck.ai session wide event, which measures one visit to a full Duck.ai tab.
extension MainViewController {

    /// Reports the tab that is (about to be) on screen. Unchanged snapshots are ignored downstream.
    func reportDuckAISessionVisibleTab(_ tab: Tab?) {
        duckAISessionInstrumentation.visibleTabDidChange(tab.map(duckAISessionSnapshot))
    }

    func reportDuckAISessionCurrentTab() {
        reportDuckAISessionVisibleTab(tabManager.currentTabsModel.currentTab)
    }

    /// Records the action about to leave Duck.ai, if the visible tab is a Duck.ai tab.
    func recordDuckAISessionPendingExit(_ trigger: DuckAISessionWideEventData.ExitTrigger) {
        guard let tab = tabManager.currentTabsModel.currentTab, tab.isAITab else { return }
        duckAISessionInstrumentation.recordPendingExit(tabUID: tab.uid, trigger: trigger)
    }

    /// Any close of the visible Duck.ai tab is the close exit, whichever surface closed it.
    func recordDuckAISessionCloseIfNeeded(closingTabs: [Tab]) {
        guard let current = tabManager.currentTabsModel.currentTab,
              closingTabs.contains(where: { $0.uid == current.uid }) else { return }
        recordDuckAISessionPendingExit(.backOrClose)
    }

    func recordDuckAISessionPromptSubmitted(for handler: AIChatContentHandling) {
        guard let tab = currentTab, tab.aiChatContentHandler === handler else { return }
        duckAISessionInstrumentation.promptSubmitted(tabUID: tab.tabModel.uid)
    }

    func recordDuckAISessionPromptSubmittedOnCurrentTab() {
        guard let tab = tabManager.currentTabsModel.currentTab, tab.isAITab else { return }
        duckAISessionInstrumentation.promptSubmitted(tabUID: tab.uid)
    }

    func recordDuckAISessionNewChatCreated(for handler: AIChatContentHandling) {
        guard let tab = currentTab, tab.aiChatContentHandler === handler else { return }
        duckAISessionInstrumentation.newChatCreated(tabUID: tab.tabModel.uid)
    }

    func recordDuckAISessionNewChatCreatedOnCurrentTab() {
        guard let tab = tabManager.currentTabsModel.currentTab, tab.isAITab else { return }
        duckAISessionInstrumentation.newChatCreated(tabUID: tab.uid)
    }

    private func duckAISessionSnapshot(_ tab: Tab) -> DuckAISessionTabSnapshot {
        let url = tab.link?.url
        return DuckAISessionTabSnapshot(uid: tab.uid, isDuckAI: tab.isAITab, url: url, chatID: url?.duckAIChatID)
    }
}
