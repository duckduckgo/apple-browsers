//
//  PrivacyDashboardDelegateMock.swift
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
import PrivacyDashboard

final class PrivacyDashboardDelegateMock: PrivacyDashboardControllerDelegate {

    var didChangeProtectionSwitchCalled = false
    var protectionState: ProtectionState?
    var didSendReport = false
    var didRequestCloseCalled = false
    var didRequestSubmitToggleReport = false

    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController,
                                    didChangeProtectionSwitch protectionState: ProtectionState,
                                    didSendReport: Bool) {
        didChangeProtectionSwitchCalled = true
        self.protectionState = protectionState
        self.didSendReport = didSendReport

    }
    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController,
                                    didRequestSubmitToggleReportWithSource source: BrokenSiteReport.Source) {
        didRequestSubmitToggleReport = true
    }

    func privacyDashboardControllerDidRequestClose(_ privacyDashboardController: PrivacyDashboardController) {
        didRequestCloseCalled = true
    }

    // not under tests

    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController, didRequestOpenUrlInNewTab url: URL) {}
    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController,
                                    didRequestOpenSettings target: PrivacyDashboardOpenSettingsTarget) {}
    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController,
                                    didRequestSubmitBrokenSiteReportWithCategory category: String,
                                    description: String) {}
    func privacyDashboardControllerDidRequestShowGeneralFeedback(_ privacyDashboardController: PrivacyDashboardController) {}
    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController, didSetHeight height: Int) {}
    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController,
                                    didSetPermission permissionName: String,
                                    to state: PermissionAuthorizationState) {}
    func privacyDashboardController(_ privacyDashboardController: PrivacyDashboardController, setPermission permissionName: String, paused: Bool) { }

}
