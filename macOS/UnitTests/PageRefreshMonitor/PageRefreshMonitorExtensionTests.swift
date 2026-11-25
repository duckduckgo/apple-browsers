//
//  PageRefreshMonitorExtensionTests.swift
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
@testable import PixelExperimentKit
import PageRefreshMonitor
import BrowserServicesKit

final class PageRefreshMonitorExtensionTests: XCTestCase {

    private func capturedMetric(after refreshes: Int) -> String? {
        var captured: String?
        PageRefreshMonitor.onDidDetectRefreshPattern(refreshes) { _, metric, _, _ in
            captured = metric
        }
        return captured
    }

    func test_OnDidDetectRefreshPattern_WithValue1_FireExperimentFuncNotCalled() throws {
        XCTAssertNil(capturedMetric(after: 1))
    }

    func test_OnDidDetectRefreshPattern_WithValue2_ExpectedFireExperimentFuncCalled() throws {
        XCTAssertEqual(capturedMetric(after: 2), "2XRefresh")
    }

    func test_OnDidDetectRefreshPattern_WithValue3_ExpectedFireExperimentFuncCalled() throws {
        XCTAssertEqual(capturedMetric(after: 3), "3XRefresh")
    }

    func test_OnDidDetectRefreshPattern_WithValue4_FireExperimentFuncNotCalled() throws {
        XCTAssertNil(capturedMetric(after: 4))
    }

}
