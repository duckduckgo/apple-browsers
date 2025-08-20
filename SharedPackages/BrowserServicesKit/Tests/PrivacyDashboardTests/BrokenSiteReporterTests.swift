//
//  BrokenSiteReporterTests.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
@testable import PrivacyDashboard
import PersistenceTestingUtils

final class BrokenSiteReporterTests: XCTestCase {

    func testReport() throws {

        let expctation1 = expectation(description: "Pixel sent without lastSentDay")
        let expctation2 = expectation(description: "Pixel sent with lastSentDay ")
        var pixelCount = 0

        let keyValueStore = MockKeyValueStore()
        let reporter = BrokenSiteReporter(pixelHandler: { parameters in
            // Send pixel
            print("PIXEL SENT: \n\(parameters)")
            pixelCount += 1

            if pixelCount == 1, parameters["lastSentDay"] == nil {
                expctation1.fulfill()
            } else if pixelCount == 2, parameters["lastSentDay"] != nil {
                expctation2.fulfill()
            }
        }, keyValueStoring: keyValueStore)

        try reporter.report(BrokenSiteReportMocks.report, reportMode: .regular)

        // test second report, the pixel must have `lastSeenDate` param
        try reporter.report(BrokenSiteReportMocks.report, reportMode: .regular)

        waitForExpectations(timeout: 3)
    }

    func testReportContainsExperimentData() throws {
        let keyValueStore = MockKeyValueStore()
        let expectation = expectation(description: "Pixel sent")
        let reporter = BrokenSiteReporter(pixelHandler: { parameters in
            XCTAssertTrue(parameters["contentScopeExperiments"]!.contains("experiment1:control"))
            XCTAssertTrue(parameters["contentScopeExperiments"]!.contains("experiment2:treatment"))
            print(parameters)
            expectation.fulfill()
        }, keyValueStoring: keyValueStore)

        try reporter.report(BrokenSiteReportMocks.report, reportMode: .regular)

        waitForExpectations(timeout: 3)
    }
}
