//
//  HistoryViewOnboardingViewModelTests.swift
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

final class HistoryViewOnboardingViewModelTests: XCTestCase {

    var settingsStorage: MockHistoryViewOnboardingViewSettingsPersistor!
    var viewModel: HistoryViewOnboardingViewModel!
    var ctaCalls: [Bool] = []

    override func setUp() async throws {
        settingsStorage = MockHistoryViewOnboardingViewSettingsPersistor()
        ctaCalls = []
        viewModel = HistoryViewOnboardingViewModel(
            settingsStorage: settingsStorage,
            ctaCallback: { self.ctaCalls.append($0) }
        )
    }

    func testThatMarkAsShownUpdatesStorageAndDoesNotTriggerCTA() throws {
        viewModel.markAsShown()
        XCTAssertEqual(ctaCalls.count, 0)
        XCTAssertTrue(settingsStorage.didShowOnboardingView)
    }

    func testThatNotNowDoesTriggersCTAWithFalse() throws {
        viewModel.notNow()
        XCTAssertEqual(ctaCalls, [false])
    }

    func testThatShowHistoryTriggersCTAWithTrue() throws {
        viewModel.showHistory()
        XCTAssertEqual(ctaCalls, [true])
    }
}
