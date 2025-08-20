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

final class AutoClearHandler {

    private let dataClearingPreferences: DataClearingPreferences
    private let startupPreferences: StartupPreferences
    private let fireViewModel: FireViewModel
    private let stateRestorationManager: AppStateRestorationManager

    init(dataClearingPreferences: DataClearingPreferences,
         startupPreferences: StartupPreferences,
         fireViewModel: FireViewModel,
         stateRestorationManager: AppStateRestorationManager) {
        self.dataClearingPreferences = dataClearingPreferences
        self.startupPreferences = startupPreferences
        self.fireViewModel = fireViewModel
        self.stateRestorationManager = stateRestorationManager
    }

    @MainActor
    func handleAppLaunch() {
        burnOnStartIfNeeded()
        resetTheCorrectTerminationFlag()
    }

    var onAutoClearCompleted: (() -> Void)?

    @MainActor
    func handleAppTermination() -> NSApplication.TerminateReply? {
        guard dataClearingPreferences.isAutoClearEnabled else { return nil }

        if dataClearingPreferences.isWarnBeforeClearingEnabled {
            switch confirmAutoClear() {
            case .alertFirstButtonReturn:
                // Clear and Quit
                performAutoClear()
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

        performAutoClear()
        return .terminateLater
    }

    func resetTheCorrectTerminationFlag() {
        appTerminationHandledCorrectly = false
    }

    // MARK: - Private

    private func confirmAutoClear() -> NSApplication.ModalResponse {
        let alert = NSAlert.autoClearAlert()
        let response = alert.runModal()
        return response
    }

    @MainActor
    private func performAutoClear() {
        fireViewModel.fire.burnAll(isBurnOnExit: true) { [weak self] in
            self?.appTerminationHandledCorrectly = true
            self?.onAutoClearCompleted?()
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

        fireViewModel.fire.burnAll()
        return true
    }

}
