//
//  VPNSettingsSessionHealthTests.swift
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

import Combine
import Foundation
import XCTest
@testable import VPN

final class VPNSettingsSessionHealthTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var settings: VPNSettings!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        suiteName = "session-health-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        settings = VPNSettings(defaults: defaults)
        cancellables = []
    }

    override func tearDown() {
        cancellables = nil
        defaults.removePersistentDomain(forName: suiteName)
        settings = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsToDisabledAndPersistsExplicitChanges() {
        XCTAssertFalse(settings.sessionHealthTelemetryEnabled)

        settings.sessionHealthTelemetryEnabled = true
        XCTAssertTrue(VPNSettings(defaults: defaults).sessionHealthTelemetryEnabled)

        settings.sessionHealthTelemetryEnabled = false
        XCTAssertFalse(VPNSettings(defaults: defaults).sessionHealthTelemetryEnabled)
    }

    func testResetToDefaultsClearsPersistedEnablement() {
        settings.sessionHealthTelemetryEnabled = true
        settings.resetToDefaults()

        XCTAssertFalse(settings.sessionHealthTelemetryEnabled)
        XCTAssertFalse(VPNSettings(defaults: defaults).sessionHealthTelemetryEnabled)
    }

    func testApplyingSettingChangeUpdatesEnablement() {
        settings.apply(change: .setSessionHealthTelemetryEnabled(true))
        XCTAssertTrue(settings.sessionHealthTelemetryEnabled)

        settings.apply(change: .setSessionHealthTelemetryEnabled(false))
        XCTAssertFalse(settings.sessionHealthTelemetryEnabled)
    }

    func testValuePublisherEmitsInitialAndUpdatedValues() {
        var values: [Bool] = []
        settings.sessionHealthTelemetryEnabledPublisher
            .removeDuplicates()
            .sink {
                values.append($0)
            }
            .store(in: &cancellables)

        settings.sessionHealthTelemetryEnabled = true
        settings.sessionHealthTelemetryEnabled = false
        XCTAssertEqual(values, [false, true, false])
    }

    func testChangePublisherSuppressesInitialValueAndDuplicateChanges() {
        var values: [Bool] = []
        settings.changePublisher
            .sink { change in
                if case .setSessionHealthTelemetryEnabled(let enabled) = change {
                    values.append(enabled)
                }
            }
            .store(in: &cancellables)

        XCTAssertTrue(values.isEmpty)

        settings.sessionHealthTelemetryEnabled = true
        settings.sessionHealthTelemetryEnabled = true
        settings.sessionHealthTelemetryEnabled = false
        XCTAssertEqual(values, [true, false])
    }

    func testWhenDebugRolloverIsChangedThenPersistenceRespectsBuildConfiguration() {
        XCTAssertFalse(settings.isSessionHealthDebugRolloverEnabled)
        settings.isSessionHealthDebugRolloverEnabled = true
#if DEBUG
        XCTAssertTrue(VPNSettings(defaults: defaults).isSessionHealthDebugRolloverEnabled)
#else
        XCTAssertFalse(VPNSettings(defaults: defaults).isSessionHealthDebugRolloverEnabled)
#endif
        settings.isSessionHealthDebugRolloverEnabled = false
        XCTAssertFalse(VPNSettings(defaults: defaults).isSessionHealthDebugRolloverEnabled)
    }

    func testWhenSettingsAreResetThenDebugRolloverIsDisabled() {
        settings.isSessionHealthDebugRolloverEnabled = true
        settings.resetToDefaults()

        XCTAssertFalse(settings.isSessionHealthDebugRolloverEnabled)
        XCTAssertFalse(VPNSettings(defaults: defaults).isSessionHealthDebugRolloverEnabled)
    }

    // MARK: - Startup snapshots

    func testSnapshotEncodingPreservesExplicitEnablement() throws {
        for enabled in [true, false] {
            settings.sessionHealthTelemetryEnabled = enabled
            let snapshot = VPNSettingsSnapshot(from: settings)

            let data = try JSONEncoder().encode(snapshot)
            let decoded = try JSONDecoder().decode(VPNSettingsSnapshot.self, from: data)

            XCTAssertEqual(decoded, snapshot, "Enablement: \(enabled)")
            XCTAssertEqual(decoded.sessionHealthTelemetryEnabled, enabled)
        }
    }

    func testApplyingSnapshotReplacesExistingEnablement() {
        for enabled in [true, false] {
            settings.sessionHealthTelemetryEnabled = enabled
            let snapshot = VPNSettingsSnapshot(from: settings)
            settings.sessionHealthTelemetryEnabled = !enabled

            snapshot.applyTo(settings)

            XCTAssertEqual(settings.sessionHealthTelemetryEnabled, enabled)
        }
    }

    func testStartupOptionsParseSessionHealthEnablement() throws {
        for enabled in [true, false] {
            settings.sessionHealthTelemetryEnabled = enabled
            let data = try JSONEncoder().encode(VPNSettingsSnapshot(from: settings))

            let options = StartupOptions(options: [NetworkProtectionOptionKey.settings: data])

            guard case .set(let parsed) = options.vpnSettings else {
                XCTFail("Expected explicit settings snapshot")
                return
            }
            XCTAssertEqual(parsed.sessionHealthTelemetryEnabled, enabled)
        }
    }

    func testLegacySnapshotWithoutSessionHealthFieldDecodesAsDisabled() throws {
        settings.sessionHealthTelemetryEnabled = true

        let encoded = try JSONEncoder().encode(VPNSettingsSnapshot(from: settings))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        json.removeValue(forKey: "sessionHealthTelemetryEnabled")

        let decoded = try JSONDecoder().decode(VPNSettingsSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(decoded.sessionHealthTelemetryEnabled)

        decoded.applyTo(settings)
        XCTAssertFalse(settings.sessionHealthTelemetryEnabled)
    }
}
