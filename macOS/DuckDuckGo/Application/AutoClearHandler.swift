//
//  AutoClearHandler.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import AppKit
import Combine
import Foundation
import AIChat
import PixelKit

protocol AutoClearAlertPresenting {
    func confirmAutoClear(clearChats: Bool) -> NSApplication.ModalResponse
}

struct DefaultAutoClearAlertPresenter: AutoClearAlertPresenting {
    func confirmAutoClear(clearChats: Bool) -> NSApplication.ModalResponse {
        let alert = NSAlert.autoClearAlert(clearChats: clearChats)
        return alert.runModal()
    }
}

final class AutoClearHandler: ApplicationTerminationDecider {

    private let dataClearingPreferences: DataClearingPreferences
    private let startupPreferences: StartupPreferences
    private let fireViewModel: FireViewModel
    private let stateRestorationManager: AppStateRestorationManaging
    private let aiChatSyncCleaner: AIChatSyncCleaning?
    private let alertPresenter: AutoClearAlertPresenting
    private let dataClearingWideEventService: DataClearingWideEventService

    init(dataClearingPreferences: DataClearingPreferences,
         startupPreferences: StartupPreferences,
         fireViewModel: FireViewModel,
         stateRestorationManager: AppStateRestorationManaging,
         aiChatSyncCleaner: AIChatSyncCleaning?,
         wideEvent: WideEventManaging,
         alertPresenter: AutoClearAlertPresenting = DefaultAutoClearAlertPresenter()) {
        self.dataClearingPreferences = dataClearingPreferences
        self.startupPreferences = startupPreferences
        self.fireViewModel = fireViewModel
        self.stateRestorationManager = stateRestorationManager
        self.aiChatSyncCleaner = aiChatSyncCleaner
        self.alertPresenter = alertPresenter
        self.dataClearingWideEventService = DataClearingWideEventService(wideEvent: wideEvent)
    }

    @MainActor
    func handleAppLaunch() {
        burnOnStartIfNeeded()
        resetTheCorrectTerminationFlag()
    }

    // MARK: - ApplicationTerminationDecider

    @MainActor
    func shouldTerminate(isAsync: Bool) -> TerminationQuery {
        guard dataClearingPreferences.isAutoClearEnabled else { return .sync(.next) }

        // Skip auto-clear if app is relaunching for an update
        if stateRestorationManager.isRelaunchingAutomatically {
            appTerminationHandledCorrectly = true
            return .sync(.next)
        }

        if dataClearingPreferences.isWarnBeforeClearingEnabled {
            switch confirmAutoClear() {
            case .alertFirstButtonReturn:
                // Clear and Quit
                return .async(Task {
                    await performAutoClear()
                    return .next
                })
            case .alertSecondButtonReturn:
                // Quit without Clearing Data
                appTerminationHandledCorrectly = true
                return .sync(.next)
            default:
                // Cancel
                return .sync(.cancel)
            }
        }

        // Autoclear without warning
        return .async(Task {
            await performAutoClear()
            return .next
        })
    }

    @MainActor
    func deciderSequenceCompleted(shouldProceed: Bool) {
        // Reset stale relaunch flag if termination was cancelled.
        // Scenario: User clicks "Restart to Update" (sets flag=true), but an earlier
        // decider (e.g., ActiveDownloadsAppTerminationDecider) cancels termination.
        // Without this reset, the flag stays true and the next normal quit would
        // incorrectly skip data clearing.
        if !shouldProceed && stateRestorationManager.isRelaunchingAutomatically {
            stateRestorationManager.resetRelaunchFlag()
        }
    }

    func resetTheCorrectTerminationFlag() {
        appTerminationHandledCorrectly = false
    }

    // MARK: - Private

    private func confirmAutoClear() -> NSApplication.ModalResponse {
        return alertPresenter.confirmAutoClear(clearChats: dataClearingPreferences.isAutoClearAIChatHistoryEnabled)
    }

    @MainActor
    private func performAutoClear() async {
        if dataClearingPreferences.isAutoClearAIChatHistoryEnabled {
            Task {
                await aiChatSyncCleaner?.recordLocalClear(date: Date())
            }
        }
        await fireViewModel.fire.burnAll(isBurnOnExit: true,
                                         includeChatHistory: dataClearingPreferences.isAutoClearAIChatHistoryEnabled,
                                         isAutoClear: true,
                                         dataClearingWideEventService: dataClearingWideEventService)
        appTerminationHandledCorrectly = true
    }

    // MARK: - Burn On Start
    // Burning on quit wasn't successful

    @UserDefaultsWrapper(key: .appTerminationHandledCorrectly, defaultValue: false)
    private var appTerminationHandledCorrectly: Bool

    @MainActor
    @discardableResult
    func burnOnStartIfNeeded() -> Bool {
        let shouldBurnOnStart = dataClearingPreferences.isAutoClearEnabled && !appTerminationHandledCorrectly
        guard shouldBurnOnStart else { return false }

        fireViewModel.fire.burnAll(includeChatHistory: dataClearingPreferences.isAutoClearAIChatHistoryEnabled,
                                   isAutoClear: true,
                                   dataClearingWideEventService: dataClearingWideEventService)

        return true
    }

}
