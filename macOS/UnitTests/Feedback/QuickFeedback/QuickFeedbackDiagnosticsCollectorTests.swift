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

    // MARK: - Header

    func testWhenCollectingDiagnosticsThenOutputStartsWithSentinelHeader() {
        let collector = QuickFeedbackDiagnosticsCollector()
        let result = collector.collectDiagnostics()

        XCTAssertTrue(result.hasPrefix("--- Diagnostics (auto-collected) ---"))
    }

    // MARK: - Required Fields

    func testWhenCollectingDiagnosticsThenOutputContainsAppVersion() {
        let collector = QuickFeedbackDiagnosticsCollector()
        let result = collector.collectDiagnostics()

        XCTAssertTrue(result.contains("App Version:"), "Diagnostics should include the app version line")
    }

    func testWhenCollectingDiagnosticsThenOutputContainsMacOSVersion() {
        let collector = QuickFeedbackDiagnosticsCollector()
        let result = collector.collectDiagnostics()

        let osVersion = ProcessInfo.processInfo.operatingSystemVersion
        let expectedVersion = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
        XCTAssertTrue(result.contains("macOS: \(expectedVersion)"))
    }

    func testWhenCollectingDiagnosticsThenOutputContainsArchitecture() {
        let collector = QuickFeedbackDiagnosticsCollector()
        let result = collector.collectDiagnostics()

        XCTAssertTrue(result.contains("Architecture:"), "Diagnostics should include the architecture line")
        #if arch(arm64)
        XCTAssertTrue(result.contains("Apple Silicon (arm64)"))
        #elseif arch(x86_64)
        XCTAssertTrue(result.contains("Intel (x86_64)"))
        #endif
    }

    func testWhenCollectingDiagnosticsThenOutputContainsMemory() {
        let collector = QuickFeedbackDiagnosticsCollector()
        let result = collector.collectDiagnostics()

        XCTAssertTrue(result.contains("Memory:"), "Diagnostics should include the memory line")
        XCTAssertTrue(result.contains("GB total"), "Memory should include total GB")
    }

    func testWhenCollectingDiagnosticsThenOutputContainsGPU() {
        let collector = QuickFeedbackDiagnosticsCollector()
        let result = collector.collectDiagnostics()

        XCTAssertTrue(result.contains("GPU:"), "Diagnostics should include the GPU line")
    }

    func testWhenCollectingDiagnosticsThenOutputContainsDisk() {
        let collector = QuickFeedbackDiagnosticsCollector()
        let result = collector.collectDiagnostics()

        XCTAssertTrue(result.contains("Disk:"), "Diagnostics should include the disk line")
    }

    func testWhenCollectingDiagnosticsThenOutputContainsSession() {
        let collector = QuickFeedbackDiagnosticsCollector()
        let result = collector.collectDiagnostics()

        XCTAssertTrue(result.contains("Session:"), "Diagnostics should include the session line")
    }

    // MARK: - Tab Count

    func testWhenTabCountProviderIsNilThenOutputDoesNotContainTabsLine() {
        let collector = QuickFeedbackDiagnosticsCollector(tabCountProvider: nil)
        let result = collector.collectDiagnostics()

        XCTAssertFalse(result.contains("Tabs:"))
    }

    func testWhenTabCountProviderExistsThenOutputContainsTabsAndWindows() {
        let mockProvider = MockTabCountProvider(tabCount: 42, windowCount: 3)
        let collector = QuickFeedbackDiagnosticsCollector(tabCountProvider: mockProvider)
        let result = collector.collectDiagnostics()

        XCTAssertTrue(result.contains("Tabs: 42 tabs / 3 windows"))
    }

    func testWhenTabCountIsZeroThenOutputContainsZeroCounts() {
        let mockProvider = MockTabCountProvider(tabCount: 0, windowCount: 0)
        let collector = QuickFeedbackDiagnosticsCollector(tabCountProvider: mockProvider)
        let result = collector.collectDiagnostics()

        XCTAssertTrue(result.contains("Tabs: 0 tabs / 0 windows"))
    }

    func testWhenCollectingDiagnosticsThenMemoryIncludesBrowserUsage() {
        let collector = QuickFeedbackDiagnosticsCollector()
        let result = collector.collectDiagnostics()

        XCTAssertTrue(result.contains("MB browser"), "Memory line should include browser memory usage from mach_task_basic_info")
    }

    func testWhenTabCountProviderIsDeallocatedThenOutputDoesNotContainTabsLine() {
        var mockProvider: MockTabCountProvider? = MockTabCountProvider(tabCount: 5, windowCount: 2)
        let collector = QuickFeedbackDiagnosticsCollector(tabCountProvider: mockProvider!)
        mockProvider = nil

        let result = collector.collectDiagnostics()

        XCTAssertFalse(result.contains("Tabs:"), "Should omit tabs when provider is deallocated")
    }

    // MARK: - Field Ordering

    func testWhenCollectingDiagnosticsWithProviderThenFieldsAreInExpectedOrder() {
        let mockProvider = MockTabCountProvider(tabCount: 3, windowCount: 1)
        let collector = QuickFeedbackDiagnosticsCollector(tabCountProvider: mockProvider)
        let lines = collector.collectDiagnostics().components(separatedBy: "\n")

        guard lines.count >= 9 else {
            XCTFail("Expected at least 9 lines but got \(lines.count)")
            return
        }

        XCTAssertTrue(lines[0].hasPrefix("--- Diagnostics"))
        XCTAssertTrue(lines[1].hasPrefix("App Version:"))
        XCTAssertTrue(lines[2].hasPrefix("macOS:"))
        XCTAssertTrue(lines[3].hasPrefix("Architecture:"))
        XCTAssertTrue(lines[4].hasPrefix("GPU:"))
        XCTAssertTrue(lines[5].hasPrefix("Memory:"))
        XCTAssertTrue(lines[6].hasPrefix("Disk:"))
        XCTAssertTrue(lines[7].hasPrefix("Tabs:"))
        XCTAssertTrue(lines[8].hasPrefix("Session:"))
    }

    // MARK: - Line Structure

    func testWhenCollectingDiagnosticsThenOutputIsNewlineSeparated() {
        let collector = QuickFeedbackDiagnosticsCollector()
        let lines = collector.collectDiagnostics().components(separatedBy: "\n")

        XCTAssertGreaterThanOrEqual(lines.count, 8, "Should have at least sentinel + version + OS + arch + GPU + memory + disk + session")
    }
}

// MARK: - Mocks

private final class MockTabCountProvider: TabCountProviding {
    let tabCount: Int
    let windowCount: Int

    init(tabCount: Int, windowCount: Int = 1) {
        self.tabCount = tabCount
        self.windowCount = windowCount
    }
}
