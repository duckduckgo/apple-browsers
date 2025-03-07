//
//  DefaultBrowserAndDockPromptExperimentDeciderTests.swift
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
@testable import DuckDuckGo_Privacy_Browser

class DefaultBrowserAndDockPromptExperimentDeciderTests: XCTestCase {

    func testIsUserEligibleForExperiment() {
        let decider = DefaultBrowserAndDockPromptExperimentDecider(
            isOnboardingCompleted: true,
            isNewUser: false,
            isEligibleForPrompt: true
        )

        let isEligible = decider.isUserEligibleForExperiment

        XCTAssertTrue(isEligible)
    }

    func testIsUserNotEligibleForExperimentWhenNewUser() {
        let decider = DefaultBrowserAndDockPromptExperimentDecider(
            isOnboardingCompleted: true,
            isNewUser: true,
            isEligibleForPrompt: true
        )

        let isEligible = decider.isUserEligibleForExperiment

        XCTAssertFalse(isEligible)
    }

    func testUserNotEligibleForExperimentWhenOnboardingNotCompleted() {
        let decider = DefaultBrowserAndDockPromptExperimentDecider(
            isOnboardingCompleted: false,
            isNewUser: false,
            isEligibleForPrompt: true
        )

        let isEligible = decider.isUserEligibleForExperiment

        XCTAssertFalse(isEligible)
    }

    func testUserNotEligibleForExperimentWhenNotEligibleForPrompt() {
        let decider = DefaultBrowserAndDockPromptExperimentDecider(
            isOnboardingCompleted: true,
            isNewUser: false,
            isEligibleForPrompt: false
        )

        let isEligible = decider.isUserEligibleForExperiment

        XCTAssertFalse(isEligible)
    }
}
