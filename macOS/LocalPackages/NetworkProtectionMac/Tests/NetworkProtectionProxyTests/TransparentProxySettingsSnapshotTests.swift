//
//  TransparentProxySettingsSnapshotTests.swift
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

import Foundation
@testable import NetworkProtectionProxy
import XCTest

final class TransparentProxySettingsSnapshotTests: XCTestCase {

    func testRoundTripsOrphanProxyFlags() throws {
        let snapshot = TransparentProxySettingsSnapshot(
            appRoutingRules: [:],
            excludedDomains: [],
            isOrphanProxyDetectionEnabled: false,
            isOrphanProxyBypassEnabled: false)

        let decoded = try JSONDecoder().decode(
            TransparentProxySettingsSnapshot.self,
            from: JSONEncoder().encode(snapshot))

        XCTAssertFalse(decoded.isOrphanProxyDetectionEnabled)
        XCTAssertFalse(decoded.isOrphanProxyBypassEnabled)
    }

    func testDefaultsOrphanProxyFlagsToEnabledWhenMissingFromPayload() throws {
        // A snapshot persisted by an older version that predates the flags.
        let legacyJSON = """
        {"appRoutingRules":{},"excludedDomains":[]}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(TransparentProxySettingsSnapshot.self, from: legacyJSON)

        XCTAssertTrue(decoded.isOrphanProxyDetectionEnabled)
        XCTAssertTrue(decoded.isOrphanProxyBypassEnabled)
    }

    func testSettingsRoundTripThroughSnapshot() {
        let defaults = UserDefaults(suiteName: "orphan-proxy-settings-test")!
        defer { defaults.removePersistentDomain(forName: "orphan-proxy-settings-test") }

        let settings = TransparentProxySettings(defaults: defaults)
        XCTAssertTrue(settings.isOrphanProxyDetectionEnabled)
        XCTAssertTrue(settings.isOrphanProxyBypassEnabled)

        settings.isOrphanProxyDetectionEnabled = false
        settings.isOrphanProxyBypassEnabled = false

        let applied = TransparentProxySettings(defaults: UserDefaults(suiteName: "orphan-proxy-applied-test")!)
        defer { applied.defaults.removePersistentDomain(forName: "orphan-proxy-applied-test") }
        applied.apply(settings.snapshot())

        XCTAssertFalse(applied.isOrphanProxyDetectionEnabled)
        XCTAssertFalse(applied.isOrphanProxyBypassEnabled)
    }
}
