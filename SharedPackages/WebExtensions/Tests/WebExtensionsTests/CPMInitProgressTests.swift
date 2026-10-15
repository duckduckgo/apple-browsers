//
//  CPMInitProgressTests.swift
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

import PrivacyConfig
import PrivacyConfigTestsUtils
import XCTest
@testable import WebExtensions

private typealias Name = CPMMessagingDiagnostics.ParameterName

/// The extension's `cpmInitProgress` marks reach the health monitor and end up on failure pixels as `init_stage`.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMInitProgressMonitorTests: XCTestCase {

    private let page = URL(string: "https://example.com/page")!

    func testAMarkForTheFailingNavigationIsReportedAtItsFurthestStage() async throws {
        for (stages, expected) in [([CPMInitProgressStage.received], "received"),
                                   ([.received, .responseSent], "response_sent"),
                                   ([.received, .responseFailed], "response_failed")] {
            let harness = makeHarness()
            harness.startAndCommit(page)
            for stage in stages {
                harness.monitor.handle(.initProgress(extensionTabIdentifier: 7, url: page, stage: stage))
            }

            try await harness.failNavigation(page)

            XCTAssertEqual(harness.failureParameters[Name.initStage], expected, "marks \(stages.map(\.rawValue))")
        }
    }

    func testAnExtensionThatReportsProgressButNothingForThisNavigationMeansInitDidNotArrive() async throws {
        let harness = makeHarness()
        harness.startAndCommit(URL(string: "https://example.com/earlier")!)
        harness.monitor.handle(.initProgress(extensionTabIdentifier: 7, url: URL(string: "https://example.com/earlier")!, stage: .received))
        harness.startAndCommit(page)

        try await harness.failNavigation(page)

        XCTAssertEqual(harness.failureParameters[Name.initStage], "none", "the earlier document's mark is not this navigation's")
    }

    func testAMarkSentBeforeTheNavigationStartedBelongsToAnEarlierDocument() async throws {
        let harness = makeHarness()
        harness.monitor.handle(.initProgress(extensionTabIdentifier: 7, url: page, stage: .received))
        harness.advanceClock(by: 1)
        harness.startAndCommit(page)
        harness.monitor.handle(.initProgress(extensionTabIdentifier: 7, url: URL(string: "https://example.com/other")!, stage: .received))

        try await harness.failNavigation(page)

        XCTAssertEqual(harness.failureParameters[Name.initStage], "none")
    }

    func testAnExtensionThatNeverReportsProgressLeavesTheStageOut() async throws {
        let harness = makeHarness()
        harness.startAndCommit(page)

        try await harness.failNavigation(page)

        XCTAssertNil(harness.failureParameters[Name.initStage], "an older extension cannot tell us; omit instead of claiming none")
    }

    func testMarksFromTwoExtensionTabsOnTheSameDocumentAreNotGuessedAt() async throws {
        let harness = makeHarness()
        harness.startAndCommit(page)
        harness.monitor.handle(.initProgress(extensionTabIdentifier: 7, url: page, stage: .received))
        harness.monitor.handle(.initProgress(extensionTabIdentifier: 8, url: page, stage: .responseSent))

        try await harness.failNavigation(page)

        XCTAssertNil(harness.failureParameters[Name.initStage])
    }

    func testMarksDoNotChangeWhetherOrWhenTheFailureIsReported() async throws {
        let withMarks = makeHarness()
        withMarks.startAndCommit(page)
        withMarks.monitor.handle(.initProgress(extensionTabIdentifier: 7, url: page, stage: .responseSent))
        let without = makeHarness()
        without.startAndCommit(page)

        try await withMarks.failNavigation(page)
        try await without.failNavigation(page)

        XCTAssertEqual(withMarks.pixels.failureCount, 1, "a mark is evidence for the report, not a response")
        XCTAssertEqual(without.pixels.failureCount, 1)
        XCTAssertEqual(withMarks.pixels.metadata.map(\.name), without.pixels.metadata.map(\.name))
    }

    // MARK: - Helpers

    @MainActor
    private final class Harness {
        /// A reference, so the monitor's clock and the test read the same time.
        private final class Clock {
            var date = Date(timeIntervalSince1970: 1_000)
        }

        let monitor: CPMMessagingHealthMonitor
        let pixels = CapturingFailurePixels()
        private let clock = Clock()

        init() {
            let clock = self.clock
            monitor = CPMMessagingHealthMonitor(pixelFiring: pixels,
                                                episodeLifetime: 600,
                                                extensionLoadWait: 0.01,
                                                responseGracePeriod: 0.02,
                                                now: { clock.date })
            monitor.diagnosticsProvider = provider
        }

        private let provider = FixedDiagnosticsProvider()

        func advanceClock(by seconds: TimeInterval) {
            clock.date += seconds
        }

        func startAndCommit(_ url: URL) {
            monitor.handle(.navigationStarted(tabIdentifier: "tab-1", navigationKind: .other))
            monitor.handle(.navigationCommitted(tabIdentifier: "tab-1", url: url))
        }

        func failNavigation(_ url: URL) async throws {
            monitor.handle(.navigationFinished(tabIdentifier: "tab-1", url: url, extensionIsLoaded: true))
            for _ in 0..<200 where pixels.failureCount == 0 {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            XCTAssertEqual(pixels.failureCount, 1, "the failure must be reported for the measurement to be meaningful")
        }

        var failureParameters: [String: String] {
            pixels.failureDiagnostics.last?.pixelParameters ?? [:]
        }
    }

    private func makeHarness() -> Harness {
        Harness()
    }
}

/// The handler passes marks on and rejects what it cannot read.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMInitProgressHandlerTests: XCTestCase {

    func testAValidMarkIsPassedToTheMonitor() async {
        let monitor = RecordingInitProgressMonitor()
        let handler = makeHandler(monitor: monitor)

        let result = await handler.handleMessage(message(["tabId": NSNumber(value: 42), "url": "https://example.com/a", "stage": "response_sent"]))

        guard case .success = result else { return XCTFail("expected success, got \(result)") }
        XCTAssertEqual(monitor.marks, [.init(extensionTabIdentifier: 42, url: URL(string: "https://example.com/a")!, stage: .responseSent)])
    }

    func testAMarkWithoutAReadableStageOrUrlIsRejectedAndNotPassedOn() async {
        let monitor = RecordingInitProgressMonitor()
        let handler = makeHandler(monitor: monitor)

        for params: [String: Any] in [["url": "https://example.com/a", "stage": "unknown"],
                                      ["url": "https://example.com/a"],
                                      ["stage": "received"],
                                      ["url": "not a url", "stage": "received"]] {
            let result = await handler.handleMessage(message(params))
            guard case .failure = result else { return XCTFail("expected failure for \(params)") }
        }
        XCTAssertTrue(monitor.marks.isEmpty)
    }

    func testAMarkIsAcceptedWithoutAMonitor() async {
        let handler = makeHandler(monitor: nil)

        let result = await handler.handleMessage(message(["url": "https://example.com/a", "stage": "received"]))

        guard case .success = result else { return XCTFail("expected success, got \(result)") }
    }

    func testStageValuesMatchWhatTheExtensionSends() {
        XCTAssertEqual(CPMInitProgressStage(rawValue: "received"), .received)
        XCTAssertEqual(CPMInitProgressStage(rawValue: "response_sent"), .responseSent)
        XCTAssertEqual(CPMInitProgressStage(rawValue: "response_failed"), .responseFailed)
    }

    func testInitStageIsSerializedAndOmittedWhenUnknown() {
        var diagnostics = CPMMessagingDiagnostics()
        XCTAssertNil(diagnostics.pixelParameters[Name.initStage])
        diagnostics.initStage = CPMMessagingDiagnostics.InitStage.none
        XCTAssertEqual(diagnostics.pixelParameters[Name.initStage], "none")
    }

    // MARK: - Helpers

    private func makeHandler(monitor: CPMMessagingHealthMonitoring?) -> AutoconsentWebExtensionMessageHandler {
        AutoconsentWebExtensionMessageHandler(privacyConfigurationManager: MockPrivacyConfigurationManager(privacyConfig: MockPrivacyConfiguration()),
                                              autoconsentPreferences: MockAutoconsentPreferences(),
                                              cpmMessagingHealthMonitor: monitor)
    }

    private func message(_ params: [String: Any]) -> WebExtensionMessage {
        WebExtensionMessage(featureName: "autoconsent", method: "cpmInitProgress", id: nil, params: params, context: "test-context", extensionIdentifier: "test-extension-id")
    }
}

// MARK: - Test doubles

@available(macOS 15.4, iOS 18.4, *)
@MainActor
private final class RecordingInitProgressMonitor: CPMMessagingHealthMonitoring {
    struct Mark: Equatable {
        let extensionTabIdentifier: Int?
        let url: URL
        let stage: CPMInitProgressStage
    }

    private(set) var marks: [Mark] = []

    func handle(_ event: CPMMessagingHealthEvent) {
        guard case .initProgress(let extensionTabIdentifier, let url, let stage) = event else { return }
        marks.append(Mark(extensionTabIdentifier: extensionTabIdentifier, url: url, stage: stage))
    }
}

@available(macOS 15.4, iOS 18.4, *)
@MainActor
private final class FixedDiagnosticsProvider: CPMMessagingDiagnosticsProviding {
    func collectDiagnostics(tabIdentifier: String) -> CPMMessagingDiagnostics {
        CPMMessagingDiagnostics(extensionContextLoaded: true)
    }
}

@available(macOS 15.4, iOS 18.4, *)
private final class CapturingFailurePixels: WebExtensionPixelFiring {
    private(set) var failureDiagnostics: [CPMMessagingDiagnostics] = []
    private(set) var metadata: [CPMWebExtensionPixelMetadata] = []
    var failureCount: Int { failureDiagnostics.count }

    func fire(_ event: WebExtensionPixelEvent) {
        if let metadata = CPMWebExtensionPixelMetadata(event: event) {
            self.metadata.append(metadata)
        }
        guard case .cpmInitializationFailed(_, let diagnostics) = event, let diagnostics else { return }
        failureDiagnostics.append(diagnostics)
    }
}
