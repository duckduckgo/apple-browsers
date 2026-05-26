//
//  DuckPlayerPreferencesTests.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import FeatureFlags
import Foundation
import PrivacyConfig
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class DuckPlayerPreferencesTests: XCTestCase {

    func testWhenInitializedThenItLoadsPersistedValues() throws {
        var model = DuckPlayerPreferences(
            persistor: DuckPlayerPreferencesPersistorMock(
                duckPlayerMode: .alwaysAsk,
                youtubeOverlayInteracted: false,
                youtubeOverlayAnyButtonPressed: false
            )
        )

        XCTAssertEqual(model.duckPlayerMode, .alwaysAsk)
        XCTAssertEqual(model.youtubeOverlayInteracted, false)
        XCTAssertEqual(model.youtubeOverlayAnyButtonPressed, false)

        model = DuckPlayerPreferences(
            persistor: DuckPlayerPreferencesPersistorMock(
                duckPlayerMode: .enabled,
                youtubeOverlayInteracted: true,
                youtubeOverlayAnyButtonPressed: true
            )
        )

        XCTAssertEqual(model.duckPlayerMode, .enabled)
        XCTAssertEqual(model.youtubeOverlayInteracted, true)
        XCTAssertEqual(model.youtubeOverlayAnyButtonPressed, true)
    }

    func testWhenPropertiesAreUpdatedThenPersistedValuesAreUpdated() throws {
        let persistor = DuckPlayerPreferencesPersistorMock()
        let model = DuckPlayerPreferences(persistor: persistor)

        model.duckPlayerMode = .enabled
        XCTAssertEqual(persistor.duckPlayerModeBool, true)
        model.duckPlayerMode = .disabled
        XCTAssertEqual(persistor.duckPlayerModeBool, false)
        model.duckPlayerMode = .alwaysAsk
        XCTAssertEqual(persistor.duckPlayerModeBool, nil)

        model.youtubeOverlayInteracted = true
        XCTAssertEqual(persistor.youtubeOverlayInteracted, true)
        model.youtubeOverlayInteracted = false
        XCTAssertEqual(persistor.youtubeOverlayInteracted, false)

        model.youtubeOverlayAnyButtonPressed = true
        XCTAssertEqual(persistor.youtubeOverlayAnyButtonPressed, true)
        model.youtubeOverlayAnyButtonPressed = false
        XCTAssertEqual(persistor.youtubeOverlayAnyButtonPressed, false)
    }

    func testPersisterReturnsValuesFromDisk() {
        UserDefaultsWrapper<Any>.clearAll()
        let persister1 = DuckPlayerPreferencesUserDefaultsPersistor()
        let persister2 = DuckPlayerPreferencesUserDefaultsPersistor()

        persister2.duckPlayerModeBool = nil
        persister1.duckPlayerModeBool = true
        persister2.youtubeOverlayInteracted = false
        persister1.youtubeOverlayInteracted = true
        persister2.youtubeOverlayAnyButtonPressed = false
        persister1.youtubeOverlayAnyButtonPressed = true

        XCTAssertTrue(persister2.duckPlayerModeBool!)
        XCTAssertTrue(persister2.youtubeOverlayInteracted)
        XCTAssertTrue(persister2.youtubeOverlayAnyButtonPressed)
    }

    // MARK: - Rollout-aware default

    func testWhenPersistorBoolIsNilAndRolloutOffThenCachedModeIsAlwaysAsk() {
        let persistor = DuckPlayerPreferencesPersistorMock(duckPlayerMode: .alwaysAsk)
        let model = DuckPlayerPreferences(persistor: persistor, featureFlagger: MockFeatureFlagger())

        XCTAssertEqual(model.duckPlayerMode, .alwaysAsk)
        XCTAssertNil(persistor.duckPlayerModeBool)
    }

    func testWhenPersistorBoolIsNilAndRolloutOnThenCachedModeIsDisabled() {
        let persistor = DuckPlayerPreferencesPersistorMock(duckPlayerMode: .alwaysAsk)
        let featureFlagger = MockFeatureFlagger(featuresStub: [FeatureFlag.adBlockingExtensionEnabledByDefault.rawValue: true])
        let model = DuckPlayerPreferences(persistor: persistor, featureFlagger: featureFlagger)

        XCTAssertEqual(model.duckPlayerMode, .disabled)
        XCTAssertNil(persistor.duckPlayerModeBool, "Rollout default must not be persisted")
    }

    func testWhenPersistorBoolIsExplicitThenRolloutDoesNotChangeMode() {
        let persistor = DuckPlayerPreferencesPersistorMock(duckPlayerMode: .enabled)
        let featureFlagger = MockFeatureFlagger(featuresStub: [FeatureFlag.adBlockingExtensionEnabledByDefault.rawValue: true])
        let model = DuckPlayerPreferences(persistor: persistor, featureFlagger: featureFlagger)

        XCTAssertEqual(model.duckPlayerMode, .enabled)
    }

    // MARK: - refreshDefaultModeIfNeeded (publisher-triggered)

    func testPublisherTriggerUpdatesCachedModeForNilPersistor() {
        let persistor = DuckPlayerPreferencesPersistorMock(duckPlayerMode: .alwaysAsk)
        let featureFlagger = MockFeatureFlagger()
        let model = DuckPlayerPreferences(persistor: persistor, featureFlagger: featureFlagger)
        XCTAssertEqual(model.duckPlayerMode, .alwaysAsk)

        featureFlagger.featuresStub[FeatureFlag.adBlockingExtensionEnabledByDefault.rawValue] = true
        featureFlagger.triggerUpdate()
        drainMainQueue()

        XCTAssertEqual(model.duckPlayerMode, .disabled)
        XCTAssertNil(persistor.duckPlayerModeBool, "Publisher-driven update must not persist")
    }

    func testPublisherTriggerDoesNotChangeModeForExplicitPersistor() {
        let persistor = DuckPlayerPreferencesPersistorMock(duckPlayerMode: .enabled)
        let featureFlagger = MockFeatureFlagger()
        let model = DuckPlayerPreferences(persistor: persistor, featureFlagger: featureFlagger)
        XCTAssertEqual(model.duckPlayerMode, .enabled)

        featureFlagger.featuresStub[FeatureFlag.adBlockingExtensionEnabledByDefault.rawValue] = true
        featureFlagger.triggerUpdate()
        drainMainQueue()

        XCTAssertEqual(model.duckPlayerMode, .enabled, "Explicit user choice must be preserved")
        XCTAssertEqual(persistor.duckPlayerModeBool, true)
    }

    // MARK: - Helpers

    private func drainMainQueue() {
        let exp = expectation(description: "main queue drained")
        DispatchQueue.main.async { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)
    }
}
