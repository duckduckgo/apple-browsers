//
//  ToggleReportingFlow.swift
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

import Foundation

@MainActor
final class ToggleReportingFlow {

    enum EntryPoint {

        case appMenuProtectionsOff(completionHandler: (Bool) -> Void)
        case dashboardProtectionsOff(protectionStateToSubmitOnDismiss: ProtectionState)

        var source: BrokenSiteReport.Source {
            switch self {
            case .appMenuProtectionsOff: return .onProtectionsOffMenu
            case .dashboardProtectionsOff: return .onProtectionsOffDashboard
            }
        }

    }

    // iOS and macOS implementations differ here: on macOS app, after the user taps 'Send Report',
    // no immediate action should be triggered due to the subsequent 'Thank you' screen.
    // Processing of the toggle report should only proceed once the user dismisses the 'Thank you' screen.
#if os(iOS)
    var shouldHandlePendingProtectionStateChangeOnReportSent: Bool = true
#else
    var shouldHandlePendingProtectionStateChangeOnReportSent: Bool = false
#endif

    weak var privacyDashboardController: PrivacyDashboardController?
    var toggleReportingManager: ToggleReportingManaging

    let entryPoint: EntryPoint

    // We need to know if the user chose to send a report. On macOS browser, the "Thank You" prompt is shown afterward.
    // If the user dismisses that prompt, handleDismissal is triggered,
    // but calling recordDismissal within it would be incorrect at that stage.
    private var didSendReport = false

    init(entryPoint: EntryPoint,
         toggleReportingManager: ToggleReportingManaging,
         controller: PrivacyDashboardController?) {
        self.entryPoint = entryPoint
        self.toggleReportingManager = toggleReportingManager
        self.privacyDashboardController = controller
    }

    func handleViewWillDisappear() {
        handleDismissal(isUserAction: true)
    }

    func userScriptDidRequestClose() {
        handleDismissal()
    }

    func userScriptDidSelectReportAction(shouldSendReport: Bool) {
        if shouldSendReport {
            handleSendReport()
        } else {
            handleDismissal()
        }
    }

    private func handleDismissal(isUserAction: Bool = false) {
        if !didSendReport {
            toggleReportingManager.recordDismissal(date: Date())
        }
        switch entryPoint {
        case .appMenuProtectionsOff(let completionHandler):
            completionHandler(false)
        case .dashboardProtectionsOff(let protectionStateToSubmitOnDismiss):
            privacyDashboardController?.didChangeProtectionState(to: protectionStateToSubmitOnDismiss, didSendReport: false)
        }
        if !isUserAction {
            privacyDashboardController?.didRequestClose()
        }
    }

    private func handleSendReport() {
        privacyDashboardController?.didRequestSubmitToggleReport(with: entryPoint.source)
        toggleReportingManager.recordPrompt(date: Date())
        didSendReport = true
        switch entryPoint {
        case .appMenuProtectionsOff(let completionHandler):
            completionHandler(true)
        case .dashboardProtectionsOff(let protectionStateToSubmitOnDismiss):
            if shouldHandlePendingProtectionStateChangeOnReportSent {
                privacyDashboardController?.didChangeProtectionState(to: protectionStateToSubmitOnDismiss, didSendReport: true)
                privacyDashboardController?.didRequestClose()
            }
        }
    }

}
