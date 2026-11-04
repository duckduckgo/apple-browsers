//
//  AutoconsentManagementTests.swift
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

import XCTest
import WebExtensions
@testable import DuckDuckGo
@testable import Core
import PixelKit

final class AutoconsentManagementTests: XCTestCase {

    @MainActor
    func testWhenSummaryPixelFiresThenOnePixelIsSentPerSiteRank() {
        var firedPixels: [(name: String, parameters: [String: String])] = []
        PixelKit.setUp(
            dryRun: false,
            appVersion: "1.0.0",
            session: "test",
            defaultHeaders: [:],
            defaults: UserDefaults(suiteName: "test_\(UUID().uuidString)")!
        ) { name, _, parameters, _, _, completion in
            firedPixels.append((name, parameters))
            completion(true, nil)
        }
        defer { PixelKit.tearDown() }

        let management = AutoconsentManagement()
        let parameters = ["consentHeuristicEnabled": "tier1"]
        management.firePixel(pixel: .acInit, siteRank: .top10k, additionalParameters: parameters)
        management.firePixel(pixel: .acInit, siteRank: .other, additionalParameters: parameters)
        management.firePixel(pixel: .popupFound, siteRank: .other, additionalParameters: parameters)
        management.fireSummaryPixel()

        let summaries = firedPixels.filter { $0.name.contains("autoconsent_summary") }.map(\.parameters)
        XCTAssertEqual(summaries.count, 2)
        let top10k = summaries.first { $0["siteRank"] == "top10k" }
        let other = summaries.first { $0["siteRank"] == "other" }
        XCTAssertEqual(top10k?["init"], "1")
        XCTAssertEqual(top10k?["popup-found"], "0")
        XCTAssertEqual(other?["init"], "1")
        XCTAssertEqual(other?["popup-found"], "1")
        XCTAssertEqual(other?["consentHeuristicEnabled"], "tier1")
        XCTAssertTrue(firedPixels.filter { !$0.name.contains("autoconsent_summary") }.allSatisfy { $0.parameters["siteRank"] == nil })
    }
}
