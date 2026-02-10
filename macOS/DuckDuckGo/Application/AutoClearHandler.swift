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
    private let stateRestorationManager: AppStateRestorationManager
    private let aiChatSyncCleaner: AIChatSyncCleaning?
    private let alertPresenter: AutoClearAlertPresenting

    init(dataClearingPreferences: DataClearingPreferences,
         startupPreferences: StartupPreferences,
         fireViewModel: FireViewModel,
         stateRestorationManager: AppStateRestorationManager,
         aiChatSyncCleaner: AIChatSyncCleaning?,
         alertPresenter: AutoClearAlertPresenting = DefaultAutoClearAlertPresenter()) {
        self.dataClearingPreferences = dataClearingPreferences
        self.startupPreferences = startupPreferences
        self.fireViewModel = fireViewModel
        self.stateRestorationManager = stateRestorationManager
        self.aiChatSyncCleaner = aiChatSyncCleaner
        self.alertPresenter = alertPresenter
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
        let startTime = CACurrentMediaTime()
        await fireViewModel.fire.burnAll(isBurnOnExit: true, includeChatHistory: dataClearingPreferences.isAutoClearAIChatHistoryEnabled)
        Self.fireCompletionPixel(from: startTime, isAutoClearAIChatHistoryEnabled: dataClearingPreferences.isAutoClearAIChatHistoryEnabled)
        appTerminationHandledCorrectly = true
    }

   // MARK: - Fallback (Old Synchronous Pattern - To be removed)

    @MainActor
    func handleAppTerminationFallback() -> NSApplication.TerminateReply? {
        guard dataClearingPreferences.isAutoClearEnabled else { return nil }

        if dataClearingPreferences.isWarnBeforeClearingEnabled {
            switch confirmAutoClear() {
            case .alertFirstButtonReturn:
                // Clear and Quit
                performAutoClearSyncFallback()
                return .terminateLater
            case .alertSecondButtonReturn:
                // Quit without Clearing Data
                appTerminationHandledCorrectly = true
                return .terminateNow
            default:
                // Cancel
                return .terminateCancel
            }
        }

        // Autoclear without warning
        performAutoClearSyncFallback()
        return .terminateLater
    }

    @MainActor
    private func performAutoClearSyncFallback() {
        if dataClearingPreferences.isAutoClearAIChatHistoryEnabled {
            Task {
                await aiChatSyncCleaner?.recordLocalClear(date: Date())
            }
        }
        fireViewModel.fire.burnAll(isBurnOnExit: true, includeChatHistory: dataClearingPreferences.isAutoClearAIChatHistoryEnabled) { [weak self] in
            self?.appTerminationHandledCorrectly = true
            NSApp.reply(toApplicationShouldTerminate: true)
        }
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

        let startTime = CACurrentMediaTime()
        fireViewModel.fire.burnAll(includeChatHistory: dataClearingPreferences.isAutoClearAIChatHistoryEnabled) { [weak self] in
            guard let self else { return }
            Self.fireCompletionPixel(from: startTime, isAutoClearAIChatHistoryEnabled: self.dataClearingPreferences.isAutoClearAIChatHistoryEnabled)
        }
        return true
    }

}

// MARK: - Instrumentation

extension AutoClearHandler {
    private static func fireCompletionPixel(from startTime: CFTimeInterval, isAutoClearAIChatHistoryEnabled: Bool) {
        PixelKit.fire(
            DataClearingPixels.fireCompletion(
                duration: Int((CACurrentMediaTime() - startTime) * 1000),
                option: "all_data",
                domains: isAutoClearAIChatHistoryEnabled ? "CookiesAndSiteData,ChatHistory": "CookiesAndSiteData",
                path: "burnAll",
                autoClear: "true"
            ),
            frequency: .standard
        )
    }
}
