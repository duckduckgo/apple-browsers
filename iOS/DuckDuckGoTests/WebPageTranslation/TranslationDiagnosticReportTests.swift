//
//  TranslationDiagnosticReportTests.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
@testable import DuckDuckGo

final class TranslationDiagnosticReportTests: XCTestCase {

    private func makeBergamot() -> TranslationDiagnosticReport.Bergamot {
        TranslationDiagnosticReport.Bergamot(modelTier: "base-memory", modelLoadSeconds: 1.2,
                                             downloadBytes: nil, downloadSeconds: nil)
    }

    func test_summaryLines_includesCoreFields() {
        let report = TranslationDiagnosticReport(
            engine: "Bergamot",
            languagePair: "es\u{2192}en",
            extractionScope: "fullPage",
            detector: "cld2",
            detectionInput: "htmlFirst50",
            detectedSourceLanguage: "es",
            detectionSeconds: 0.042,
            nodesExtracted: 100,
            uniqueUnits: 80,
            viewportCount: 10,
            timeToViewportSeconds: 1.5,
            fullPageSeconds: 6.4,
            throughput: 12.5,
            bergamot: makeBergamot(),
            errorMessage: nil
        )

        let joined = report.summaryLines.joined(separator: "\n")
        XCTAssertTrue(joined.contains("Bergamot"), "should contain engine name")
        XCTAssertTrue(joined.contains("es\u{2192}en"), "should contain language pair")
        XCTAssertTrue(joined.contains("cld2"), "should contain detector")
        XCTAssertTrue(joined.contains("base-memory"), "should contain model tier")
        XCTAssertTrue(joined.contains("6.4"), "should contain full page seconds")
        XCTAssertTrue(joined.contains("0.042"), "should contain detection seconds")
    }

    func test_summaryLines_errorMessage_appearsNearTop() {
        let report = TranslationDiagnosticReport(
            engine: "Bergamot",
            languagePair: "es\u{2192}en",
            extractionScope: "batches",
            detector: "cld2",
            detectionInput: "textFirst50",
            detectedSourceLanguage: "es",
            detectionSeconds: nil,
            nodesExtracted: 0,
            uniqueUnits: 0,
            viewportCount: 0,
            timeToViewportSeconds: nil,
            fullPageSeconds: 0.1,
            throughput: 0,
            bergamot: nil,
            errorMessage: "Bergamot spike supports es↔en only."
        )

        let lines = report.summaryLines
        XCTAssertFalse(lines.isEmpty, "should have at least one line")
        XCTAssertTrue(lines[0].contains("Error"), "error message should be first line")
        let joined = lines.joined(separator: "\n")
        XCTAssertTrue(joined.contains("Bergamot spike supports es↔en only."), "should contain error text")
    }
}
