//
//  TranslationDebugSettingsTests.swift
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

final class TranslationDebugSettingsTests: XCTestCase {

    // MARK: - Helpers

    /// Ephemeral, isolated defaults per test.
    private func makeEphemeralDefaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "test.translationDebug.\(UUID().uuidString)")!
        return d
    }

    // MARK: - Tests

    func test_defaults() {
        let s = TranslationDebugSettings(defaults: makeEphemeralDefaults())
        XCTAssertEqual(s.extractionScope, .batches)
        XCTAssertEqual(s.detector, .naturalLanguage)
        XCTAssertFalse(s.diagnosticReportEnabled)
        XCTAssertEqual(s.detectionInput, .htmlFirst50)
    }

    func test_roundTrip_extractionScope() {
        let d = makeEphemeralDefaults()
        TranslationDebugSettings(defaults: d).extractionScope = .viewportOnly
        XCTAssertEqual(TranslationDebugSettings(defaults: d).extractionScope, .viewportOnly)
    }

    func test_roundTrip_detector() {
        let d = makeEphemeralDefaults()
        TranslationDebugSettings(defaults: d).detector = .cld2
        XCTAssertEqual(TranslationDebugSettings(defaults: d).detector, .cld2)
    }

    func test_roundTrip_diagnosticReport() {
        let d = makeEphemeralDefaults()
        TranslationDebugSettings(defaults: d).diagnosticReportEnabled = true
        XCTAssertTrue(TranslationDebugSettings(defaults: d).diagnosticReportEnabled)
    }

    func test_roundTrip_detectionInput() {
        let d = makeEphemeralDefaults()
        TranslationDebugSettings(defaults: d).detectionInput = .textFullPage
        XCTAssertEqual(TranslationDebugSettings(defaults: d).detectionInput, .textFullPage)
    }
}
