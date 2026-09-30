//
//  QuickFeedbackDiagnosticsCollectorTests.swift
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
@testable import DuckDuckGo_Privacy_Browser

final class QuickFeedbackDiagnosticsCollectorTests: XCTestCase {

    private func makeCollector(
        tabAndWindowCountProvider: TabAndWindowCountProviding? = nil,
        memoryUsageMonitor: MemoryUsageMonitoring = StubMemoryUsageMonitor(),
        launchDate: Date = Date()
    ) -> QuickFeedbackDiagnosticsCollector {
        QuickFeedbackDiagnosticsCollector(
            tabAndWindowCountProvider: tabAndWindowCountProvider,
            memoryUsageMonitor: memoryUsageMonitor,
            launchDate: launchDate
        )
    }

    // MARK: - Collected Fields

    func testWhenCollectingDiagnosticsThenHardwareAndSessionFieldsArePresent() {
        let fields = makeCollector().collectDiagnostics()

        XCTAssertNotNil(fields["GPU"], "Diagnostics should include the GPU")
        XCTAssertNotNil(fields["Disk"], "Diagnostics should include free disk space")
        XCTAssertNotNil(fields["Session"], "Diagnostics should include the session length")
    }

    func testWhenCollectingDiagnosticsThenMemoryReportsBrowserWebContentAndTotal() {
        let monitor = StubMemoryUsageMonitor(
            webContentBytes: 250 * 1_048_576,
            webContentProcessCount: 3
        )
        let memory = makeCollector(memoryUsageMonitor: monitor).collectDiagnostics()["Memory"]

        XCTAssertNotNil(memory)
        XCTAssertTrue(memory?.contains("400 MB browser") == true, "Memory should report the browser's own usage")
        XCTAssertTrue(memory?.contains("250 MB web content (3 processes)") == true, "Memory should report Web Content usage")
        XCTAssertTrue(memory?.contains("GB total") == true, "Memory should report the total available")
    }

    func testWhenCollectingDiagnosticsThenValuesReportedAsDeviceInfoFieldsAreOmitted() {
        let fields = makeCollector().collectDiagnostics()

        XCTAssertNil(fields["App Version"])
        XCTAssertNil(fields["macOS"])
        XCTAssertNil(fields["Architecture"])
    }

    // MARK: - Tab And Window Counts

    func testWhenTabCountProviderIsNilThenCountsAreOmitted() {
        let fields = makeCollector(tabAndWindowCountProvider: nil).collectDiagnostics()

        XCTAssertNil(fields["Tabs"])
        XCTAssertNil(fields["Windows"])
    }

    func testWhenTabCountProviderExistsThenCountsAreReportedSeparately() {
        let provider = MockTabAndWindowCountProvider(tabCount: 42, windowCount: 3)
        let fields = makeCollector(tabAndWindowCountProvider: provider).collectDiagnostics()

        XCTAssertEqual(fields["Tabs"], "42")
        XCTAssertEqual(fields["Windows"], "3")
    }

    func testWhenTabCountIsZeroThenCountsAreStillReported() {
        let provider = MockTabAndWindowCountProvider(tabCount: 0, windowCount: 0)
        let fields = makeCollector(tabAndWindowCountProvider: provider).collectDiagnostics()

        XCTAssertEqual(fields["Tabs"], "0")
        XCTAssertEqual(fields["Windows"], "0")
    }

    func testWhenTabCountProviderIsDeallocatedThenCountsAreOmitted() {
        var provider: MockTabAndWindowCountProvider? = MockTabAndWindowCountProvider(tabCount: 5, windowCount: 2)
        let collector = makeCollector(tabAndWindowCountProvider: provider!)
        provider = nil

        let fields = collector.collectDiagnostics()

        XCTAssertNil(fields["Tabs"], "Counts should be omitted once the provider has gone")
        XCTAssertNil(fields["Windows"])
    }

    // MARK: - Values

    func testWhenCollectingDiagnosticsThenNoValueIsEmpty() {
        let provider = MockTabAndWindowCountProvider(tabCount: 3, windowCount: 1)
        let fields = makeCollector(tabAndWindowCountProvider: provider).collectDiagnostics()

        XCTAssertFalse(fields.isEmpty)
        for (key, value) in fields {
            XCTAssertFalse(value.isEmpty, "\(key) should never be reported as an empty string")
        }
    }
}

// MARK: - Mocks

private final class MockTabAndWindowCountProvider: TabAndWindowCountProviding {
    let tabCount: Int
    let windowCount: Int

    init(tabCount: Int, windowCount: Int = 1) {
        self.tabCount = tabCount
        self.windowCount = windowCount
    }
}

private struct StubMemoryUsageMonitor: MemoryUsageMonitoring {
    let webContentBytes: UInt64?
    let webContentProcessCount: Int?

    init(webContentBytes: UInt64? = nil, webContentProcessCount: Int? = nil) {
        self.webContentBytes = webContentBytes
        self.webContentProcessCount = webContentProcessCount
    }

    func getCurrentMemoryUsage() -> MemoryUsageMonitor.MemoryReport {
        MemoryUsageMonitor.MemoryReport(
            residentBytes: 500 * 1_048_576,
            physFootprintBytes: 400 * 1_048_576,
            webContentBytes: webContentBytes,
            webContentProcessCount: webContentProcessCount
        )
    }
}
