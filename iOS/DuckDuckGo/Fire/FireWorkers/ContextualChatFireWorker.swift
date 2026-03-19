//
//  ContextualChatFireWorker.swift
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

import Core
import PixelKit

struct ContextualChatFireWorker: FireExecutorWorker {

    private let appSettings: AppSettings
    private let tabManager: TabManaging
    private let aiChatDeleter: AIChatDeleting
    private let dataClearingWideEventService: DataClearingWideEventService?

    init(appSettings: AppSettings,
         tabManager: TabManaging,
         aiChatDeleter: AIChatDeleting,
         dataClearingWideEventService: DataClearingWideEventService?) {
        self.appSettings = appSettings
        self.tabManager = tabManager
        self.aiChatDeleter = aiChatDeleter
        self.dataClearingWideEventService = dataClearingWideEventService
    }

    @MainActor
    func burnNormalModeData() async {
        // Contextual chats are tied to specific tabs, not cleared during burn all
    }

    @MainActor
    func burnFireModeData() async {
        // Contextual chats are tied to specific tabs, not cleared during fire mode burn
    }

    @MainActor
    func burnTabData(tabViewModel: TabViewModel, domains: [String]) async {
        guard appSettings.autoClearAIChatHistory else { return }

        var interval = WideEvent.MeasuredInterval.startingNow()

        guard let contextualChatID = tabViewModel.currentContextualChatId else {
            interval.complete()
            dataClearingWideEventService?.update(.deleteContextualAIChat,
                                                 actionResult: ActionResult(result: .success(()), measuredInterval: interval))
            return
        }

        let result = await aiChatDeleter.deleteChat(chatID: contextualChatID)
        switch result {
        case .success:
            tabManager.controller(for: tabViewModel.tab)?.aiChatContextualSheetCoordinator.clearActiveChat()
        case .failure:
            Logger.aiChat.debug("Failed to delete contextual ai chat")
        }

        interval.complete()
        dataClearingWideEventService?.update(.deleteContextualAIChat,
                                             actionResult: ActionResult(result: result, measuredInterval: interval))
    }
}
