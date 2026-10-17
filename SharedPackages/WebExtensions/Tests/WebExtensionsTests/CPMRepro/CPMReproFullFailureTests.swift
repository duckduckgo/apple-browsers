//
//  CPMReproFullFailureTests.swift
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
@testable import WebExtensions

/// Full failure: one fault must not leave every tab, including documents loaded earlier, without
/// CPM. These run the app's path (navigation gate, M4) and must pass.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMReproFullFailureTests: CPMReproTestCase {

    // MARK: Faults that WebKit already recovers from

    func testMemoryPressureKeepsEveryTabWorking() async throws {
        try requireLocalRun()
        let report = try await runFullFailureScenario(fault: .memoryPressure)
        XCTAssertFalse(report.allOutcomes.contains(.timedOut), "\(report)")
    }

    func testBackgroundFreezeKeepsEveryTabWorking() async throws {
        try requireLocalRun()
        let report = try await runFullFailureScenario(fault: .backgroundFreeze)
        XCTAssertFalse(report.allOutcomes.contains(.timedOut), "\(report)")
    }

    /// The in-flight message itself is lost when WebKit unloads the frozen background; the tabs
    /// must work afterwards.
    func testBackgroundFreezeWithMessageInFlightKeepsEveryTabWorking() async throws {
        try requireLocalRun()
        let report = try await runFullFailureScenario(fault: .backgroundFreezeWithMessageInFlight)
        XCTAssertFalse(report.allOutcomes.contains(.timedOut), "\(report)")
    }
}
