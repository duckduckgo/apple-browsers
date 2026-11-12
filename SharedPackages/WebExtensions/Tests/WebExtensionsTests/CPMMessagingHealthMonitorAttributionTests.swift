//
//  CPMMessagingHealthMonitorAttributionTests.swift
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

@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMMessagingHealthMonitorAttributionTests: XCTestCase {

    private let monitor = CPMMessagingHealthMonitor(pixelFiring: NoOpWebExtensionPixelFiring())
    private let pageURL = URL(string: "https://example.com/a")!
    private var healthyResponses = 0

    override func setUp() async throws {
        monitor.onHealthyResponse = { [unowned self] in self.healthyResponses += 1 }
    }

    func testResponseFromTheCurrentExtensionIsAHealthyResponse() {
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 1, url: pageURL))

        XCTAssertEqual(healthyResponses, 1)
    }

    func testResponseFromAnOldEmbeddedExtensionIsIgnored() {
        monitor.isCurrentEmbeddedExtension = { $0 == "current" }
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 1, url: pageURL, extensionIdentifier: "old"))
        XCTAssertEqual(healthyResponses, 0)

        monitor.handle(.dashboardResponse(extensionTabIdentifier: 1, url: pageURL, extensionIdentifier: "current"))
        XCTAssertEqual(healthyResponses, 1)
    }

    func testBreakageSimulationHidesResponses() {
        monitor.setBreakageSimulationEnabled(true)
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 1, url: pageURL))
        XCTAssertEqual(healthyResponses, 0)

        monitor.setBreakageSimulationEnabled(false)
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 1, url: pageURL))
        XCTAssertEqual(healthyResponses, 1)
    }

    func testResponseWithoutAnExtensionTabIsStillAHealthyResponse() {
        commit("tab", url: pageURL)
        monitor.handle(.dashboardResponse(extensionTabIdentifier: nil, url: pageURL))

        XCTAssertEqual(healthyResponses, 1)
    }

    private func commit(_ tab: String, url: URL, kind: CPMNavigationKind = .other) {
        monitor.handle(.navigationCommitted(tabIdentifier: tab, url: url, navigationKind: kind, extensionIsLoaded: true))
    }
}
