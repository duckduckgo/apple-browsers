//
//  AutoplayPreferencesTests.swift
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
import WebKit
@testable import DuckDuckGo_Privacy_Browser

final class AutoplayPreferencesPersistorMock: AutoplayPreferencesPersistor {
    var autoplayBlockingModeRawValue: String
    init(autoplayBlockingModeRawValue: String) {
        self.autoplayBlockingModeRawValue = autoplayBlockingModeRawValue
    }
}

final class AutoplayPreferencesTests: XCTestCase {

    // MARK: - Default value

    func testDefaultModeIsBlockAudio() {
        let persistor = AutoplayPreferencesPersistorMock(autoplayBlockingModeRawValue: AutoplayBlockingMode.blockAudio.rawValue)
        let prefs = AutoplayPreferences(persistor: persistor)
        XCTAssertEqual(prefs.autoplayBlockingMode, .blockAudio)
    }

    func testWhenPersistedValueIsInvalidThenDefaultsToBlockAudio() {
        let persistor = AutoplayPreferencesPersistorMock(autoplayBlockingModeRawValue: "invalidValue")
        let prefs = AutoplayPreferences(persistor: persistor)
        XCTAssertEqual(prefs.autoplayBlockingMode, .blockAudio)
    }

    // MARK: - Persistence round-trip

    func testWhenModeIsSetThenPersistorIsUpdated() {
        let persistor = AutoplayPreferencesPersistorMock(autoplayBlockingModeRawValue: AutoplayBlockingMode.blockAudio.rawValue)
        let prefs = AutoplayPreferences(persistor: persistor)

        prefs.autoplayBlockingMode = .allowAll

        XCTAssertEqual(persistor.autoplayBlockingModeRawValue, AutoplayBlockingMode.allowAll.rawValue)
    }

    func testAllModesRoundTrip() {
        for mode in AutoplayBlockingMode.allCases {
            let persistor = AutoplayPreferencesPersistorMock(autoplayBlockingModeRawValue: mode.rawValue)
            let prefs = AutoplayPreferences(persistor: persistor)
            XCTAssertEqual(prefs.autoplayBlockingMode, mode, "Read round-trip failed for mode: \(mode)")
        }
    }

    // MARK: - WKAudiovisualMediaTypes mapping

    func testAllowAllMapsToEmptyMediaTypes() {
        XCTAssertEqual(AutoplayBlockingMode.allowAll.mediaTypesRequiringUserAction, [])
    }

    func testBlockAudioMapsToAudioOnly() {
        XCTAssertEqual(AutoplayBlockingMode.blockAudio.mediaTypesRequiringUserAction, .audio)
    }

    func testBlockAllMapsToAll() {
        XCTAssertEqual(AutoplayBlockingMode.blockAll.mediaTypesRequiringUserAction, .all)
    }

    // MARK: - objectWillChange

    func testObjectWillChangeFiresOnModeChange() {
        let persistor = AutoplayPreferencesPersistorMock(autoplayBlockingModeRawValue: AutoplayBlockingMode.blockAudio.rawValue)
        let prefs = AutoplayPreferences(persistor: persistor)

        let expectation = expectation(description: "objectWillChange fires")
        let cancellable = prefs.objectWillChange.sink { expectation.fulfill() }

        prefs.autoplayBlockingMode = .blockAll
        waitForExpectations(timeout: 0)
        withExtendedLifetime(cancellable) {}
    }
}
