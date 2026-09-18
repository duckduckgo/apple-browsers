//
//  CPMMessagingDiagnosticsTests.swift
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

import WebKit
import XCTest
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMMessagingDiagnosticsTests: XCTestCase {

    typealias Name = CPMMessagingDiagnostics.ParameterName

    func testEmptyDiagnosticsOnlyCarryDefaults() {
        let parameters = CPMMessagingDiagnostics().pixelParameters

        XCTAssertEqual(parameters, [
            Name.memoryPressureCritical: "none",
            Name.extensionContextErrors: "none"
        ])
    }

    func testWhenParameterNamesAreSerializedThenUsesCompactKeys() {
        XCTAssertEqual([
            Name.extensionContextLoaded, Name.memoryPressureCritical, Name.networkProcessRestarted,
            Name.extensionContextErrors, Name.backgroundViewCreateCount, Name.backgroundViewAlive,
            Name.backgroundViewLeakedCount, Name.backgroundWebProcessAlive, Name.tabKnownToWebKit,
            Name.nativeMessageHandlerRegistered, Name.tabControllerMatchesContext, Name.tabHasExtensionUserScripts,
            Name.backgroundWebProcessResponsive, Name.backgroundEvents
        ], [
            "context_loaded", "critical_memory_age", "network_restarted",
            "context_errors", "bg_view_creations", "bg_view_alive",
            "bg_view_leaked_count", "bg_process_alive", "tab_in_context",
            "handler_registered", "tab_controller_match", "tab_has_ext_scripts",
            "bg_process_responsive", "bg_events"
        ])
    }

    func testBackgroundEventsDropOldestEntriesToFitTheCap() {
        let events = (0..<40).map { CPMMessagingDiagnostics.BackgroundEvent(token: "error_background_failed_to_load", secondsBeforeSnapshot: TimeInterval($0)) }
        let value = CPMMessagingDiagnostics.backgroundEventsValue(events)

        XCTAssertLessThanOrEqual(value.count, CPMMessagingDiagnostics.maximumBackgroundEventsLength)
        XCTAssertTrue(value.hasSuffix("error_background_failed_to_load@-39"), "newest event must survive")
        XCTAssertFalse(value.hasPrefix("error_background_failed_to_load@-0,"), "oldest events are dropped first")
    }

    func testBackgroundEventTokensAreSanitized() {
        let value = CPMMessagingDiagnostics.backgroundEventsValue([
            .init(token: "Died Crash; https://example.com/?q=1", secondsBeforeSnapshot: -3)
        ])
        XCTAssertEqual(value, "diedcrashhttps:examplecomq1@-0")
    }

    func testMemoryPressureIsBucketed() {
        XCTAssertEqual(CPMMessagingDiagnostics.memoryPressureBucket(nil), "none")
        XCTAssertEqual(CPMMessagingDiagnostics.memoryPressureBucket(0), "1m")
        XCTAssertEqual(CPMMessagingDiagnostics.memoryPressureBucket(59.9), "1m")
        XCTAssertEqual(CPMMessagingDiagnostics.memoryPressureBucket(60), "5m")
        XCTAssertEqual(CPMMessagingDiagnostics.memoryPressureBucket(299), "5m")
        XCTAssertEqual(CPMMessagingDiagnostics.memoryPressureBucket(300), "30m")
        XCTAssertEqual(CPMMessagingDiagnostics.memoryPressureBucket(1800), "over_30")
    }

    func testCountsAreBucketed() {
        XCTAssertEqual(CPMMessagingDiagnostics.countBucket(0), "0")
        XCTAssertEqual(CPMMessagingDiagnostics.countBucket(1), "1")
        XCTAssertEqual(CPMMessagingDiagnostics.countBucket(2), "2")
        XCTAssertEqual(CPMMessagingDiagnostics.countBucket(3), "3_to_5")
        XCTAssertEqual(CPMMessagingDiagnostics.countBucket(5), "3_to_5")
        XCTAssertEqual(CPMMessagingDiagnostics.countBucket(6), "over_5")
    }

    func testFullDiagnosticsRenderEveryParameter() {
        var diagnostics = CPMMessagingDiagnostics()
        diagnostics.extensionContextLoaded = true
        diagnostics.secondsSinceCriticalMemoryPressure = 30
        diagnostics.networkProcessRestarted = true
        diagnostics.extensionContextErrors = ["background_failed_to_load:NSURLErrorDomain:-1100"]
        diagnostics.backgroundWebViewCreateCount = 4
        diagnostics.backgroundWebViewAlive = true
        diagnostics.leakedBackgroundWebViewCount = 1
        diagnostics.backgroundWebProcessAlive = false
        diagnostics.tabKnownToWebKit = false
        diagnostics.nativeMessageHandlerRegistered = false
        diagnostics.tabControllerMatchesContext = false
        diagnostics.tabHasExtensionUserScripts = false
        diagnostics.backgroundWebProcessResponsive = false
        diagnostics.backgroundEvents = [
            .init(token: "load", secondsBeforeSnapshot: 600.4),
            .init(token: "view", secondsBeforeSnapshot: 599),
            .init(token: "died_crash", secondsBeforeSnapshot: 42),
            .init(token: "error_background_failed_to_load:NSURLErrorDomain:-1100", secondsBeforeSnapshot: 41.6),
        ]

        XCTAssertEqual(diagnostics.pixelParameters, [
            Name.backgroundWebProcessResponsive: "false",
            Name.backgroundEvents: "load@-600,view@-599,died_crash@-42,error_background_failed_to_load:nsurlerrordomain:-1100@-42",
            Name.extensionContextLoaded: "true",
            Name.memoryPressureCritical: "1m",
            Name.networkProcessRestarted: "true",
            Name.extensionContextErrors: "background_failed_to_load:NSURLErrorDomain:-1100",
            Name.backgroundViewCreateCount: "3_to_5",
            Name.backgroundViewAlive: "true",
            Name.backgroundViewLeakedCount: "1",
            Name.backgroundWebProcessAlive: "false",
            Name.tabKnownToWebKit: "false",
            Name.nativeMessageHandlerRegistered: "false",
            Name.tabControllerMatchesContext: "false",
            Name.tabHasExtensionUserScripts: "false"
        ])
    }

}

@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMMessagingDiagnosticsRecorderTests: XCTestCase {

    private var createdTestExtensionDirs: [URL] = []

    func testWhenContextErrorIsRecordedThenDescriptorCarriesCodesNotText() async throws {
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false)
        let context = try await makeContext()
        recorder.contextWillLoad(context)
        let underlying = NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist, userInfo: [NSLocalizedDescriptionKey: "/Users/someone/file.js"])
        let error = NSError(domain: WKWebExtensionContext.errorDomain,
                            code: WKWebExtensionContext.Error.Code.backgroundContentFailedToLoad.rawValue,
                            userInfo: [NSUnderlyingErrorKey: underlying, NSLocalizedDescriptionKey: "The background content failed to load."])

        recorder.contextUnloadFailed(identifier: context.uniqueIdentifier, error: error)
        let descriptor = try XCTUnwrap(recorder.snapshot().backgroundEvents.last?.token)

        XCTAssertEqual(descriptor, "context_unload_failed_\(error.domain):\(error.code):\(NSURLErrorDomain):\(NSURLErrorFileDoesNotExist)")
        XCTAssertFalse(descriptor.contains("/Users"))
        recorder.contextUnloadFailed(identifier: context.uniqueIdentifier, error: NSError(domain: "Custom", code: 7))
        XCTAssertEqual(recorder.snapshot().backgroundEvents.last?.token, "context_unload_failed_Custom:7")
        recorder.contextUnloadFailed(identifier: context.uniqueIdentifier,
                                     error: NSError(domain: WKWebExtensionContext.errorDomain, code: 999))
        XCTAssertEqual(recorder.snapshot().backgroundEvents.last?.token, "context_unload_failed_\(WKWebExtensionContext.errorDomain):999")
    }

    override func tearDown() {
        for dir in createdTestExtensionDirs {
            try? FileManager.default.removeItem(at: dir)
        }
        createdTestExtensionDirs.removeAll()
        super.tearDown()
    }

    func testBackgroundWebViewCreationAndDeallocationAreRecorded() async throws {
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false)
        let context = try await makeContext()

        recorder.contextWillLoad(context)
        var snapshot = recorder.snapshot()
        XCTAssertEqual(snapshot.backgroundWebViewCreateCount, 0)
        XCTAssertEqual(snapshot.backgroundWebViewAlive, false)
        XCTAssertEqual(snapshot.leakedBackgroundWebViewCount, 0)

        var webView = WKWebView(frame: .zero)
        recorder.didCreateBackgroundWebView(webView, for: context)
        snapshot = recorder.snapshot()
        XCTAssertEqual(snapshot.backgroundWebViewCreateCount, 1)
        XCTAssertEqual(snapshot.backgroundWebViewAlive, true)
        XCTAssertEqual(snapshot.leakedBackgroundWebViewCount, 0)

        // WebKit replaces the background view: the old one is retained here to simulate a leak.
        let retainedOldView = webView
        webView = WKWebView(frame: .zero)
        recorder.didCreateBackgroundWebView(webView, for: context)
        withExtendedLifetime((retainedOldView, webView)) {
            snapshot = recorder.snapshot()
            XCTAssertEqual(snapshot.backgroundWebViewCreateCount, 2)
            XCTAssertEqual(snapshot.leakedBackgroundWebViewCount, 1)

            // Once the context is gone, the current view counts as leaked too until it deallocates.
            recorder.contextDidUnload(identifier: context.uniqueIdentifier)
            XCTAssertEqual(recorder.snapshot().leakedBackgroundWebViewCount, 2)
            XCTAssertEqual(recorder.snapshot().extensionContextLoaded, false)
        }
    }

    func testCollectDiagnosticsWithoutTabLeavesTabFactsUnknown() async {
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false)

        let diagnostics = recorder.collectDiagnostics(tabIdentifier: "missing")

        XCTAssertNil(diagnostics.tabKnownToWebKit)
    }

    func testMemoryPressureIsReportedRelativeToNow() {
        var currentDate = Date(timeIntervalSince1970: 1_000)
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false, now: { currentDate })

        XCTAssertNil(recorder.snapshot().secondsSinceCriticalMemoryPressure)

        recorder.recordCriticalMemoryPressureForTesting()
        currentDate = currentDate.addingTimeInterval(90)

        XCTAssertEqual(recorder.snapshot().secondsSinceCriticalMemoryPressure, 90)
    }

    func testUnloadFailurePreservesCPMContextAndBackgroundView() async throws {
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false)
        let context = try await makeContext()
        let webView = WKWebView(frame: .zero)
        recorder.contextWillLoad(context)
        recorder.didCreateBackgroundWebView(webView, for: context)
        recorder.nativeMessageHandlerCheck = { $0 === context }

        recorder.contextUnloadFailed(identifier: context.uniqueIdentifier, error: NSError(domain: "UnloadError", code: 7))

        let snapshot = recorder.snapshot()
        XCTAssertEqual(snapshot.backgroundWebViewAlive, true)
        XCTAssertEqual(snapshot.nativeMessageHandlerRegistered, true)
        XCTAssertEqual(snapshot.backgroundEvents.last?.token, "context_unload_failed_UnloadError:7")
    }

    func testFileRemovalFailureIsRecordedAfterSuccessfulUnloadWithoutErrorText() async throws {
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false)
        let context = try await makeContext()
        recorder.contextWillLoad(context)
        recorder.contextDidUnload(identifier: context.uniqueIdentifier)
        let error = NSError(domain: "FilesError", code: 13,
                            userInfo: [NSLocalizedDescriptionKey: "https://private.example", NSFilePathErrorKey: "/Users/private"])

        recorder.extensionFilesRemoveFailed(identifier: context.uniqueIdentifier, error: error)

        let snapshot = recorder.snapshot()
        XCTAssertEqual(snapshot.backgroundEvents.last?.token, "extension_files_remove_failed_FilesError:13")
        XCTAssertEqual(snapshot.extensionContextLoaded, false)
        let payload = snapshot.pixelParameters.values.joined()
        XCTAssertFalse(payload.contains("private"))
    }

    func testLifecycleFailuresIgnoreOtherExtensionsAndPreviousContext() async throws {
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false)
        let context = try await makeContext()
        recorder.contextWillLoad(context)
        let error = NSError(domain: "TestError", code: 1)
        recorder.contextUnloadFailed(identifier: "another-extension", error: error)
        recorder.extensionFilesRemoveFailed(identifier: "another-extension", error: error)
        XCTAssertEqual(recorder.snapshot().backgroundEvents.map(\.token), ["load"])

        let replacement = try await makeContext()
        replacement.uniqueIdentifier = "replacement"
        recorder.contextWillLoad(replacement)
        recorder.contextUnloadFailed(identifier: context.uniqueIdentifier, error: error)
        recorder.extensionFilesRemoveFailed(identifier: context.uniqueIdentifier, error: error)
        XCTAssertEqual(recorder.snapshot().backgroundEvents.map(\.token), ["load"])
    }

    func testWhenOldViewCallsBackAfterContextReplacementThenNewTimelineIsUnchanged() async throws {
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false)
        let oldContext = try await makeContext()
        let replacement = try await makeContext()
        let oldView = WKWebView(frame: .zero)
        recorder.contextWillLoad(oldContext)
        recorder.didCreateBackgroundWebView(oldView, for: oldContext)

        recorder.contextWillLoad(replacement)
        recorder.backgroundWebView(oldView, webContentProcessDidTerminateWith: .crash)
        recorder.backgroundWebViewWebProcessDidBecomeUnresponsive(oldView)
        recorder.backgroundWebViewWebProcessDidBecomeResponsive(oldView)
        recorder.didCreateBackgroundWebView(oldView, for: oldContext)

        XCTAssertEqual(recorder.snapshot().backgroundEvents.map(\.token), ["load"])
        XCTAssertEqual(recorder.snapshot().backgroundWebViewAlive, false)
        XCTAssertEqual(recorder.snapshot().backgroundWebViewCreateCount, 0)
    }

    func testWhenOldViewDeallocatesAfterContextReplacementThenNewTimelineIsUnchanged() async throws {
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false)
        let oldContext = try await makeContext()
        let replacement = try await makeContext()
        weak var releasedView: WKWebView?
        autoreleasepool {
            let view = WKWebView(frame: .zero)
            releasedView = view
            recorder.contextWillLoad(oldContext)
            recorder.didCreateBackgroundWebView(view, for: oldContext)
            recorder.contextWillLoad(replacement)
        }
        await Task.yield()

        XCTAssertNil(releasedView)
        XCTAssertEqual(recorder.snapshot().backgroundEvents.map(\.token), ["load"])
        XCTAssertEqual(recorder.snapshot().leakedBackgroundWebViewCount, 0)
    }

    private func makeContext() async throws -> WKWebExtensionContext {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("CPMDiagnosticsTestExtension-\(UUID().uuidString)")
        let manifest = """
        {
            "manifest_version": 3,
            "name": "CPM Diagnostics Test Extension",
            "version": "1.0.0",
            "background": { "service_worker": "background.js" }
        }
        """
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try manifest.write(to: dir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try "// test".write(to: dir.appendingPathComponent("background.js"), atomically: true, encoding: .utf8)
        createdTestExtensionDirs.append(dir)

        let webExtension = try await WKWebExtension(resourceBaseURL: dir)
        let context = WKWebExtensionContext(for: webExtension)
        context.uniqueIdentifier = "cpm-diagnostics-test"
        return context
    }
}
