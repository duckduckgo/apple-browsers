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

    private let monitor = CPMMessagingHealthMonitor()
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

    func testExtensionTabIsLearnedFromTheOnePageThatMatches() {
        commit("tab", url: pageURL)
        commit("other", url: URL(string: "https://other.example/")!)
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 5, url: pageURL))

        XCTAssertEqual(monitor.tabIdentifier(forExtensionTab: 5), "tab")
    }

    func testLearnedMappingIsKeptWhenThePageLaterMatchesTwoTabs() {
        let second = URL(string: "https://example.com/second")!
        commit("tab", url: pageURL)
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 5, url: pageURL))
        commit("tab", url: second)
        commit("other", url: second)
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 5, url: second))

        XCTAssertEqual(monitor.tabIdentifier(forExtensionTab: 5), "tab")
        XCTAssertEqual(healthyResponses, 2)
    }

    func testResponseThatMatchesTwoTabsLearnsNothing() {
        commit("one", url: pageURL)
        commit("two", url: pageURL)
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 5, url: pageURL))

        XCTAssertNil(monitor.tabIdentifier(forExtensionTab: 5))
    }

    func testResponseWithoutAnExtensionTabLearnsNothing() {
        commit("tab", url: pageURL)
        monitor.handle(.dashboardResponse(extensionTabIdentifier: nil, url: pageURL))

        XCTAssertEqual(healthyResponses, 1)
        XCTAssertNil(monitor.tabIdentifier(forExtensionTab: 0))
    }

    func testOnlyAnOrdinaryHttpPageIsKept() {
        let ineligible: [(URL, CPMNavigationKind)] = [
            (pageURL, .errorPage),
            (pageURL, .backForward),
            (pageURL, .sessionRestoration),
            (URL(string: "duck://newtab")!, .other),
        ]
        for (index, (url, kind)) in ineligible.enumerated() {
            commit("tab", url: pageURL)
            commit("tab", url: url, kind: kind)
            monitor.handle(.dashboardResponse(extensionTabIdentifier: index, url: pageURL))

            XCTAssertNil(monitor.tabIdentifier(forExtensionTab: index), "\(url.scheme ?? "") \(kind) erases the tab's page")
        }
        commit("tab", url: pageURL, kind: .other)
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 9, url: pageURL))
        XCTAssertEqual(monitor.tabIdentifier(forExtensionTab: 9), "tab")
    }

    func testClosedTabAndTerminatedProcessEraseThePageOfTheTab() {
        commit("closed", url: pageURL)
        monitor.handle(.tabClosed(tabIdentifier: "closed"))
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 1, url: pageURL))
        XCTAssertNil(monitor.tabIdentifier(forExtensionTab: 1))

        commit("crashed", url: pageURL)
        monitor.handle(.webContentProcessTerminated(tabIdentifier: "crashed"))
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 2, url: pageURL))
        XCTAssertNil(monitor.tabIdentifier(forExtensionTab: 2))
    }

    func testClosingATabForgetsItsExtensionTab() {
        commit("tab", url: pageURL)
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 5, url: pageURL))
        monitor.handle(.tabClosed(tabIdentifier: "tab"))

        XCTAssertNil(monitor.tabIdentifier(forExtensionTab: 5))
    }

    func testExtensionReloadForgetsMappingsAndKeepsPagesSoTabsAreLearnedAgain() {
        commit("tab", url: pageURL)
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 5, url: pageURL))
        monitor.handle(.extensionLifecycle(.reloaded(identifier: "embedded", type: .embedded, trigger: .explicit)))
        XCTAssertNil(monitor.tabIdentifier(forExtensionTab: 5))

        monitor.handle(.dashboardResponse(extensionTabIdentifier: 6, url: pageURL))
        XCTAssertEqual(monitor.tabIdentifier(forExtensionTab: 6), "tab", "the open page is matched by the new extension tab")
    }

    func testWillReloadForgetsMappingsBeforeTheReloadCompletes() {
        commit("tab", url: pageURL)
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 5, url: pageURL))
        monitor.handle(.extensionLifecycle(.willReload(identifier: "embedded", type: .embedded, trigger: .explicit)))

        XCTAssertNil(monitor.tabIdentifier(forExtensionTab: 5))
    }

    func testLifecycleOfAnotherExtensionTypeIsIgnored() {
        commit("tab", url: pageURL)
        monitor.handle(.dashboardResponse(extensionTabIdentifier: 5, url: pageURL))
        monitor.handle(.extensionLifecycle(.reloaded(identifier: "other", type: .darkReader, trigger: .explicit)))

        XCTAssertEqual(monitor.tabIdentifier(forExtensionTab: 5), "tab")
    }

    private func commit(_ tab: String, url: URL, kind: CPMNavigationKind = .other) {
        monitor.handle(.navigationCommitted(tabIdentifier: tab, url: url, navigationKind: kind, extensionIsLoaded: true))
    }
}
