//
//  ScriptSourceProviderTests.swift
//  DuckDuckGo
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
import Common
import BrowserServicesKit
import TrackerRadarKit
@testable import DuckDuckGo
import Combine

final class ScriptSourceProviderTests: XCTestCase {

    var experimentManager: MockContentScopeExperimentManager!
    let testExperimentData = ExperimentData(
        parentID: "parent",
        cohortID: "aCohort",
        enrollmentDate: Date()
    )

    override func setUpWithError() throws {
        experimentManager = MockContentScopeExperimentManager()
    }

    override func tearDownWithError() throws {
        experimentManager = nil
    }

    @MainActor
    func testCohortDataInitialisedCorrectly() throws {
        let expectedCohortData = ContentScopeExperimentData(feature: testExperimentData.parentID, subfeature: "test", cohort: testExperimentData.cohortID)
        let experimentManager = MockContentScopeExperimentManager()
        experimentManager.allActiveContentScopeExperiments = ["test": testExperimentData]

        let sourceProvider = DefaultScriptSourceProvider(appSettings: AppSettingsMock(), privacyConfigurationManager: MockPrivacyConfigurationManager(), contentBlockingManager: MockContentBlockerRulesManagerProtocol(), fireproofing: MockFireproofing(), contentScopeExperimentsManager: experimentManager)

        let cohorts = try XCTUnwrap(sourceProvider.currentCohorts)
        XCTAssertFalse(cohorts.isEmpty)
        XCTAssertEqual(cohorts[0], expectedCohortData)
        XCTAssertTrue(experimentManager.resolveContentScopeScriptActiveExperimentsCalled)
    }

}

class MockContentBlockerRulesManagerProtocol: ContentBlockerRulesManagerProtocol {
    func entity(forHost host: String) -> Entity? {
        return nil
    }

    var updatesPublisher: AnyPublisher<ContentBlockerRulesManager.UpdateEvent, Never> = Empty<ContentBlockerRulesManager.UpdateEvent, Never>(completeImmediately: false).eraseToAnyPublisher()

    var currentRules: [BrowserServicesKit.ContentBlockerRulesManager.Rules] = []

    func scheduleCompilation() -> ContentBlockerRulesManager.CompletionToken {
        return ContentBlockerRulesManager.CompletionToken()
    }

    var currentMainRules: ContentBlockerRulesManager.Rules?

    var currentAttributionRules: ContentBlockerRulesManager.Rules?
}
