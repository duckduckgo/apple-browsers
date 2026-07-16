//
//  SettingsNextStepsDebugView.swift
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
import Persistence
import SwiftUI

struct SettingsNextStepsDebugView: View {

    let keyValueStore: ThrowingKeyValueStoring

    var body: some View {
        List {
            Section {
                Button {
                    resetDismissalState()
                } label: {
                    Text(verbatim: "Reset Next Steps state")
                }
                Button {
                    expireTapTimers()
                } label: {
                    Text(verbatim: "Expire Add to Dock / Add Widget timers")
                }
            } header: {
                Text(verbatim: "Dismissal state")
            } footer: {
                Text(verbatim: "Reset clears the tap timestamps and the hidden flag, so the section and its Add to Dock / Add Widget rows reappear. (The Set-Address-Bar and Voice-Search rows follow those settings, so they only come back if you change the setting back.) Expire back-dates both tap timers so those rows dismiss next time Settings opens.")
            }

            Section {
                Button {
                    simulateFifteenDaysSinceInstall()
                } label: {
                    Text(verbatim: "Simulate 15 days since install (reveal Hide button)")
                }
                Button {
                    resetInstallDateToToday()
                } label: {
                    Text(verbatim: "Reset install date to today")
                }
            } header: {
                Text(verbatim: "Hide button (14-day install gate)")
            } footer: {
                Text(verbatim: "Debug only: these change the GLOBAL app install date, which affects other install-gated features.")
            }
        }
        .navigationTitle(Text(verbatim: "Next Steps Dismissal"))
    }

    /// Clears the tap timestamps and the section-hidden flag so all rows and the section reappear.
    private func resetDismissalState() {
        try? keyValueStore.set(nil, forKey: SettingsViewModel.Constants.didTapAddToDockNextStepKey)
        try? keyValueStore.set(nil, forKey: SettingsViewModel.Constants.didTapAddWidgetNextStepKey)
        try? keyValueStore.set(nil, forKey: SettingsViewModel.Constants.nextStepsSectionHiddenKey)
        ActionMessageView.present(message: "Next Steps state reset — reopen Settings")
    }

    /// Back-dates both tap timestamps past the dismissal window so those rows dismiss on next open.
    private func expireTapTimers() {
        let expired = Date().timeIntervalSinceReferenceDate - SettingsViewModel.Constants.nextStepTapDismissalInterval - 1
        try? keyValueStore.set(expired, forKey: SettingsViewModel.Constants.didTapAddToDockNextStepKey)
        try? keyValueStore.set(expired, forKey: SettingsViewModel.Constants.didTapAddWidgetNextStepKey)
        ActionMessageView.present(message: "Add to Dock / Add Widget timers expired — reopen Settings")
    }

    private func simulateFifteenDaysSinceInstall() {
        StatisticsUserDefaults().installDate = Calendar.current.date(byAdding: .day, value: -15, to: Date())
        ActionMessageView.present(message: "Install date set to 15 days ago — reopen Settings")
    }

    private func resetInstallDateToToday() {
        StatisticsUserDefaults().installDate = Date()
        ActionMessageView.present(message: "Install date reset to today — reopen Settings")
    }
}
