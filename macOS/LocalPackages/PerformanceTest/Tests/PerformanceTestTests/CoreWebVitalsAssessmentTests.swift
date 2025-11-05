//
//  CoreWebVitalsAssessmentTests.swift
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

import XCTest
@testable import PerformanceTest

final class CoreWebVitalsAssessmentTests: XCTestCase {

    func testLCPAssessment_withGoodScore_returnsGood() {
        let assessment = CoreWebVitalsAssessment(lcp: 2.0, fid: nil, cls: nil)
        XCTAssertEqual(assessment.lcpAssessment, "Good")
    }

    func testLCPAssessment_withPoorScore_returnsPoor() {
        let assessment = CoreWebVitalsAssessment(lcp: 5.0, fid: nil, cls: nil)
        XCTAssertEqual(assessment.lcpAssessment, "Poor")
    }

    func testFIDAssessment_withGoodScore_returnsGood() {
        let assessment = CoreWebVitalsAssessment(lcp: 2.0, fid: 0.05, cls: nil)
        XCTAssertEqual(assessment.fidAssessment, "Good")
    }

    func testCLSAssessment_withPoorScore_returnsPoor() {
        let assessment = CoreWebVitalsAssessment(lcp: 2.0, fid: nil, cls: 0.5)
        XCTAssertEqual(assessment.clsAssessment, "Poor")
    }

    func testOverallAssessment_withMixedScores_returnsWorstCategory() {
        let goodAssessment = CoreWebVitalsAssessment(lcp: 2.0, fid: 0.05, cls: 0.05)
        XCTAssertEqual(goodAssessment.overallAssessment, "Good")

        let poorAssessment = CoreWebVitalsAssessment(lcp: 5.0, fid: 0.05, cls: 0.05)
        XCTAssertEqual(poorAssessment.overallAssessment, "Poor")

        let needsImprovementAssessment = CoreWebVitalsAssessment(lcp: 3.0, fid: 0.2, cls: 0.05)
        XCTAssertEqual(needsImprovementAssessment.overallAssessment, "Needs Improvement")
    }
}
