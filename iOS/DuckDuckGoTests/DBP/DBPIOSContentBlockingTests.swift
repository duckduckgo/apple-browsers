//
//  DBPIOSContentBlockingTests.swift
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

import BrowserServicesKit
import TrackerRadarKit
import WebKit
import XCTest

@testable import DuckDuckGo

@MainActor
final class DBPIOSContentBlockingTests: XCTestCase {

    func testWhenRulesSourceIsEmpty_thenContentRuleListsIsEmptyAndSurrogateTrackerDataIsNil() {
        let source = StubCompiledRuleListsSource(currentRules: [])
        let sut = DBPIOSContentBlocking(contentBlockingManager: source)

        XCTAssertTrue(sut.contentRuleLists.isEmpty)
        XCTAssertNil(sut.surrogateTrackerData)
    }
}

private final class StubCompiledRuleListsSource: CompiledRuleListsSource {
    let currentRules: [ContentBlockerRulesManager.Rules]
    var currentMainRules: ContentBlockerRulesManager.Rules? { currentRules.first }
    var currentAttributionRules: ContentBlockerRulesManager.Rules? { nil }
    init(currentRules: [ContentBlockerRulesManager.Rules]) {
        self.currentRules = currentRules
    }
}
