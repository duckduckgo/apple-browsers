//
//  PrivacyDashboardTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import XCTest
import BrowserServicesKit
import PrivacyDashboard
import Common
import PixelKit
@testable import DuckDuckGo_Privacy_Browser

final class PrivacyDashboardTests: XCTestCase {
    var capturedPixelEvent: PixelKitEvent?
    var capturedPixelParameters: [String: String] = [:]

    @MainActor
    func testPrivacyDashboardSendExperimentsCohortInBreakageReport() async {
        // GIVEN
        let expectation = XCTestExpectation()
        let configManager = MockPrivacyConfigurationManaging()
        let testExperimentData = ExperimentData(
            parentID: "parent",
            cohortID: "aCohort",
            enrollmentDate: Date()
        )

        let experimentManager = MockContentScopeExperimentManager()
        experimentManager.allActiveContentScopeExperiments = ["test": testExperimentData]
        let vc = PrivacyDashboardViewController(contentScopeExperimentsManager: experimentManager, pixelFiring: {event, parameters, _ in
            self.capturedPixelEvent = event
            self.capturedPixelParameters = parameters ?? [:]
            expectation.fulfill()
        })
        let tab = Tab(content: .url(URL.duckDuckGo, source: .ui))
        let tabViewModel = TabViewModel(tab: tab)
        vc.updateTabViewModel(tabViewModel)
        let privacyDashboardController = PrivacyDashboardController(privacyInfo: nil, entryPoint: .dashboard, toggleReportingManager: ToggleReportingManagerMock(), eventMapping: EventMapping<PrivacyDashboardEvents> { _, _, _, _ in })

        // WHEN
        vc.privacyDashboardController(privacyDashboardController, didRequestSubmitBrokenSiteReportWithCategory: "SomeCategory", description: "SomeDescription")

        // THEN
        await fulfillment(of: [expectation], timeout: 3)
        XCTAssertEqual(capturedPixelEvent?.name, "epbf_macos_desktop")
        XCTAssertEqual(capturedPixelParameters["contentScopeExperiments"], "test:aCohort")
    }

}

class MockContentScopeExperimentManager: ContentScopeExperimentsManaging {
    var allActiveContentScopeExperiments: Experiments = [:]

    func resolveContentScopeScriptActiveExperiments() -> Experiments {
        return allActiveContentScopeExperiments
    }
}

final class ToggleReportingManagerMock: ToggleReportingManaging {

    var recordDismissalCalled: Bool = false
    var recordPromptCalled: Bool = false

    func recordDismissal(date: Date) {
        recordDismissalCalled = true
    }

    func recordPrompt(date: Date) {
        recordPromptCalled = true
    }

    var shouldShowToggleReport: Bool { return true }

}
