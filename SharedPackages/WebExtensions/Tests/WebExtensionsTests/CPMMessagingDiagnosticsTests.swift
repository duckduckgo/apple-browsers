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

    func testWhenRecorderIsRecreatedThenAppLaunchAgeDoesNotReset() {
        var date = Date(timeIntervalSince1970: 1000)
        let session = CPMAppSessionDiagnostics(appVersionChange: nil, launchDate: date)
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false, now: { date }, appSession: session)
        XCTAssertEqual(recorder.snapshot().secondsSinceAppLaunch, 0)
        date += 60
        let replacement = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false, now: { date }, appSession: session)
        XCTAssertEqual(recorder.snapshot().secondsSinceAppLaunch, 60)
        XCTAssertEqual(replacement.snapshot().secondsSinceAppLaunch, 60)
        XCTAssertNil(replacement.snapshot().appVersionChange)
    }

    func testWhenAppWasUpdatedThenSnapshotKeepsSessionFacts() {
        let date = Date(timeIntervalSince1970: 1000)
        let session = CPMAppSessionDiagnostics(appVersionChange: .updated, launchDate: date)
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false, now: { date }, appSession: session)
        XCTAssertEqual(recorder.snapshot().appVersionChange, .updated)
        XCTAssertEqual(recorder.snapshot().secondsSinceAppLaunch, 0)
    }

    func testBackgroundEventsDropOldestEntriesToFitTheCap() {
        let events = (0..<40).map {
            CPMMessagingDiagnostics.BackgroundEvent(token: "error_background_failed_to_load_\($0)", secondsBeforeSnapshot: TimeInterval(39 - $0))
        }
        let value = CPMMessagingDiagnostics.backgroundEventsValue(events)

        XCTAssertLessThanOrEqual(value.count, CPMMessagingDiagnostics.maximumBackgroundEventsLength)
        XCTAssertTrue(value.hasSuffix("error_background_failed_to_load_39@30s"), "newest event must survive")
        XCTAssertFalse(value.contains("error_background_failed_to_load_0@"), "oldest events are dropped first")
    }

    func testBackgroundEventTokensAreSanitized() {
        let value = CPMMessagingDiagnostics.backgroundEventsValue([
            .init(token: "Died Crash; https://example.com/?q=1", secondsBeforeSnapshot: -3)
        ])
        XCTAssertEqual(value, "diedcrashhttps:examplecomq1@30s")
    }

    func testWhenBackgroundEventAgeCrossesBoundaryThenUsesNextBucket() {
        let cases: [(TimeInterval, String)] = [
            (-1, "30s"), (0, "30s"), (29.999, "30s"),
            (30, "1m"), (59.999, "1m"),
            (60, "2m"), (119.999, "2m"),
            (120, "5m"), (299.999, "5m"),
            (300, "15m"), (899.999, "15m"),
            (900, "over_15"), (86_400, "over_15")
        ]
        for (seconds, bucket) in cases {
            let value = CPMMessagingDiagnostics.backgroundEventsValue([.init(token: "view", secondsBeforeSnapshot: seconds)])
            XCTAssertEqual(value, "view@\(bucket)", "age: \(seconds)")
        }
    }

    func testWhenBackgroundEventsShareBucketThenPreservesOrderAndDuplicates() {
        let value = CPMMessagingDiagnostics.backgroundEventsValue([
            .init(token: "view", secondsBeforeSnapshot: 29),
            .init(token: "died_crash", secondsBeforeSnapshot: 20),
            .init(token: "view", secondsBeforeSnapshot: 10)
        ])
        XCTAssertEqual(value, "view@30s,died_crash@30s,view@30s")
    }

    func testBackgroundReadinessBucketsCoverTheGraceAndUnloadBoundaries() {
        let times: [TimeInterval] = [0, 0.999, 1, 3.999, 4, 9.999, 10, 29.999, 30]
        XCTAssertEqual(times.map { CPMMessagingDiagnostics.readinessValue(.loaded(secondsAfterViewCreation: $0)) },
                       ["under_1s", "under_1s", "1s_to_4s", "1s_to_4s", "4s_to_10s", "4s_to_10s", "10s_to_30s", "10s_to_30s", "over_30s"])
        XCTAssertEqual([CPMBackgroundReadiness.noBackground, .pending, .failed].map(CPMMessagingDiagnostics.readinessValue),
                       ["none", "pending", "failed"])
    }

    func testBackgroundAgeAndLoadErrorBucketsAtEveryBoundary() {
        XCTAssertEqual([0, 3.999, 4, 7.999, 8, 29.999, 30, 119.999, 120].map(CPMMessagingDiagnostics.backgroundViewAgeBucket),
                       ["under_4s", "under_4s", "4s_to_8s", "4s_to_8s", "8s_to_30s", "8s_to_30s", "30s_to_2m", "30s_to_2m", "over_2m"])
        XCTAssertEqual([0, 4.999, 5, 24.999, 25, 34.999, 35].map(CPMMessagingDiagnostics.loadErrorDelayBucket),
                       ["under_5s", "under_5s", "5s_to_25s", "5s_to_25s", "25s_to_35s", "25s_to_35s", "over_35s"])
    }

    func testLoadErrorFieldsRequireAnAttributedErrorAndOmitUnknownFacts() {
        var diagnostics = CPMMessagingDiagnostics()
        diagnostics.backgroundLoadErrorAppState = .background
        diagnostics.secondsFromBackgroundViewToLoadError = 30
        for errorPresent in [nil, false, true] as [Bool?] {
            diagnostics.hasBackgroundLoadError = errorPresent
            let expected = errorPresent == true ? [Name.backgroundLoadErrorAppState: "background", Name.backgroundLoadErrorAfter: "25s_to_35s"] : [:]
            XCTAssertEqual(diagnostics.backgroundLoadParameters, expected)
        }
        diagnostics.backgroundLoadErrorAppState = nil
        diagnostics.secondsFromBackgroundViewToLoadError = nil
        XCTAssertTrue(diagnostics.backgroundLoadParameters.isEmpty)
    }
}

@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMMessagingDiagnosticsRecorderTests: XCTestCase {

    private var createdTestExtensionDirs: [URL] = []

    func testWhenContextReloadsThenSessionEventsKeepTheirOriginalAges() async throws {
        var date = Date(timeIntervalSince1970: 1000)
        let session = CPMAppSessionDiagnostics(appVersionChange: nil, launchDate: date)
        date += 60
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false,
                                                      now: { date }, appSession: session)
        recorder.extensionDidUpdate(type: .embedded)
        let context = try await makeContext()
        recorder.contextWillLoad(context)
        XCTAssertEqual(episodeParameters(recorder.snapshot())["bg_events"], "extension_updated@30s,load@30s")
        XCTAssertEqual(recorder.snapshot().secondsSinceAppLaunch, 60)

        date += 60
        recorder.contextWillLoad(context)
        XCTAssertEqual(episodeParameters(recorder.snapshot())["bg_events"], "extension_updated@2m,load@30s")
        XCTAssertEqual(recorder.snapshot().secondsSinceAppLaunch, 120)
    }

    func testWhenOtherExtensionUpdatesOrCPMReloadsThenNoUpdateEventIsAdded() async throws {
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false)
        let context = try await makeContext()
        recorder.contextWillLoad(context)
        recorder.extensionDidUpdate(type: .adBlockingExtension)
        recorder.contextWillLoad(context)
        XCTAssertEqual(recorder.snapshot().backgroundEvents.map(\.token), ["load"])
        recorder.extensionDidUpdate(type: .embedded)
        XCTAssertEqual(recorder.snapshot().backgroundEvents.map(\.token), ["load", "extension_updated"])
    }

    func testWhenBaseURLChangesAcrossUnloadThenRecordsChangeWithoutURL() async throws {
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false,
                                                      now: { Date(timeIntervalSince1970: 1000) })
        let context = try await makeContext()
        context.baseURL = try XCTUnwrap(URL(string: "webkit-extension://first/"))
        recorder.contextWillLoad(context)
        XCTAssertEqual(recorder.snapshot().backgroundEvents.map(\.token), ["load"])
        recorder.contextDidUnload(identifier: context.uniqueIdentifier)

        let replacement = try await makeContext()
        replacement.baseURL = try XCTUnwrap(URL(string: "webkit-extension://second/"))
        recorder.contextWillLoad(replacement)
        XCTAssertEqual(episodeParameters(recorder.snapshot())["bg_events"], "load@30s,base_url_changed@30s")

        recorder.contextWillLoad(replacement)
        XCTAssertEqual(recorder.snapshot().backgroundEvents.map(\.token), ["load"])
    }

    func testWhenContextIdentifierChangesThenDoesNotCompareBaseURLs() async throws {
        let recorder = CPMMessagingDiagnosticsRecorder(tabResolver: { _ in nil }, observesMemoryPressure: false)
        let context = try await makeContext()
        context.baseURL = try XCTUnwrap(URL(string: "webkit-extension://first/"))
        recorder.contextWillLoad(context)

        let replacement = try await makeContext()
        replacement.uniqueIdentifier = "another-extension"
        replacement.baseURL = try XCTUnwrap(URL(string: "webkit-extension://second/"))
        recorder.contextWillLoad(replacement)
        XCTAssertEqual(recorder.snapshot().backgroundEvents.map(\.token), ["load"])
    }

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
        let payload = episodeParameters(snapshot).values.joined()
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
        replacement.baseURL = oldContext.baseURL
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
        replacement.baseURL = oldContext.baseURL
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

private func episodeParameters(_ diagnostics: CPMMessagingDiagnostics) -> [String: String] {
    CPMMessagingEpisodeReport(reason: .other, wasStuck: false, outcome: .failedMeasurementResponse,
                              reloadState: .none, secondsToResponse: 0, diagnostics: diagnostics).pixelParameters
}
