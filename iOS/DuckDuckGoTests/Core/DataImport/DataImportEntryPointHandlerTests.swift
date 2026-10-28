//
//  DataImportEntryPointHandlerTests.swift
//  DuckDuckGoTests
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
@testable import DuckDuckGo

final class DataImportEntryPointHandlerTests: XCTestCase {

    private var featureFlagger: MockFeatureFlagger!

    override func setUp() {
        super.setUp()
        featureFlagger = MockFeatureFlagger()
    }

    override func tearDown() {
        featureFlagger = nil
        super.tearDown()
    }

    func testWhenSupportedOSAndFeatureEnabledThenDestinationIsHub() {
        featureFlagger.enabledFeatureFlags = [.dataImportNewUI]
        let sut = DataImportEntryPointHandler(
            featureFlagger: featureFlagger,
            isSupportedOSVersion: { true }
        )

        XCTAssertEqual(sut.destination(for: .passwords), .hub)
    }

    func testWhenSupportedOSAndFeatureDisabledThenDestinationIsLegacy() {
        let sut = DataImportEntryPointHandler(
            featureFlagger: featureFlagger,
            isSupportedOSVersion: { true }
        )

        XCTAssertEqual(sut.destination(for: .bookmarks), .legacy(importScreen: .bookmarks))
    }

    func testWhenUnsupportedOSAndFeatureEnabledThenDestinationIsLegacy() {
        featureFlagger.enabledFeatureFlags = [.dataImportNewUI]
        let sut = DataImportEntryPointHandler(
            featureFlagger: featureFlagger,
            isSupportedOSVersion: { false }
        )

        XCTAssertEqual(sut.destination(for: .settings), .legacy(importScreen: .settings))
    }

    func testWhenRoutingToLegacyThenSelectedImportScreenIsPreserved() {
        let sut = DataImportEntryPointHandler(
            featureFlagger: featureFlagger,
            isSupportedOSVersion: { false }
        )

        XCTAssertEqual(sut.destination(for: .whatsNew), .legacy(importScreen: .whatsNew))
    }
}
